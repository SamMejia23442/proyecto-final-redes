#!/bin/bash
# 1) La VNet entrega 10.0.0.105 como DNS por DHCP a todas las VMs.
# 2) Excepciones por NIC (el DNS de la NIC tiene prioridad sobre el de la VNet):
#    - Visitas: sigue con el DNS de Azure (168.63.129.16). Así tiene Internet pero no resuelve agrosense.local.
#    - DMZ: su NSG le prohíbe salir hacia la red interna, así que también usa el DNS de Azure.
# 3) Cada VM renueva DHCP para tomar el nuevo DNS.
RG=rg-agrosense-prod
VNET=vnet-agrosense-gt

az network vnet update -g $RG -n $VNET --dns-servers 10.0.0.105

for vm in $(az vm list -g $RG --query "[?contains(name,'visitas') || contains(name,'dmz')].name" -o tsv); do
  nic=$(az vm show -g $RG -n $vm --query "networkProfile.networkInterfaces[0].id" -o tsv)
  az network nic update --ids $nic --dns-servers 168.63.129.16 -o none
done

for vm in $(az vm list -g $RG --query "[].name" -o tsv); do
  az vm run-command invoke -g $RG -n $vm --command-id RunShellScript \
    --scripts "networkctl renew eth0; sleep 3; resolvectl dns eth0" --query "value[0].message" -o tsv &
done
wait
