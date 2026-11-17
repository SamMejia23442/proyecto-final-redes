#!/bin/bash
# 1) La VNet entrega 10.0.0.105 como DNS por DHCP a todas las VMs.
# 2) Excepción por NIC (el DNS de la NIC tiene prioridad sobre el de la VNet):
#    vm-dmz-web: nsg-dmz le prohíbe salir hacia la red interna, así que usa el DNS de Azure (168.63.129.16).
#    (Una VM en Visitas recibe la misma excepción: ver mover-cliente.sh)
# 3) Las VMs encendidas renuevan DHCP para tomar el nuevo DNS.
RG=rg-agrosense-prod
VNET=vnet-agrosense-gt

az network vnet update -g $RG -n $VNET --dns-servers 10.0.0.105 --query "dhcpOptions" -o tsv
az network nic update -g $RG -n vm-dmz-webVMNic --dns-servers 168.63.129.16 --query "dnsSettings.dnsServers" -o tsv
az vm run-command invoke -g $RG -n vm-rrhh-web --command-id RunShellScript \
  --scripts "networkctl renew eth0; sleep 3; resolvectl dns eth0" --query "value[0].message" -o tsv
