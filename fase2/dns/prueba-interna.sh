#!/bin/bash
# Prueba DNS desde una subred interna (Ventas o TI). Para az vm run-command.
echo "== $(hostname)  IP: $(hostname -I)  DNS: $(resolvectl dns eth0 | cut -d: -f2)"
echo; echo "## 1. Resolución directa (consultando al DNS interno)";  nslookup rrhh.agrosense.local 10.0.0.105
echo "## 2. Nombre corto vía resolver del sistema (dominio de búsqueda)"; nslookup rrhh | tail -3
echo "## 3. Resolución inversa"; nslookup 10.0.0.106 | grep name
echo "## 4. Nombre de Internet (reenviado a Azure DNS)"; nslookup -type=A google.com 10.0.0.105 | tail -3
echo "## 5. Transferencia de zona (debe fallar)"; dig @10.0.0.105 agrosense.local AXFR +short | head -3
echo "## 6. Intranet por nombre"; curl -s -m 5 http://rrhh.agrosense.local | grep -o '<h1>.*</h1>' || echo "sin acceso web"
