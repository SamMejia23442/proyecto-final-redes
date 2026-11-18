#!/usr/bin/env bash
# hardening-extra.sh — Complemento de hardening.sh para las VMs de AgroSense GT
# CC3067 Redes — Proyecto Final, Fase 2
#
# hardening.sh ya deja: ufw con "denegar todo lo entrante" + reglas por rol,
# SSH sin root ni contraseña y sin protocolos en texto plano. Este script agrega:
#   1. Parámetros de red del kernel (sysctl): sin redirecciones ICMP, sin source
#      routing, filtro de ruta inversa estricto y registro de paquetes "marcianos".
#   2. Apaga servicios que vienen en la imagen de Ubuntu de Azure y no se usan:
#      snapd, packagekit y multipathd. Quita el cliente ftp (texto plano).
#   3. SSH: sin túneles TCP y desconexión de sesiones inactivas.
#   4. Por rol:
#        rrhh  -> el puerto 80 de la intranet también desde el Data Center
#                 (igual que la regla Allow-Intranet-Web del NSG).
#        dmz   -> cabeceras de seguridad HTTP en el sitio HTTPS (HSTS, nosniff,
#                 anti-clickjacking).
#
# Uso:   sudo ./hardening-extra.sh <rrhh|dmz|cliente>
# Azure: az vm run-command invoke -g rg-agrosense-prod -n vm-rrhh-web \
#          --command-id RunShellScript --scripts @hardening-extra.sh --parameters rrhh
# Se puede repetir sin efectos secundarios.
set -euo pipefail

ROL="${1:-}"
case "$ROL" in rrhh|dmz|cliente) ;; *) echo "Uso: $0 <rrhh|dmz|cliente>"; exit 1 ;; esac
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root"; exit 1; }
LOG_DIR=/var/log/hardening; mkdir -p "$LOG_DIR"
echo "[*] hardening-extra en $(hostname) | rol: $ROL | $(date '+%F %T')"

# 1. Kernel / red
cat > /etc/sysctl.d/60-agrosense-hardening.conf <<'EOF'
# Generado por hardening-extra.sh — CC3067 Proyecto Final Fase 2
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
EOF
sysctl --system >/dev/null
echo "[ok] sysctl aplicado"

# 2. Servicios y paquetes que no se usan
for unit in snapd.service snapd.socket snapd.seeded.service packagekit.service multipathd.service multipathd.socket; do
  if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
    systemctl mask "$unit" >/dev/null 2>&1 || true
    echo "[ok] deshabilitado: $unit"
  fi
done
if dpkg -s ftp >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get purge -y ftp >/dev/null && echo "[ok] eliminado: ftp"
fi

# 3. SSH (01- se lee después de 00-hardening.conf; sshd usa el primer valor de cada directiva)
cat > /etc/ssh/sshd_config.d/01-hardening-extra.conf <<'EOF'
# Generado por hardening-extra.sh — CC3067 Proyecto Final Fase 2
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
if sshd -t; then systemctl reload ssh; echo "[ok] SSH recargado"
else rm -f /etc/ssh/sshd_config.d/01-hardening-extra.conf; echo "[x] SSH inválido, revertido"; exit 1; fi

# 4. Por rol
case "$ROL" in
  rrhh)
    ufw allow from 10.0.0.96/28 to any port 80 proto tcp comment "Intranet desde Data Center" >/dev/null
    echo "[ok] ufw: 80 desde Data Center"
    ;;
  dmz)
    SITE=/etc/nginx/sites-available/ventas
    cat > /etc/nginx/snippets/security-headers.conf <<'EOF'
# Generado por hardening-extra.sh — CC3067 Proyecto Final Fase 2
add_header Strict-Transport-Security "max-age=31536000" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
add_header Referrer-Policy "no-referrer" always;
EOF
    if ! grep -q 'security-headers.conf' "$SITE"; then
      cp "$SITE" "$LOG_DIR/ventas.bak"
      # Solo en el primer bloque server (el de 443); el de 80 solo redirige.
      sed -i '0,/server_tokens off;/s//server_tokens off;\n    include \/etc\/nginx\/snippets\/security-headers.conf;/' "$SITE"
    fi
    if nginx -t 2>/dev/null; then systemctl reload nginx; echo "[ok] nginx: cabeceras de seguridad"
    else cp "$LOG_DIR/ventas.bak" "$SITE"; nginx -t && systemctl reload nginx; echo "[x] nginx inválido, revertido"; fi
    ;;
  cliente) : ;;
esac

# Evidencia
{
  echo "== $(hostname) — puertos en escucha"; ss -tulpn | awk 'NR==1 || /LISTEN|UNCONN/ {print $1, $5, $7}' | column -t
  echo; echo "== ufw"; ufw status verbose
  echo; echo "== SSH efectivo"; sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|maxauthtries|x11forwarding|allowtcpforwarding|allowagentforwarding|clientaliveinterval) '
  echo; echo "== sysctl"; sysctl net.ipv4.conf.all.send_redirects net.ipv4.conf.all.accept_redirects net.ipv4.conf.all.rp_filter net.ipv4.conf.all.log_martians net.ipv4.tcp_syncookies
} | tee "$LOG_DIR/extra_despues.txt"
echo "[ok] Listo. Evidencia en $LOG_DIR/extra_despues.txt"
