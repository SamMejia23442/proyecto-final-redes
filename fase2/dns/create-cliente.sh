#!/bin/bash
# VM cliente de pruebas (la cuota de 6 vCPU solo permite una). Arranca en snet-ventas (10.0.0.4)
# y se mueve entre subredes con mover-cliente.sh para las capturas de DNS y de bloqueos.
RG=rg-agrosense-prod
VNET=vnet-agrosense-gt
az vm create -g $RG -n vm-cliente-01 --image Ubuntu2204 --size Standard_D2s_v4 \
  --subnet $(az network vnet subnet show -g $RG --vnet-name $VNET -n snet-ventas --query id -o tsv) --private-ip-address 10.0.0.4 \
  --public-ip-address "" --nsg "" --storage-sku Standard_LRS \
  --admin-username azureuser --generate-ssh-keys
