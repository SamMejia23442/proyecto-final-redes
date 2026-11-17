#!/bin/bash
# Se ejecuta DENTRO de vm-dmz-web. Uso: sudo bash setup-dmz.sh <dominio-publico>
# Ej: sudo bash setup-dmz.sh agrosense-ventas.chilecentral.cloudapp.azure.com
set -e
DOMINIO="$1"
[ -z "$DOMINIO" ] && { echo "Falta el dominio"; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"

apt-get update -y
apt-get install -y nginx ufw

mkdir -p /var/www/ventas
cp "$DIR/index.html" /var/www/ventas/index.html
sed "s/DOMINIO/$DOMINIO/g" "$DIR/ventas.conf" > /etc/nginx/sites-available/ventas
ln -sf /etc/nginx/sites-available/ventas /etc/nginx/sites-enabled/ventas
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# Hardening: web público, SSH solo desde TI
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from 10.0.0.64/27 to any port 22 proto tcp
ufw --force enable
ufw status verbose
