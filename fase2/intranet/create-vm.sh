#!/bin/bash
# Crea vm-rrhh-web en snet-datacenter, IP privada fija, SIN IP pública (Azure CLI)
RG=rg-agrosense-prod
VNET=vnet-agrosense-gt
VM_SIZE=Standard_D2as_v4   # Brazil South: B1s/B2ats_v2 sin capacidad; este si

az vm create -g $RG -n vm-rrhh-web --image Ubuntu2204 --size $VM_SIZE \
  --vnet-name $VNET --subnet snet-datacenter --private-ip-address 10.0.0.106 \
  --public-ip-address "" --nsg "" --storage-sku Standard_LRS \
  --admin-username azureuser --generate-ssh-keys
