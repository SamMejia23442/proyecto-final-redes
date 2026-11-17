#!/bin/bash
# Configura BIND9 en vm-rrhh-web con la IP de servicio 10.0.0.105. Autocontenido (az vm run-command). Corre como root.
# Generado a partir de named.conf.options, named.conf.local, db.agrosense.local y db.10.0.0
set -e
export DEBIAN_FRONTEND=noninteractive

# 1) IP secundaria en el sistema operativo (Azure solo entrega la primaria por DHCP)
cat > /etc/netplan/60-dns-ip.yaml << 'CONF'
network:
  version: 2
  ethernets:
    eth0:
      addresses: [10.0.0.105/28]
CONF
chmod 600 /etc/netplan/60-dns-ip.yaml
netplan apply
sleep 3
ip -4 -o addr show eth0

# 2) BIND9
apt-get update -y
apt-get install -y bind9 bind9-utils dnsutils
mkdir -p /etc/bind/zones
cat > /etc/bind/named.conf.options << 'CONF'
// /etc/bind/named.conf.options  (vm-dns-01, 10.0.0.105)
// Resolver interno de AgroSense GT. Autoritativo para agrosense.local y
// recursivo (vía Azure DNS) SOLO para las subredes internas.

acl internas {
    10.0.0.0/27;     // snet-ventas
    10.0.0.64/27;    // snet-ti
    10.0.0.96/28;    // snet-datacenter
    127.0.0.1;
};

acl visitas {
    10.0.0.32/27;    // snet-visitas: no debe conocer los nombres internos
};

options {
    directory "/var/cache/bind";

    listen-on { 10.0.0.105; 127.0.0.1; };
    listen-on-v6 { none; };

    // Control de acceso (defensa en profundidad además del NSG y ufw)
    blackhole        { visitas; };   // ignora por completo a Visitas
    allow-query      { internas; };
    allow-recursion  { internas; };
    allow-transfer   { none; };      // nadie puede descargar la zona (AXFR)

    // Lo que no es agrosense.local se reenvía al resolver de Azure
    recursion yes;
    forwarders { 168.63.129.16; };
    forward only;

    dnssec-validation auto;
    version "no disponible";         // hardening: no revelar versión de BIND
};
CONF
cat > /etc/bind/named.conf.local << 'CONF'
// /etc/bind/named.conf.local  (vm-dns-01)
// Zona directa y zona inversa de la red interna 10.0.0.0/24

zone "agrosense.local" {
    type master;
    file "/etc/bind/zones/db.agrosense.local";
};

zone "0.0.10.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.10.0.0";
};
CONF
cat > /etc/bind/zones/db.agrosense.local << 'CONF'
; /etc/bind/zones/db.agrosense.local  - zona directa interna de AgroSense GT
$TTL    3600
@       IN  SOA ns1.agrosense.local. admin.agrosense.local. (
                2026111601  ; serial (AAAAMMDDnn) - subirlo en cada cambio
                3600        ; refresh
                900         ; retry
                604800      ; expire
                300 )       ; TTL negativo
;
@           IN  NS      ns1.agrosense.local.
;
; Servicios
ns1         IN  A       10.0.0.105      ; vm-dns-01 (este servidor)
dns         IN  CNAME   ns1
rrhh        IN  A       10.0.0.106      ; vm-rrhh-web - Intranet de RRHH
intranet    IN  CNAME   rrhh
web-dmz     IN  A       10.0.0.116      ; vm-dmz-web (IP privada en la DMZ)
www         IN  CNAME   agrosense-ventas-gt.brazilsouth.cloudapp.azure.com.  ; web pública
;
; Hosts por subred
ti01        IN  A       10.0.0.68       ; vm-ti-01     (snet-ti)
ventas01    IN  A       10.0.0.4        ; vm-ventas-01 (snet-ventas)
CONF
cat > /etc/bind/zones/db.10.0.0 << 'CONF'
; /etc/bind/zones/db.10.0.0  - zona inversa 10.0.0.0/24
$TTL    3600
@       IN  SOA ns1.agrosense.local. admin.agrosense.local. (
                2026111601 3600 900 604800 300 )
@       IN  NS      ns1.agrosense.local.
;
4       IN  PTR     ventas01.agrosense.local.
68      IN  PTR     ti01.agrosense.local.
105     IN  PTR     ns1.agrosense.local.
106     IN  PTR     rrhh.agrosense.local.
116     IN  PTR     web-dmz.agrosense.local.
CONF
chown -R root:bind /etc/bind/zones && chmod 640 /etc/bind/zones/*
sed -i 's/^OPTIONS=.*/OPTIONS="-u bind -4"/' /etc/default/named
named-checkconf
named-checkzone agrosense.local /etc/bind/zones/db.agrosense.local
named-checkzone 0.0.10.in-addr.arpa /etc/bind/zones/db.10.0.0
systemctl enable named
systemctl restart named

# 3) ufw: se AGREGAN reglas (sin reset, para no borrar las de la intranet). DNS solo desde subredes internas.
for net in 10.0.0.0/27 10.0.0.64/27 10.0.0.96/28; do
  ufw allow from $net to 10.0.0.105 port 53 proto udp comment 'DNS interno'
  ufw allow from $net to 10.0.0.105 port 53 proto tcp comment 'DNS interno'
done
ufw status numbered

echo "--- prueba local ---"
dig +short @10.0.0.105 rrhh.agrosense.local
dig +short @10.0.0.105 -x 10.0.0.106
dig +short @10.0.0.105 google.com | head -2
