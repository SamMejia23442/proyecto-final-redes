#!/bin/bash
# Regla en nsg-datacenter para que las subredes internas consulten el DNS (puerto 53 UDP/TCP).
# Va antes de Deny-VNet-Inbound (prioridad 4000). Visitas NO está en el origen.
RG=rg-agrosense-prod
az network nsg rule create -g $RG --nsg-name nsg-datacenter -n Allow-DNS-Internal \
  --priority 115 --direction Inbound --access Allow --protocol '*' \
  --source-address-prefixes 10.0.0.0/27 10.0.0.64/27 10.0.0.96/28 \
  --destination-address-prefixes 10.0.0.105/32 --destination-port-ranges 53
