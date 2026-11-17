#!/bin/bash
# Configura vm-rrhh-web (autocontenido, para az vm run-command). Corre como root.
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx ufw
mkdir -p /var/www/rrhh
cat > /var/www/rrhh/index.html << 'HTML'
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Intranet RRHH - AgroSense GT</title>
  <style>
    body{font-family:Arial,sans-serif;max-width:720px;margin:48px auto;padding:0 16px;color:#1f2937}
    h1{color:#166534} .box{background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:16px;margin:16px 0}
    small{color:#6b7280}
  </style>
</head>
<body>
  <h1>Intranet de Recursos Humanos</h1>
  <p>Bienvenido al portal interno de <b>AgroSense GT</b>.</p>
  <div class="box">
    <ul>
      <li>Políticas internas y reglamento</li>
      <li>Solicitud de vacaciones y permisos</li>
      <li>Directorio de empleados</li>
    </ul>
  </div>
  <small>Acceso exclusivo desde la red interna (rrhh.agrosense.local).</small>
</body>
</html>
HTML
cat > /etc/nginx/sites-available/rrhh << 'CONF'
# nginx: sitio de la Intranet de RRHH (solo HTTP, solo red interna)
server {
    listen 80;
    server_name rrhh.agrosense.local;
    root /var/www/rrhh;
    index index.html;
    server_tokens off;

    location / {
        try_files $uri $uri/ =404;
    }
}
CONF
ln -sf /etc/nginx/sites-available/rrhh /etc/nginx/sites-enabled/rrhh
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.0.0.64/27 to any port 22 proto tcp
ufw allow from 10.0.0.64/27 to any port 80 proto tcp
ufw allow from 10.0.0.0/27 to any port 80 proto tcp
ufw --force enable
ufw status verbose
echo "--- prueba local ---"
curl -s -H "Host: rrhh.agrosense.local" http://localhost | head -8
