#!/bin/bash
# Crea vm-dns-01 (BIND9) en snet-datacenter, IP privada fija 10.0.0.105, SIN IP pública.
# Autor: Pablo Cabrera 231156
RG=rg-agrosense-prod
VNET=vnet-agrosense-gt
VM_SIZE=${VM_SIZE:-Standard_D2as_v4}   # mismo tamaño que usó Jose (B1s/B2ats_v2 sin capacidad en la región)

az vm create -g $RG -n vm-dns-01 --image Ubuntu2204 --size $VM_SIZE \
  --vnet-name $VNET --subnet snet-datacenter --private-ip-address 10.0.0.105 \
  --public-ip-address "" --nsg "" --storage-sku Standard_LRS \
  --admin-username azureuser --generate-ssh-keys
