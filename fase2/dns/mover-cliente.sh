#!/bin/bash
# Mueve vm-cliente-01 a otra subred. Uso: bash mover-cliente.sh <snet-ventas|snet-ti|snet-visitas> <ip>
# Ej: bash mover-cliente.sh snet-ti 10.0.0.68 ; bash mover-cliente.sh snet-visitas 10.0.0.36
# En Visitas la NIC usa el DNS de Azure; en el resto hereda el de la VNet (10.0.0.105).
set -e
RG=rg-agrosense-prod; VNET=vnet-agrosense-gt; VM=vm-cliente-01; NIC=vm-cliente-01VMNic
az vm deallocate -g $RG -n $VM
IPC=$(az network nic show -g $RG -n $NIC --query "ipConfigurations[0].name" -o tsv)
az network nic ip-config update -g $RG --nic-name $NIC -n $IPC --vnet-name $VNET --subnet $1 --private-ip-address $2 -o none
if [ "$1" = snet-visitas ]; then
  az network nic update -g $RG -n $NIC --dns-servers 168.63.129.16 -o none
else
  az network nic update -g $RG -n $NIC --set dnsSettings.dnsServers=[] -o none
fi
az vm start -g $RG -n $VM
az network nic show -g $RG -n $NIC --query "{ip:ipConfigurations[0].privateIPAddress, subred:ipConfigurations[0].subnet.id, dns:dnsSettings.dnsServers}" -o json
