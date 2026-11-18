#!/usr/bin/env python3
"""Genera el informe en Word (y una copia en PDF) a partir de informe-fase2.md.

Reemplaza cada marcador <<ARCHIVO:ruta>> por el contenido real del archivo del repositorio, así el
Anexo A siempre coincide con lo que está en fase2/. Requiere pandoc; el PDF usa LibreOffice (soffice).
Uso: python3 informe/construir.py
"""
import re
import shutil
import subprocess
from pathlib import Path

INF = Path(__file__).resolve().parent
RAIZ = INF.parent
FUENTE = INF / "informe-fase2.md"
INTERMEDIO = INF / ".informe-construido.md"
DOCX = INF / "Informe_Fase2_AgroSenseGT.docx"


def incluir(m):
    ruta = RAIZ / m.group(1)
    texto = ruta.read_text(encoding="utf-8").rstrip("\n")
    return f"Archivo `{m.group(1)}`:\n\n```\n{texto}\n```"


md = re.sub(r"<<ARCHIVO:([^>]+)>>", incluir, FUENTE.read_text(encoding="utf-8"))
INTERMEDIO.write_text(md, encoding="utf-8")
subprocess.run(["pandoc", str(INTERMEDIO), "-o", str(DOCX), "--reference-doc", str(INF / "plantilla" / "referencia.docx"),
                "--resource-path", str(INF), "--syntax-highlighting=none"], check=True)
INTERMEDIO.unlink()

# El texto dentro de las tablas usa el estilo TablaTexto (10 pt); las listas siguen con Compact (12 pt).
import zipfile
tmp = DOCX.with_suffix(".tmp")
with zipfile.ZipFile(DOCX) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        data = zin.read(item.filename)
        if item.filename == "word/document.xml":
            xml = data.decode("utf-8")
            xml = re.sub(r"<w:tbl>.*?</w:tbl>", lambda t: t.group(0).replace('w:val="Compact"', 'w:val="TablaTexto"'),
                         xml, flags=re.S)
            data = xml.encode("utf-8")
        zout.writestr(item, data)
tmp.replace(DOCX)
print("Word:", DOCX)

soffice = shutil.which("soffice")
if soffice:
    subprocess.run([soffice, "--headless", "--convert-to", "pdf", "--outdir", str(INF), str(DOCX)],
                   check=True, capture_output=True)
    print("PDF: ", DOCX.with_suffix(".pdf"))
