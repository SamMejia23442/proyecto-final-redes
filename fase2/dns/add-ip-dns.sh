#!/bin/bash
# El servicio DNS vive en vm-rrhh-web (snet-datacenter) con una IP SECUNDARIA propia: 10.0.0.105.
# Motivo: Azure for Students limita a 6 vCPU por región y el mínimo disponible es 2 vCPU por VM;
# así queda espacio para una VM cliente de pruebas. El servicio conserva su propia IP, de modo que
# moverlo a una VM dedicada después solo implica trasladar esa IP.
RG=rg-agrosense-prod
NIC=vm-rrhh-webVMNic
az network nic ip-config create -g $RG --nic-name $NIC -n ipconfig-dns \
  --private-ip-address 10.0.0.105 --private-ip-address-version IPv4
