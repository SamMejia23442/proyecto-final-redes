#!/bin/bash
# nsg-reglas.sh — Firewall/ACLs de AgroSense GT en Azure (reglas NSG de la Fase 2)
# CC3067 Redes — Proyecto Final, Fase 2
#
# Deja los 5 NSG exactamente como quedaron desplegados el 17/11/2026 (verificado con
# "az network nsg rule list" y "az network watcher test-ip-flow"; ver fase2/evidencias/).
# Se puede correr varias veces: "nsg rule create" crea o actualiza la regla, y los NSG y
# la subred de la DMZ solo se crean si no existen (recrear un NSG borraría sus reglas).
#
# Requisitos del enunciado que cubre:
#   - Visitas tiene Internet, pero NO acceso a las subredes internas  -> nsg-visitas
#   - TI llega a todas las subredes; las demás NO llegan a TI          -> nsg-ti
#   - La intranet es accesible desde las demás subredes, excepto
#     Visitas, y NO desde Internet (no tiene IP pública)               -> nsg-datacenter
#   - DMZ aislada: recibe web desde Internet y no puede iniciar
#     conexiones hacia la red interna                                  -> nsg-dmz
#
# Cómo evalúa Azure:
#   - Gana la regla de MENOR número de prioridad (100-4096); al primer acierto se detiene.
#   - Los NSG son "stateful": si una conexión se permite, su respuesta vuelve sola.
#   - Todo NSG trae reglas por defecto (65000+): AllowVnetInBound permite TODO el tráfico
#     entre subredes de la VNet. Por eso cada aislamiento necesita un Deny explícito.
#   - 168.63.129.16 (DNS/DHCP de Azure) no se bloquea con reglas hacia "Internet".
set -e
RG=rg-agrosense-prod
VNET=vnet-agrosense-gt
LOC=brazilsouth

VENTAS=10.0.0.0/27; VISITAS=10.0.0.32/27; TI=10.0.0.64/27; DC=10.0.0.96/28
DMZ=10.0.0.112/28; VNET_CIDR=10.0.0.0/24
DNS_IP=10.0.0.105/32; INTRANET_IP=10.0.0.106/32

# --- NSG y subred de la DMZ (solo si no existen) ------------------------------------
for n in ventas visitas ti datacenter dmz; do
  az network nsg show -g $RG -n nsg-$n -o none 2>/dev/null || \
    az network nsg create -g $RG -n nsg-$n -l $LOC -o none
done
az network vnet subnet show -g $RG --vnet-name $VNET -n snet-dmz -o none 2>/dev/null || \
  az network vnet subnet create -g $RG --vnet-name $VNET -n snet-dmz \
    --address-prefixes $DMZ -o none

rule() { az network nsg rule create -g $RG -o none "$@"; }

# --- nsg-ventas: sin reglas propias -------------------------------------------------
# Ventas usa las reglas por defecto. Quién puede entrar a Ventas lo deciden los NSG
# de origen (Visitas y la DMZ tienen Deny de salida hacia la VNet).

# --- nsg-visitas (SALIDA): aislada de la red interna, solo web hacia Internet -------
rule --nsg-name nsg-visitas -n Deny-Internal-VNet --priority 110 --direction Outbound \
  --access Deny --protocol '*' --source-address-prefixes '*' \
  --destination-address-prefixes $VNET_CIDR --destination-port-ranges '*'
rule --nsg-name nsg-visitas -n Allow-Web-Internet --priority 120 --direction Outbound \
  --access Allow --protocol Tcp --source-address-prefixes $VISITAS \
  --destination-address-prefixes Internet --destination-port-ranges 80 443
rule --nsg-name nsg-visitas -n Deny-Other-Internet --priority 4000 --direction Outbound \
  --access Deny --protocol '*' --source-address-prefixes $VISITAS \
  --destination-address-prefixes Internet --destination-port-ranges '*'

# --- nsg-ti (ENTRADA): nadie de la VNet entra a TI, salvo los equipos de TI ----------
rule --nsg-name nsg-ti -n Allow-TI-Intra --priority 100 --direction Inbound \
  --access Allow --protocol '*' --source-address-prefixes $TI \
  --destination-address-prefixes $TI --destination-port-ranges '*'
rule --nsg-name nsg-ti -n Deny-Inbound-VNet --priority 4000 --direction Inbound \
  --access Deny --protocol '*' --source-address-prefixes $VNET_CIDR \
  --destination-address-prefixes '*' --destination-port-ranges '*'

# --- nsg-datacenter (ENTRADA): DNS, intranet y administración desde TI; resto Deny ---
rule --nsg-name nsg-datacenter -n Deny-DNS-From-Visitas --priority 110 \
  --direction Inbound --access Deny --protocol '*' --source-address-prefixes $VISITAS \
  --destination-address-prefixes $DNS_IP --destination-port-ranges 53
rule --nsg-name nsg-datacenter -n Allow-DNS-Internal --priority 115 --direction Inbound \
  --access Allow --protocol '*' --source-address-prefixes $VENTAS $TI $DC \
  --destination-address-prefixes $DNS_IP --destination-port-ranges 53
rule --nsg-name nsg-datacenter -n Allow-Intranet-Web --priority 120 --direction Inbound \
  --access Allow --protocol Tcp --source-address-prefixes $VENTAS $TI $DC \
  --destination-address-prefixes $INTRANET_IP --destination-port-ranges 80
rule --nsg-name nsg-datacenter -n Allow-SSH-From-TI --priority 130 --direction Inbound \
  --access Allow --protocol Tcp --source-address-prefixes $TI \
  --destination-address-prefixes '*' --destination-port-ranges 22
rule --nsg-name nsg-datacenter -n Allow-ICMP-From-TI --priority 135 --direction Inbound \
  --access Allow --protocol Icmp --source-address-prefixes $TI \
  --destination-address-prefixes $DC --destination-port-ranges '*'
rule --nsg-name nsg-datacenter -n Deny-VNet-Inbound --priority 4000 --direction Inbound \
  --access Deny --protocol '*' --source-address-prefixes $VNET_CIDR \
  --destination-address-prefixes '*' --destination-port-ranges '*'

# --- nsg-dmz: web pública desde Internet, SSH solo desde TI, sin salida a la VNet -----
rule --nsg-name nsg-dmz -n Allow-Web-Internet --priority 100 --direction Inbound \
  --access Allow --protocol Tcp --source-address-prefixes Internet \
  --destination-address-prefixes $DMZ --destination-port-ranges 80 443
rule --nsg-name nsg-dmz -n Allow-SSH-From-TI --priority 110 --direction Inbound \
  --access Allow --protocol Tcp --source-address-prefixes $TI \
  --destination-address-prefixes $DMZ --destination-port-ranges 22
rule --nsg-name nsg-dmz -n Deny-DMZ-To-VNet --priority 100 --direction Outbound \
  --access Deny --protocol '*' --source-address-prefixes $DMZ \
  --destination-address-prefixes $VNET_CIDR --destination-port-ranges '*'

# --- Asociación de cada NSG a su subred ---------------------------------------------
for n in ventas visitas ti datacenter dmz; do
  az network vnet subnet update -g $RG --vnet-name $VNET -n snet-$n \
    --network-security-group nsg-$n -o none
done

# --- Verificación -------------------------------------------------------------------
az network vnet subnet list -g $RG --vnet-name $VNET \
  --query "[].{Subred:name, Prefijo:addressPrefix, NSG:networkSecurityGroup.id}" \
  -o tsv | sed 's#/subscriptions/.*/##' | column -t
Q="sort_by([], &priority)[].{Regla:name, Prio:priority, Dir:direction, Acceso:access,"
Q+=" Proto:protocol, Origen:sourceAddressPrefix || join(',', sourceAddressPrefixes),"
Q+=" Destino:destinationAddressPrefix || join(',', destinationAddressPrefixes),"
Q+=" Puertos:destinationPortRange || join(',', destinationPortRanges)}"
for n in ventas visitas ti datacenter dmz; do
  echo "--- nsg-$n"
  az network nsg rule list -g $RG --nsg-name nsg-$n --query "$Q" -o table
done
