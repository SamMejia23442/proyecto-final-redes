#!/bin/bash
# Reglas de DNS en nsg-datacenter. Sin una regla Deny propia, la regla por defecto AllowVnetInBound
# dejaría pasar a Visitas, así que se niega explícitamente antes del Allow.
RG=rg-agrosense-prod

az network nsg rule create -g $RG --nsg-name nsg-datacenter -n Deny-DNS-From-Visitas \
  --priority 110 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes 10.0.0.32/27 \
  --destination-address-prefixes 10.0.0.105/32 --destination-port-ranges 53

az network nsg rule create -g $RG --nsg-name nsg-datacenter -n Allow-DNS-Internal \
  --priority 115 --direction Inbound --access Allow --protocol '*' \
  --source-address-prefixes 10.0.0.0/27 10.0.0.64/27 10.0.0.96/28 \
  --destination-address-prefixes 10.0.0.105/32 --destination-port-ranges 53
