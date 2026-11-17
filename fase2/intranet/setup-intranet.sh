#!/bin/bash
# Se ejecuta DENTRO de vm-rrhh-web (10.0.0.106). Uso: sudo bash setup-intranet.sh
# Requiere que index.html y rrhh.conf estén en el mismo directorio que este script.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

apt-get update -y
apt-get install -y nginx ufw

mkdir -p /var/www/rrhh
cp "$DIR/index.html" /var/www/rrhh/index.html
cp "$DIR/rrhh.conf" /etc/nginx/sites-available/rrhh
ln -sf /etc/nginx/sites-available/rrhh /etc/nginx/sites-enabled/rrhh
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# Hardening: solo web desde Ventas/TI y SSH desde TI
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.0.0.64/27 to any port 22 proto tcp   # SSH solo TI
ufw allow from 10.0.0.64/27 to any port 80 proto tcp   # web desde TI
ufw allow from 10.0.0.0/27  to any port 80 proto tcp   # web desde Ventas
ufw --force enable
ufw status verbose

curl -s -H "Host: rrhh.agrosense.local" http://localhost | head -5
