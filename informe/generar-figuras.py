#!/usr/bin/env python3
"""Convierte las salidas guardadas en fase2/evidencias/ en figuras PNG con aspecto de terminal.

El texto de cada figura es exactamente el del archivo de evidencia (salida real de Azure CLI /
run-command del 17/11/2026); solo se le da formato. Uso: python3 informe/generar-figuras.py
"""
import re
import textwrap
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parent.parent
EV = RAIZ / "fase2" / "evidencias"
DNS = RAIZ / "fase2" / "dns" / "evidencias"
SALIDA = RAIZ / "informe" / "img"

FIGURAS = [
    ("t-subredes-nsg.png", [EV / "subredes-nsg.txt"]),
    ("t-reglas-nsg.png", [EV / "reglas-nsg.txt"]),
    ("t-dns-ventas.png", [DNS / "dns-desde-ventas.txt"]),
    ("t-dns-ti.png", [DNS / "dns-desde-ti.txt"]),
    ("t-dns-visitas.png", [DNS / "dns-desde-visitas.txt"]),
    ("t-matriz-ventas.png", [EV / "matriz-desde-ventas.txt"]),
    ("t-matriz-ti.png", [EV / "matriz-desde-ti.txt"]),
    ("t-matriz-visitas.png", [EV / "matriz-desde-visitas.txt"]),
    ("t-servidores.png", [EV / "desde-datacenter-hacia-ventas.txt", EV / "desde-datacenter-hacia-ti.txt",
                          EV / "desde-dmz-hacia-ti.txt"]),
    ("t-ipflow-servidores.png", [EV / "ipflow-servidores.txt"]),
    ("t-ipflow-ti-visitas.png", [EV / "ipflow-hacia-ti.txt", EV / "ipflow-desde-visitas.txt"]),
    ("t-internet.png", [EV / "desde-internet.txt"]),
    ("t-hardening-rrhh.png", [EV / "hardening-vm-rrhh-web.txt"]),
    ("t-hardening-dmz.png", [EV / "hardening-vm-dmz-web.txt"]),
]

COLS = 112
FS = 26          # tamaño de letra (px); la imagen se reduce al insertarla en Word
LH = 34          # alto de línea
PAD = 34
BG, FG, CMD, PROMPT = "#0c0c0c", "#d4d4d4", "#f2f2f2", "#16c60c"
VERDE, ROJO, AMARILLO, CIAN = "#16c60c", "#e74856", "#f9f1a5", "#61d6d6"

fuente = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", FS, index=0)
negrita = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", FS, index=1)
ANCHO_CHAR = fuente.getlength("M")

RESALTAR = [
    (re.compile(r"PERMITIDO|\bAllow\b|HTTP/1\.1 (200|301)[^\n]*"), VERDE),
    (re.compile(r"BLOQUEADO|\bDeny\b|Transfer failed\.|NXDOMAIN|timed out|no servers could be reached"), ROJO),
]


def partir(linea):
    """Devuelve las líneas visuales (los comandos largos se parten con '\\' como en una terminal)."""
    if len(linea) <= COLS:
        return [linea]
    if linea.startswith("$ "):
        partes = textwrap.wrap(linea, COLS - 2, break_long_words=True, break_on_hyphens=False, subsequent_indent="    ")
        return [p + " \\" for p in partes[:-1]] + [partes[-1]]
    return textwrap.wrap(linea, COLS, subsequent_indent="  ", break_on_hyphens=False) or [linea]


def segmentos(linea, es_comando):
    if es_comando:
        return [("$ ", PROMPT, True), (linea[2:], CMD, False)] if linea.startswith("$ ") else [(linea, CMD, False)]
    if linea.startswith("== "):
        return [(linea, AMARILLO, True)]
    if linea.startswith("## ") or linea.startswith("--- "):
        return [(linea, CIAN, True)]
    marcas = []
    for patron, color in RESALTAR:
        for m in patron.finditer(linea):
            marcas.append((m.start(), m.end(), color))
    marcas.sort()
    salida, pos = [], 0
    for ini, fin, color in marcas:
        if ini < pos:
            continue
        if ini > pos:
            salida.append((linea[pos:ini], FG, False))
        salida.append((linea[ini:fin], color, True))
        pos = fin
    if pos < len(linea):
        salida.append((linea[pos:], FG, False))
    return salida or [("", FG, False)]


def render(nombre, archivos):
    visuales = []  # (texto, es_comando)
    for i, archivo in enumerate(archivos):
        if i:
            visuales.append(("", False))
        for linea in archivo.read_text(encoding="utf-8").rstrip("\n").split("\n"):
            linea = linea.replace("\t", "    ")
            es_cmd = linea.startswith("$ ")
            for j, v in enumerate(partir(linea)):
                visuales.append((v, es_cmd))
    ancho = int(PAD * 2 + ANCHO_CHAR * min(COLS, max(len(t) for t, _ in visuales)))
    alto = PAD * 2 + LH * len(visuales)
    img = Image.new("RGB", (ancho, alto), BG)
    d = ImageDraw.Draw(img)
    y = PAD
    for texto, es_cmd in visuales:
        x = PAD
        for trozo, color, bold in segmentos(texto, es_cmd):
            d.text((x, y), trozo, font=negrita if bold else fuente, fill=color)
            x += ANCHO_CHAR * len(trozo)
        y += LH
    img.save(SALIDA / nombre, optimize=True)
    return img.size


if __name__ == "__main__":
    SALIDA.mkdir(parents=True, exist_ok=True)
    for nombre, archivos in FIGURAS:
        print(nombre, render(nombre, archivos))
