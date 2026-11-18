#!/bin/bash
# Pruebas desde un servidor (vm-rrhh-web en el Data Center o vm-dmz-web en la DMZ) hacia la VM cliente.
# Uso: az vm run-command invoke -g rg-agrosense-prod -n <vm> --command-id RunShellScript \
#        --scripts @prueba-servidor.sh --parameters <ip-del-cliente> --query "value[0].message" -o tsv
CLI=${1:-10.0.0.4}; O=${CLI##*.}
if   [ "$O" -lt 32 ]; then SUB="Ventas"; elif [ "$O" -lt 64 ]; then SUB="Visitas"; else SUB="TI"; fi
echo "== Pruebas desde $(hostname) | $(hostname -I | xargs) | $(date '+%F %T')"
printf '%-30s %-14s %s\n' "DESTINO" "PRUEBA" "RESULTADO"
fila() { printf '%-30s %-14s %s\n' "$1" "$2" "$3"; }
tcp()  { timeout 4 bash -c "</dev/tcp/$1/$2" 2>/dev/null && echo "PERMITIDO (puerto abierto)" || echo "BLOQUEADO (sin respuesta)"; }
icmp() { ping -c 2 -W 2 "$1" >/dev/null 2>&1 && echo "PERMITIDO (responde)" || echo "BLOQUEADO (sin respuesta)"; }
http() { c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@"); [ "$c" != "000" ] && echo "PERMITIDO (HTTP $c)" || echo "BLOQUEADO (sin respuesta)"; }
fila "Cliente $CLI ($SUB)" "ICMP ping" "$(icmp $CLI)"
if [ "$(hostname)" = "vm-dmz-web" ]; then
  fila "Intranet 10.0.0.106 (DC)" "HTTP 80" "$(http -H 'Host: rrhh.agrosense.local' http://10.0.0.106/)"
  fila "DNS interno 10.0.0.105"   "DNS 53/tcp" "$(tcp 10.0.0.105 53)"
  fila "Intranet 10.0.0.106 (DC)" "ICMP ping" "$(icmp 10.0.0.106)"
  fila "Internet www.google.com"  "HTTPS 443" "$(http https://www.google.com)"
fi
