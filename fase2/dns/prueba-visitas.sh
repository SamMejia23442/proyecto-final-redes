#!/bin/bash
# Prueba DNS desde Visitas: tiene Internet, pero no puede usar el DNS interno ni resolver agrosense.local.
echo "== $(hostname)  IP: $(hostname -I)  DNS: $(resolvectl dns eth0 | cut -d: -f2)"
echo; echo "## 1. Consulta directa al DNS interno (debe dar timeout)"; nslookup -timeout=3 -retry=1 rrhh.agrosense.local 10.0.0.105
echo "## 2. Nombre interno con su DNS (Azure): no existe"; nslookup rrhh.agrosense.local 168.63.129.16 | tail -2
echo "## 3. Internet sí funciona"; nslookup -type=A google.com | tail -3; curl -s -o /dev/null -w "HTTP %{http_code} google.com\n" -m 5 http://google.com
