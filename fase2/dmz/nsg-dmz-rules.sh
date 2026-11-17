#!/bin/bash
# Reglas de nsg-dmz (aplicadas el 2026-11-16). nsg-dmz esta asociado a snet-dmz (10.0.0.112/28).
RG=rg-agrosense-prod

# Entrada: web publico desde Internet
az network nsg rule create -g $RG --nsg-name nsg-dmz -n Allow-Web-Internet --priority 100 \
  --direction Inbound --access Allow --protocol Tcp --source-address-prefixes Internet \
  --destination-address-prefixes 10.0.0.112/28 --destination-port-ranges 80 443

# Entrada: administracion SSH solo desde la subred de TI
az network nsg rule create -g $RG --nsg-name nsg-dmz -n Allow-SSH-From-TI --priority 110 \
  --direction Inbound --access Allow --protocol Tcp --source-address-prefixes 10.0.0.64/27 \
  --destination-address-prefixes 10.0.0.112/28 --destination-port-ranges 22

# Salida: la DMZ no inicia conexiones hacia la red interna (contencion si la DMZ es comprometida)
az network nsg rule create -g $RG --nsg-name nsg-dmz -n Deny-DMZ-To-VNet --priority 100 \
  --direction Outbound --access Deny --protocol '*' --source-address-prefixes 10.0.0.112/28 \
  --destination-address-prefixes 10.0.0.0/24 --destination-port-ranges '*'
