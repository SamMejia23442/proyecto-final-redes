# DNS interno (BIND9) — Pablo Cabrera 231156

| Dato | Valor |
|---|---|
| VM | `vm-dns-01`, Ubuntu 22.04, sin IP pública |
| Subred / IP | `snet-datacenter` (10.0.0.96/28) / **10.0.0.105** |
| Zona directa | `agrosense.local` |
| Zona inversa | `0.0.10.in-addr.arpa` |
| Reenviador | `168.63.129.16` (resolver de Azure) para nombres de Internet |

## Registros

| Nombre | Tipo | Valor |
|---|---|---|
| ns1.agrosense.local (alias `dns`) | A | 10.0.0.105 |
| **rrhh.agrosense.local** (alias `intranet`) | A | **10.0.0.106** |
| web-dmz.agrosense.local | A | 10.0.0.116 |
| www.agrosense.local | CNAME | agrosense-ventas-gt.brazilsouth.cloudapp.azure.com |
| ti01.agrosense.local | A | 10.0.0.68 |
| ventas01.agrosense.local | A | 10.0.0.4 |

Cada A tiene su PTR en la zona inversa.

## Orden de ejecución (desde una máquina con `az` y permisos sobre `rg-agrosense-prod`)

```bash
bash create-vm.sh
az vm run-command invoke -g rg-agrosense-prod -n vm-dns-01 --command-id RunShellScript --scripts @setup-dns-standalone.sh --query "value[0].message" -o tsv
bash nsg-dns-rules.sh
bash vnet-dns.sh
bash pruebas-dns.sh
```

## Cómo se aplican las reglas de acceso al DNS

Se controla en tres capas (defensa en profundidad):

1. **NSG `nsg-datacenter`**: `Allow-DNS-Internal` (prioridad 115) deja pasar el puerto 53 UDP/TCP hacia 10.0.0.105 solo desde Ventas, TI y Datacenter. Visitas ya tiene bloqueada la salida hacia 10.0.0.0/24 en `nsg-visitas`, y la DMZ en `nsg-dmz`.
2. **BIND9**: `allow-query` y `allow-recursion` limitados a la ACL `internas`. `blackhole { visitas; }` ignora a Visitas. `allow-transfer { none; }` impide transferencias de zona (AXFR). `version` está oculta.
3. **ufw** en la VM: solo el 53 desde las subredes internas y el SSH desde TI.

**Configuración de clientes:** la VNet entrega `10.0.0.105` por DHCP (*Custom DNS* de la VNet). Visitas y la DMZ no pueden llegar a la red interna, así que su NIC usa el DNS de Azure (`168.63.129.16`). El DNS configurado en la NIC tiene prioridad sobre el de la VNet. Así, Visitas sigue resolviendo nombres de Internet, pero `rrhh.agrosense.local` no existe para ella.

## Archivos

- `named.conf.options`, `named.conf.local`, `db.agrosense.local`, `db.10.0.0`: configuración de BIND9 (los archivos que pide el entregable).
- `setup-dns-standalone.sh`: instala y configura todo dentro de la VM (generado a partir de los archivos anteriores).
- `create-vm.sh`, `nsg-dns-rules.sh`, `vnet-dns.sh`, `pruebas-dns.sh`: comandos de Azure CLI.
