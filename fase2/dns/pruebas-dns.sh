#!/bin/bash
# Pruebas para las capturas: nslookup desde Ventas y TI (deben resolver) y desde Visitas (no debe).
RG=rg-agrosense-prod
run() { echo "===== $1"; az vm run-command invoke -g $RG -n $1 --command-id RunShellScript --scripts "$2" --query "value[0].message" -o tsv; }

PRUEBA='hostname; resolvectl dns eth0; nslookup rrhh.agrosense.local; nslookup -type=PTR 10.0.0.106; nslookup google.com | tail -3; curl -s -m 5 http://rrhh.agrosense.local | grep -o "<h1>.*</h1>"'
run vm-ventas-01 "$PRUEBA"
run vm-ti-01     "$PRUEBA"
# Visitas consultando directo a 10.0.0.105 -> timeout (NSG + blackhole de BIND + ufw)
for vm in $(az vm list -g $RG --query "[?contains(name,'visitas')].name" -o tsv); do
  run $vm 'hostname; nslookup -timeout=3 rrhh.agrosense.local 10.0.0.105; nslookup rrhh.agrosense.local; nslookup google.com | tail -3'
done
