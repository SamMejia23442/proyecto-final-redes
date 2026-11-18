#!/usr/bin/env bash
# hardening.sh — Hardening básico de las VMs de AgroSense GT
# CC3067 Redes — Proyecto Final, Fase 2
#
# Aplica tres medidas en cada VM:
#   1. Deshabilita servicios innecesarios y elimina protocolos en texto plano.
#   2. Endurece SSH (sin root, límite de intentos y, si hay llave, sin contraseña).
#   3. Asegura ufw con política "denegar todo lo entrante" y AGREGA las reglas
#      del rol. No borra reglas existentes: no usa "ufw reset", para no romper
#      las reglas de DNS (setup-dns.sh) ni las de nginx ya aplicadas.
#
# VMs y roles:
#   rrhh     vm-rrhh-web  (10.0.0.106 intranet + 10.0.0.105 DNS BIND9)
#            -> 22 desde TI, 80 desde Ventas y TI,
#               53 TCP/UDP hacia 10.0.0.105 desde Ventas, TI y Data Center
#   dmz      vm-dmz-web   (10.0.0.116, snet-dmz)
#            -> 22 desde TI, 80 y 443 desde cualquier origen
#   cliente  vm-cliente-01 (VM de pruebas)
#            -> 22 desde TI
#
# Uso por SSH:
#   sudo ./hardening.sh <rol> [usuario_admin]
#
# Uso con Azure Run Command (desde Cloud Shell, con el archivo subido):
#   az vm run-command invoke -g rg-agrosense-prod -n vm-rrhh-web \
#     --command-id RunShellScript --scripts @hardening.sh --parameters rrhh
#
# Variables opcionales:
#   SSH_FROM       Origen de SSH.                Default: 10.0.0.64/27 (TI)
#   INTRANET_FROM  Orígenes HTTP de la intranet. Default: Ventas y TI
#   DNS_FROM       Orígenes de consultas DNS.    Default: Ventas, TI y Data Center
#   ALLOW_USERS    Si se define, solo esos usuarios pueden entrar por SSH.
#
# La evidencia queda en /var/log/hardening/ y también se imprime al final.
set -euo pipefail

# --- Direccionamiento de AgroSense GT (vnet-agrosense-gt 10.0.0.0/24) ---------
NET_VENTAS="10.0.0.0/27"
NET_TI="10.0.0.64/27"
NET_DATACENTER="10.0.0.96/28"
DNS_IP="10.0.0.105"        # IP secundaria de vm-rrhh-web donde escucha BIND9

ROL="${1:-${ROL:-}}"
ADMIN_USER="${2:-${ADMIN_USER:-${SUDO_USER:-}}}"
SSH_FROM="${SSH_FROM:-$NET_TI}"
INTRANET_FROM="${INTRANET_FROM:-$NET_VENTAS $NET_TI}"
DNS_FROM="${DNS_FROM:-$NET_VENTAS $NET_TI $NET_DATACENTER}"
ALLOW_USERS="${ALLOW_USERS:-}"
LOG_DIR="/var/log/hardening"
SSH_DROPIN="/etc/ssh/sshd_config.d/00-hardening.conf"

SERVICIOS_INNECESARIOS=(avahi-daemon.service avahi-daemon.socket cups.service cups.socket
                        cups-browsed.service rpcbind.service rpcbind.socket
                        ModemManager.service postfix.service)
PAQUETES_INSEGUROS=(telnetd inetutils-telnetd telnet rsh-server rsh-client xinetd vsftpd tftpd-hpa)

# Colores solo si la salida es una terminal (Run Command no lo es).
if [[ -t 1 ]]; then C_B=$'\033[1;34m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'; C_R=$'\033[1;31m'; C_0=$'\033[0m'
else C_B=""; C_G=""; C_Y=""; C_R=""; C_0=""; fi
info()  { printf '\n%s[*]%s %s\n' "$C_B" "$C_0" "$*"; }
ok()    { printf '%s[ok]%s %s\n' "$C_G" "$C_0" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*"; }
error() { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

uso() { sed -n '2,38p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 1; }

# 0. Validaciones
[[ $EUID -eq 0 ]] || error "Ejecutar con sudo (o mediante Run Command)."
case "$ROL" in rrhh|dmz|cliente) ;; *) uso ;; esac

# Con Run Command el script corre como root y no existe SUDO_USER: se toma el
# primer usuario normal (UID 1000), que en Azure es el administrador de la VM.
if [[ -z "$ADMIN_USER" || "$ADMIN_USER" == "root" ]]; then
  ADMIN_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
fi
[[ -n "$ADMIN_USER" ]] || error "No se pudo determinar el usuario administrador; pasarlo como segundo argumento."
id "$ADMIN_USER" >/dev/null 2>&1 || error "El usuario '$ADMIN_USER' no existe."

mkdir -p "$LOG_DIR"
info "Hardening de $(hostname) | rol: $ROL | admin: $ADMIN_USER | $(date '+%F %T')"

# 1. Evidencia inicial
ss -tulpn > "$LOG_DIR/puertos_antes.txt"
(ufw status numbered 2>/dev/null || echo "ufw no instalado") > "$LOG_DIR/ufw_antes.txt"
ok "Estado inicial guardado (puertos y reglas ufw)"

# 2. Servicios y paquetes innecesarios

info "Deshabilitando servicios innecesarios"
for svc in "${SERVICIOS_INNECESARIOS[@]}"; do
  if systemctl list-unit-files "$svc" --no-legend 2>/dev/null | grep -q .; then
    systemctl disable --now "$svc" >/dev/null 2>&1 || true
    systemctl mask "$svc" >/dev/null 2>&1 || true
    ok "Deshabilitado y enmascarado: $svc"
  fi
done

info "Eliminando paquetes de protocolos inseguros"
a_eliminar=()
for pkg in "${PAQUETES_INSEGUROS[@]}"; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then a_eliminar+=("$pkg"); fi
done
if (( ${#a_eliminar[@]} > 0 )); then
  DEBIAN_FRONTEND=noninteractive apt-get purge -y "${a_eliminar[@]}" >/dev/null
  ok "Eliminados: ${a_eliminar[*]}"
else
  ok "No había paquetes inseguros instalados"
fi

# 3. SSH
info "Endureciendo SSH"
HOME_ADMIN="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
AUTH_KEYS="$HOME_ADMIN/.ssh/authorized_keys"

# La contraseña solo se desactiva si existe una llave pública válida;
# de lo contrario, nadie podría volver a entrar por SSH.
if [[ -s "$AUTH_KEYS" ]] && grep -qE '^(ssh-|ecdsa-|sk-)' "$AUTH_KEYS"; then
  DESACTIVAR_PASSWORD=1
  ok "Llave pública encontrada en $AUTH_KEYS"
else
  DESACTIVAR_PASSWORD=0
  warn "No hay llave en $AUTH_KEYS: se mantiene la contraseña para no perder el acceso"
fi

# sshd conserva el PRIMER valor que lee de cada directiva. Las imágenes de
# Ubuntu en Azure incluyen 50-cloudimg-settings.conf; con el prefijo 00 este
# archivo se lee antes y sus valores prevalecen.
{
  echo "# Generado por hardening.sh — CC3067 Proyecto Final Fase 2"
  echo "PermitRootLogin no"
  echo "PubkeyAuthentication yes"
  if [[ "$DESACTIVAR_PASSWORD" == "1" ]]; then
    echo "PasswordAuthentication no"
    echo "KbdInteractiveAuthentication no"
  fi
  echo "PermitEmptyPasswords no"
  echo "MaxAuthTries 3"
  echo "LoginGraceTime 30"
  echo "X11Forwarding no"
  echo "AllowAgentForwarding no"
  if [[ -n "$ALLOW_USERS" ]]; then echo "AllowUsers $ALLOW_USERS"; fi
} > "$SSH_DROPIN"
chmod 644 "$SSH_DROPIN"

grep -qE '^\s*Include\s+/etc/ssh/sshd_config.d/\*\.conf' /etc/ssh/sshd_config \
  || warn "sshd_config no incluye sshd_config.d/*.conf; revisar manualmente"

if sshd -t; then
  systemctl reload ssh 2>/dev/null || systemctl reload sshd
  ok "SSH recargado"
else
  rm -f "$SSH_DROPIN"
  error "Configuración de SSH inválida; se revirtió el cambio"
fi

# 4. Firewall del host (ufw) — modo aditivo, sin reset
info "Configurando ufw para el rol '$ROL'"
command -v ufw >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y ufw >/dev/null

ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null

# "ufw allow" omite las reglas que ya existen, así que repetir el script no
# duplica nada. Las reglas de SSH, intranet y DNS se escriben con el mismo
# formato que las aplicadas por setup-dns.sh y por la configuración de la
# intranet, para que coincidan con ellas en lugar de crear reglas paralelas.
# SSH se agrega ANTES de activar ufw para no cortar la sesión.
permitir() { ufw allow "$@" >/dev/null; }

for red in $SSH_FROM; do
  permitir from "$red" to any port 22 proto tcp
done

case "$ROL" in
  rrhh)
    for red in $INTRANET_FROM; do
      permitir from "$red" to any port 80 proto tcp
    done
    for red in $DNS_FROM; do
      permitir from "$red" to "$DNS_IP" port 53 proto udp comment "DNS interno"
      permitir from "$red" to "$DNS_IP" port 53 proto tcp comment "DNS interno"
    done
    ;;
  dmz)
    # 80 abierto para la redirección 301 a HTTPS y el reto HTTP-01 de Let's Encrypt.
    permitir 80/tcp  comment "HTTP publico (redireccion a HTTPS)"
    permitir 443/tcp comment "HTTPS publico"
    ;;
  cliente) : ;;
esac

ufw logging low >/dev/null
ufw --force enable >/dev/null
ok "ufw activo"

# 5. Evidencia final
ss -tulpn > "$LOG_DIR/puertos_despues.txt"
ufw status verbose > "$LOG_DIR/ufw_despues.txt"
sshd -T 2>/dev/null | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|maxauthtries|allowusers|x11forwarding) ' \
  > "$LOG_DIR/ssh_efectivo.txt" || true

echo
echo "===== $(hostname) — ufw ====="
cat "$LOG_DIR/ufw_despues.txt"
echo
echo "===== $(hostname) — SSH efectivo ====="
cat "$LOG_DIR/ssh_efectivo.txt"
echo
echo "===== $(hostname) — puertos en escucha ====="
cat "$LOG_DIR/puertos_despues.txt"
echo
ok "Listo. Evidencia en $LOG_DIR/"
