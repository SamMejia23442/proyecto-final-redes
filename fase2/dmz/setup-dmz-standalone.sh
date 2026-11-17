#!/bin/bash
# Configura vm-dmz-web (autocontenido, para az vm run-command). Corre como root.
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx ufw
mkdir -p /var/www/ventas
cat > /var/www/ventas/index.html << 'HTML'
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AgroSense GT - Agricultura de precisión</title>
  <style>
    body{font-family:Arial,sans-serif;max-width:760px;margin:48px auto;padding:0 16px;color:#1f2937}
    h1{color:#166534} .box{background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:16px;margin:16px 0}
  </style>
</head>
<body>
  <h1>AgroSense GT</h1>
  <p>Riego inteligente y agricultura de precisión para fincas de Guatemala.</p>
  <div class="box">
    <b>Qué hacemos</b>
    <ul>
      <li>Monitoreo en tiempo real de humedad, pH y precipitación</li>
      <li>Alertas de riego basadas en datos</li>
      <li>Analítica para cooperativas e ingenios</li>
    </ul>
  </div>
  <p>Contacto comercial: ventas@agrosense.example</p>
</body>
</html>
HTML
cat > /etc/nginx/sites-available/ventas << 'CONF'
# nginx: sitio público de Ventas (DMZ). Reemplazar agrosense-ventas-gt.brazilsouth.cloudapp.azure.com por el dominio público.
# Tras correr certbot, este archivo queda con HTTPS y redirección HTTP->HTTPS.
server {
    listen 80;
    server_name agrosense-ventas-gt.brazilsouth.cloudapp.azure.com;
    root /var/www/ventas;
    index index.html;
    server_tokens off;

    location / {
        try_files $uri $uri/ =404;
    }
}
CONF
ln -sf /etc/nginx/sites-available/ventas /etc/nginx/sites-enabled/ventas
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from 10.0.0.64/27 to any port 22 proto tcp
ufw --force enable
ufw status verbose
echo "--- prueba local ---"
curl -s http://localhost | head -8
