#!/bin/bash
# Crea vm-dmz-web en snet-dmz con IP pública estática y etiqueta DNS (Azure CLI)
# Requiere que Samuel ya haya creado snet-dmz (10.0.0.112/28) y su NSG.
RG=rg-agrosense-prod
VNET=vnet-agrosense-gt
VM_SIZE=Standard_D2as_v4   # Brazil South: B1s/B2ats_v2 sin capacidad; este si
DNS_LABEL=agrosense-ventas-gt   # -> agrosense-ventas-gt.brazilsouth.cloudapp.azure.com

az vm create -g $RG -n vm-dmz-web --image Ubuntu2204 --size $VM_SIZE \
  --vnet-name $VNET --subnet snet-dmz --private-ip-address 10.0.0.116 \
  --public-ip-address pip-dmz-web --public-ip-sku Standard --public-ip-address-allocation static \
  --public-ip-address-dns-name $DNS_LABEL \
  --nsg "" --storage-sku Standard_LRS \
  --admin-username azureuser --generate-ssh-keys
