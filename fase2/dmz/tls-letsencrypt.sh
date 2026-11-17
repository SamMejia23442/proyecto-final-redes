#!/bin/bash
# PUNTO EXTRA: certificado Let's Encrypt + redirección HTTP->HTTPS
# Uso: sudo bash tls-letsencrypt.sh <dominio-publico> <correo>
# Requiere que el dominio ya resuelva a la IP pública y que el 80/443 estén abiertos.
set -e
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d "$1" -m "$2" --agree-tos --no-eff-email --redirect -n
nginx -t && systemctl reload nginx
curl -sI "http://$1" | head -3
