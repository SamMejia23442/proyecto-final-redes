#!/bin/bash
# Se corre en cada VM Linux cliente del DNS interno (az vm run-command). Corre como root.
# systemd-resolved manda los nombres *.local a mDNS/LLMNR y NO al servidor DNS, salvo que el dominio
# esté configurado en la interfaz. Declarar agrosense.local como dominio de búsqueda en eth0 hace que
# esas consultas vayan al DNS entregado por DHCP (10.0.0.105) y además permite usar nombres cortos (rrhh).
cat > /etc/netplan/61-agrosense-dns.yaml << 'CONF'
network:
  version: 2
  ethernets:
    eth0:
      nameservers:
        search: [agrosense.local]
CONF
chmod 600 /etc/netplan/61-agrosense-dns.yaml
netplan apply
sleep 4
resolvectl status eth0 | grep -E "DNS Servers|DNS Domain"
