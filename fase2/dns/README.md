# DNS interno (BIND9) — Pablo Cabrera 231156

**Estado: desplegado y probado el 2026-11-16** (suscripción Azure for Students, Brazil South).

| Dato | Valor |
|---|---|
| Servidor | BIND 9.18 en `vm-rrhh-web` (snet-datacenter), con **IP de servicio propia 10.0.0.105** (IP secundaria de la NIC) |
| Zona directa | `agrosense.local` |
| Zona inversa | `0.0.10.in-addr.arpa` |
| Reenviador | `168.63.129.16` (resolver de Azure) para nombres de Internet |
| DNS de la VNet | `10.0.0.105` (Custom DNS de `vnet-agrosense-gt`) |

### ¿Por qué no hay una VM de DNS dedicada?
Azure for Students limita a **6 vCPU por región**, y en Brazil South el tamaño más pequeño con capacidad y cuota es de 2 vCPU. `vm-rrhh-web` y `vm-dmz-web` ya usan 4 (las VMs desasignadas también cuentan). Quedaba espacio para **una sola** VM más. Se usó para una **VM cliente de pruebas** (`vm-cliente-01`), sin la cual no habría evidencia desde Ventas, TI ni Visitas. El DNS tiene su propia IP (.105), separada de la web (.106), así que se puede llevar a una VM dedicada solo moviendo esa IP.

## Registros

| Nombre | Tipo | Valor |
|---|---|---|
| ns1.agrosense.local (alias `dns`) | A | 10.0.0.105 |
| **rrhh.agrosense.local** (alias `intranet`) | A | **10.0.0.106** |
| web-dmz.agrosense.local | A | 10.0.0.116 |
| www.agrosense.local | CNAME | agrosense-ventas-gt.brazilsouth.cloudapp.azure.com |
| ventas01.agrosense.local | A | 10.0.0.4 |
| ti01.agrosense.local | A | 10.0.0.68 |

Cada registro A tiene su PTR en la zona inversa.

## Control de acceso al DNS (tres capas)

1. **NSG `nsg-datacenter`**
   - `Deny-DNS-From-Visitas` (prioridad 110): niega 10.0.0.32/27 → 10.0.0.105:53. Hace falta porque la regla por defecto `AllowVnetInBound` dejaría pasar a Visitas, y `nsg-visitas` hoy solo bloquea el puerto 80.
   - `Allow-DNS-Internal` (prioridad 115): permite el 53 UDP/TCP desde Ventas, TI y Datacenter.
2. **BIND9** (`named.conf.options`)
   - `allow-query` y `allow-recursion` limitados a la ACL `internas`.
   - `blackhole { visitas; }` ignora por completo a Visitas.
   - `allow-transfer { none; }` impide transferencias de zona (AXFR).
   - La versión de BIND está oculta y solo escucha en 10.0.0.105 y localhost (IPv4).
3. **ufw** en la VM: el 53 hacia 10.0.0.105 solo desde las subredes internas. Las reglas se *agregan*, sin hacer `reset`, para no borrar las de la intranet.

## Configuración de los clientes

- **VNet → Custom DNS 10.0.0.105:** todas las VMs lo reciben por DHCP.
- **Excepciones por NIC** (el DNS configurado en la NIC tiene prioridad sobre el de la VNet):
  - `vm-dmz-web` usa `168.63.129.16`, porque `nsg-dmz` le prohíbe salir hacia la red interna.
  - Una VM en Visitas también usa `168.63.129.16`: tiene Internet, pero `agrosense.local` no existe para ella.
- **Detalle de Ubuntu:** `systemd-resolved` trata los nombres `*.local` como mDNS y **no los manda al servidor DNS**. Por eso `cliente-dns.sh` declara `agrosense.local` como dominio de búsqueda en eth0 (netplan). Así las consultas de ese dominio van a 10.0.0.105, y además funciona el nombre corto (`nslookup rrhh`).

## Evidencias (`evidencias/`)

| Archivo | Desde | Resultado |
|---|---|---|
| `dns-desde-ventas.txt` | vm-cliente-01 en Ventas (10.0.0.4) | resuelve rrhh, nombre corto, PTR y google.com; AXFR rechazado; la intranet carga por nombre |
| `dns-desde-ti.txt` | vm-cliente-01 en TI (10.0.0.68) | igual que Ventas |
| `dns-desde-visitas.txt` | vm-cliente-01 en Visitas (10.0.0.36) | timeout contra 10.0.0.105, `rrhh.agrosense.local` da NXDOMAIN, Internet funciona |

Para la captura en el portal: **vm-cliente-01 → Ejecutar comando → RunShellScript** y pegar el contenido de `prueba-interna.sh` o `prueba-visitas.sh`.

## Orden de ejecución

```bash
bash add-ip-dns.sh
az vm run-command invoke -g rg-agrosense-prod -n vm-rrhh-web --command-id RunShellScript --scripts @setup-dns.sh --query "value[0].message" -o tsv
bash nsg-dns-rules.sh
bash vnet-dns.sh
bash create-cliente.sh
az vm run-command invoke -g rg-agrosense-prod -n vm-cliente-01 --command-id RunShellScript --scripts @cliente-dns.sh --query "value[0].message" -o tsv
az vm run-command invoke -g rg-agrosense-prod -n vm-cliente-01 --command-id RunShellScript --scripts @prueba-interna.sh --query "value[0].message" -o tsv
bash mover-cliente.sh snet-ti 10.0.0.68
bash mover-cliente.sh snet-visitas 10.0.0.36
```

## Archivos

- **Configuración de BIND9 (entregable):** `named.conf.options`, `named.conf.local`, `db.agrosense.local`, `db.10.0.0`.
- **Dentro de las VMs:**
  - `setup-dns.sh`: IP secundaria y BIND9 (generado a partir de los archivos de arriba).
  - `cliente-dns.sh`: dominio de búsqueda en cada cliente.
  - `prueba-interna.sh` y `prueba-visitas.sh`: pruebas para las capturas.
- **Azure CLI:** `add-ip-dns.sh`, `nsg-dns-rules.sh`, `vnet-dns.sh`, `create-cliente.sh`, `mover-cliente.sh`.
