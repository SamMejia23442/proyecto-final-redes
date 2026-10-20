# AgroSense GT. Proyecto Final Fase 1 (CC3067 Redes, UVG)
# Despliegue de la red segmentada en Microsoft Azure con Azure CLI
#
# Autores: 
# Eliazar Canastuj 23384
# Pablo Cabrera 231156
# Jose Sanchez 231221
# Ángel Mérida 23661 
# Samuel Mejía 23442
# 



# 
# Variables
# 
RG=rg-agrosense-prod
# Azure for Students limita por política las regiones permitidas
# (se consulta con: az policy assignment list). En westus había cuota, pero
# todos los tamaños tenían restricción de capacidad. Chile Central sí tenía disponibilidad
# (se verifica con: az vm list skus l <region> query "[?restrictions \`[]\`]").
LOC=chilecentral
VNET=vnet-agrosense-gt
VM_SIZE=Standard_B2ats_v2   # 2 vCPU, 1 GiB RAM — familia Basv2


# Requisito previo (una sola vez por suscripción): se registra el proveedor de cómputo
az provider register --namespace Microsoft.Compute --wait


# 
# BLOQUE 1. Grupo de recursos, VNet y subredes (VLSM)
# 
az group create --name $RG --location $LOC

az network vnet create --resource-group $RG --name $VNET \
  --location $LOC --address-prefixes 10.0.0.0/24

az network vnet subnet create -g $RG --vnet-name $VNET -n snet-ventas     --address-prefixes 10.0.0.0/27
az network vnet subnet create -g $RG --vnet-name $VNET -n snet-visitas    --address-prefixes 10.0.0.32/27
az network vnet subnet create -g $RG --vnet-name $VNET -n snet-ti         --address-prefixes 10.0.0.64/27
az network vnet subnet create -g $RG --vnet-name $VNET -n snet-datacenter --address-prefixes 10.0.0.96/28
# Reservas futuras (no se crean): 10.0.0.112/28 y 10.0.0.128/25

# Verificación
az network vnet subnet list -g $RG --vnet-name $VNET \
  --query "[].{Subred:name, Prefijo:addressPrefix}" -o table


# 
# BLOQUE 2. NSGs y reglas
# 
for n in ventas visitas ti datacenter; do
  az network nsg create -g $RG -n nsg-$n -l $LOC
done

# nsg ventas: TI puede hacer ping a Ventas
az network nsg rule create -g $RG --nsg-name nsg-ventas -n Allow-ICMP-From-TI \
  --priority 100 --direction Inbound --access Allow --protocol Icmp \
  --source-address-prefixes 10.0.0.64/27 --destination-address-prefixes 10.0.0.0/27 \
  --destination-port-ranges '*'

# nsg TI: permite pings iniciados desde cualquier subred interna
az network nsg rule create -g $RG --nsg-name nsg-ti -n Allow-ICMP-Internal \
  --priority 100 --direction Inbound --access Allow --protocol Icmp \
  --source-address-prefixes 10.0.0.0/24 --destination-address-prefixes 10.0.0.64/27 \
  --destination-port-ranges '*'

# nsg visitas (SALIDA): aislada de la VNet, solo web hacia Internet
az network nsg rule create -g $RG --nsg-name nsg-visitas -n Deny-Internal-VNet \
  --priority 100 --direction Outbound --access Deny --protocol '*' \
  --source-address-prefixes 10.0.0.32/27 --destination-address-prefixes 10.0.0.0/24 \
  --destination-port-ranges '*'

az network nsg rule create -g $RG --nsg-name nsg-visitas -n Allow-Web-Internet \
  --priority 110 --direction Outbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.0.0.32/27 --destination-address-prefixes Internet \
  --destination-port-ranges 80 443

az network nsg rule create -g $RG --nsg-name nsg-visitas -n Deny-Other-Internet \
  --priority 4000 --direction Outbound --access Deny --protocol '*' \
  --source-address-prefixes 10.0.0.32/27 --destination-address-prefixes Internet \
  --destination-port-ranges '*'

# nsg datacenter: TI administra (SSH + ICMP), Ventas solo al API gateway, resto denegado
az network nsg rule create -g $RG --nsg-name nsg-datacenter -n Allow-SSH-From-TI \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.0.0.64/27 --destination-address-prefixes 10.0.0.96/28 \
  --destination-port-ranges 22

az network nsg rule create -g $RG --nsg-name nsg-datacenter -n Allow-ICMP-From-TI \
  --priority 105 --direction Inbound --access Allow --protocol Icmp \
  --source-address-prefixes 10.0.0.64/27 --destination-address-prefixes 10.0.0.96/28 \
  --destination-port-ranges '*'

az network nsg rule create -g $RG --nsg-name nsg-datacenter -n Allow-API-From-Ventas \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.0.0.0/27 --destination-address-prefixes 10.0.0.104/32 \
  --destination-port-ranges 443

az network nsg rule create -g $RG --nsg-name nsg-datacenter -n Deny-VNet-Inbound \
  --priority 4000 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes VirtualNetwork --destination-address-prefixes 10.0.0.96/28 \
  --destination-port-ranges '*'

# Se asocia cada NSG a su subred
az network vnet subnet update -g $RG --vnet-name $VNET -n snet-ventas     --network-security-group nsg-ventas
az network vnet subnet update -g $RG --vnet-name $VNET -n snet-visitas    --network-security-group nsg-visitas
az network vnet subnet update -g $RG --vnet-name $VNET -n snet-ti         --network-security-group nsg-ti
az network vnet subnet update -g $RG --vnet-name $VNET -n snet-datacenter --network-security-group nsg-datacenter

# Verificación
az network vnet subnet list -g $RG --vnet-name $VNET \
  --query "[].{Subred:name, Prefijo:addressPrefix, NSG:networkSecurityGroup.id}" -o table


# 
# BLOQUE 3. VMs de prueba (Ubuntu, IP privada fija, SIN IP pública)
# 
az vm create -g $RG -n vm-ti-01 --image Ubuntu2204 --size $VM_SIZE \
  --vnet-name $VNET --subnet snet-ti --private-ip-address 10.0.0.68 \
  --public-ip-address "" --nsg "" --storage-sku Standard_LRS \
  --admin-username azureuser --generate-ssh-keys

az vm create -g $RG -n vm-ventas-01 --image Ubuntu2204 --size $VM_SIZE \
  --vnet-name $VNET --subnet snet-ventas --private-ip-address 10.0.0.4 \
  --public-ip-address "" --nsg "" --storage-sku Standard_LRS \
  --admin-username azureuser --generate-ssh-keys

# Verificación
az vm list-ip-addresses -g $RG \
  --query "[].{VM:virtualMachine.name, IP:virtualMachine.network.privateIpAddresses[0]}" -o table


# 
# BLOQUE 4. Prueba de conectividad (ping TI hacia Ventas)
# (Como alternativa para la captura, se usa Portal > vm TI 01 > Run command > RunShellScript)
# 
az vm run-command invoke -g $RG -n vm-ti-01 --command-id RunShellScript \
  --scripts "hostname; ip -4 -o addr show eth0; ping -c 4 10.0.0.4" \
  --query "value[0].message" -o tsv


# 
# BLOQUE 5. Limpieza (se ejecuta al terminar las capturas)
# 
az group delete --name $RG --yes --no-wait
az group list --query "[?name=='$RG'].{Grupo:name, Estado:properties.provisioningState}" -o table
