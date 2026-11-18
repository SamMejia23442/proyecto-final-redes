# Fase 2 — Servicios, seguridad y publicación (AgroSense GT)

Todo está desplegado en `rg-agrosense-prod` (Azure for Students, Brazil South) y se probó por última vez el 17/11/2026. El informe final está en [`informe/Informe_Fase2_AgroSenseGT.docx`](../informe/Informe_Fase2_AgroSenseGT.docx), con una copia en PDF.

| Pieza | Carpeta | Qué hay |
|---|---|---|
| DNS interno (BIND9) | [`dns/`](dns/) | Zonas `agrosense.local` e inversa, ACL, IP de servicio 10.0.0.105, DNS de la VNet. Ver su [README](dns/README.md) |
| Intranet RRHH | [`intranet/`](intranet/) | nginx en `vm-rrhh-web` (10.0.0.106), sin IP pública, `rrhh.agrosense.local` |
| DMZ y web pública | [`dmz/`](dmz/) | `vm-dmz-web` (10.0.0.116, IP pública 191.232.198.113), HTTPS con Let's Encrypt y redirección 301. `ventas-https.conf` es la versión desplegada |
| Firewall / ACL | [`firewall/nsg-reglas.sh`](firewall/nsg-reglas.sh) | Las reglas de los 5 NSG en un solo script. Se puede volver a ejecutar sin efectos secundarios |
| Hardening | [`hardening/`](hardening/) | `hardening.sh` (ufw por rol, SSH y servicios) y `hardening-extra.sh` (sysctl, servicios de la imagen de Azure y cabeceras HTTP) |
| Pruebas | [`pruebas/`](pruebas/) | Matriz de bloqueos desde la VM cliente y pruebas desde los servidores |
| Evidencias | [`evidencias/`](evidencias/) y [`dns/evidencias/`](dns/evidencias/) | Salidas de las pruebas, de IP flow verify, de las reglas NSG y del hardening |
| Diagrama | [`diagrama/`](diagrama/) | Diagrama de red de la Fase 2 (SVG y PNG) |

## Cómo se cumple cada requisito

| Requisito | Cómo |
|---|---|
| DNS interno | BIND9 en 10.0.0.105, que es el DNS de la VNet |
| Intranet solo interna y con nombre | `rrhh.agrosense.local` → 10.0.0.106, sin IP pública |
| Visitas: Internet sí, red interna no | `nsg-visitas`: `Deny-Internal-VNet` y solo 80/443 hacia Internet |
| TI llega a todas las subredes; nadie llega a TI | `nsg-ti`: `Deny-Inbound-VNet`, además de `Allow-SSH/ICMP-From-TI` en el Data Center y la DMZ |
| Intranet desde todas las subredes excepto Visitas, no desde Internet | `nsg-datacenter`: `Allow-Intranet-Web` (Ventas, TI y Data Center) y `Deny-VNet-Inbound` |
| Hardening en todas las instancias | ufw con "denegar todo lo entrante" por rol, SSH solo con llave, servicios innecesarios eliminados y sysctl |
| DMZ con web pública y dominio | `snet-dmz` y `agrosense-ventas-gt.brazilsouth.cloudapp.azure.com` |
| Punto extra: TLS y redirección | Let's Encrypt, 301 de HTTP a HTTPS y HSTS |

## Volver a generar el informe

```bash
python3 informe/generar-figuras.py   # figuras a partir de las evidencias
python3 informe/construir.py         # Word + PDF (requiere pandoc y LibreOffice)
```
