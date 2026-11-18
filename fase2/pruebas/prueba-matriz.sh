#!/bin/bash
# Matriz de pruebas de bloqueos desde vm-cliente-01, en la subred donde esté (Ventas, TI o Visitas).
# Se corre con: az vm run-command invoke -g rg-agrosense-prod -n vm-cliente-01 \
#                 --command-id RunShellScript --scripts @prueba-matriz.sh --query "value[0].message" -o tsv
# PERMITIDO = hubo respuesta.  BLOQUEADO = sin respuesta (el NSG o ufw descartan el paquete).
IP=$(hostname -I | awk '{print $1}'); O=${IP##*.}
if   [ "$O" -lt 32 ]; then SUB="snet-ventas"; elif [ "$O" -lt 64 ]; then SUB="snet-visitas"; else SUB="snet-ti"; fi
WEB=agrosense-ventas-gt.brazilsouth.cloudapp.azure.com
echo "== Matriz de bloqueos desde $(hostname) | $IP ($SUB) | $(date '+%F %T')"
printf '%-30s %-22s %s\n' "DESTINO" "PRUEBA" "RESULTADO"
fila() { printf '%-30s %-22s %s\n' "$1" "$2" "$3"; }
tcp()  { timeout 4 bash -c "</dev/tcp/$1/$2" 2>/dev/null && echo "PERMITIDO (puerto abierto)" || echo "BLOQUEADO (sin respuesta)"; }
icmp() { ping -c 2 -W 2 "$1" >/dev/null 2>&1 && echo "PERMITIDO (responde)" || echo "BLOQUEADO (sin respuesta)"; }
http() { c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@"); [ "$c" != "000" ] && echo "PERMITIDO (HTTP $c)" || echo "BLOQUEADO (sin respuesta)"; }
dns()  { r=$(dig +time=2 +tries=1 +short @10.0.0.105 rrhh.agrosense.local 2>/dev/null); [ -n "$r" ] && ! grep -q "timed out" <<<"$r" && echo "PERMITIDO (rrhh -> $r)" || echo "BLOQUEADO (sin respuesta)"; }

fila "DNS interno 10.0.0.105"      "DNS 53/udp"         "$(dns)"
fila "Intranet 10.0.0.106 (DC)"    "HTTP 80"            "$(http -H 'Host: rrhh.agrosense.local' http://10.0.0.106/)"
fila "Intranet 10.0.0.106 (DC)"    "SSH 22"             "$(tcp 10.0.0.106 22)"
fila "Intranet 10.0.0.106 (DC)"    "ICMP ping"          "$(icmp 10.0.0.106)"
fila "Web DMZ 10.0.0.116"          "HTTPS 443"          "$(tcp 10.0.0.116 443)"
fila "Web DMZ 10.0.0.116"          "SSH 22"             "$(tcp 10.0.0.116 22)"
fila "Web DMZ 10.0.0.116"          "ICMP ping"          "$(icmp 10.0.0.116)"
fila "Internet www.google.com"     "HTTPS 443"          "$(http https://www.google.com)"
fila "Web publica (dominio)"       "HTTP 80"            "$(http http://$WEB/)"
fila "Web publica (dominio)"       "HTTPS 443"          "$(http https://$WEB/)"
