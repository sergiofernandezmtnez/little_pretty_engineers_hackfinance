#!/usr/bin/env python3
"""Convierte datos/becas_y_ayudas.csv en el bloque de datos de sql/becas_ayudas.sql.

Uso (desde la raíz del repo):   python scripts/csv_a_sql.py
Solo usa la librería estándar de Python. Valida el CSV antes de escribir nada y, si hay un
error, dice la fila y el motivo. Acepta CSV guardado desde Excel (con o sin BOM, con , o ;).
"""
import csv
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
CSV = RAIZ / "datos" / "becas_y_ayudas.csv"
SQL = RAIZ / "sql" / "becas_ayudas.sql"
INICIO, FIN = "-- BEGIN DATOS", "-- END DATOS"

COLUMNAS = ["id", "titulo", "organismo", "categoria", "cuantia_maxima", "requisitos",
            "plazo", "estado", "ambito", "enlace_oficial"]
ESTADOS = {"Abierta", "Próximamente", "Permanente", "Cerrada"}
MAX = {"titulo": 200, "organismo": 200, "categoria": 80, "cuantia_maxima": 400,
       "requisitos": 1000, "plazo": 200, "ambito": 40, "enlace_oficial": 500}


def leer():
    texto = CSV.read_text(encoding="utf-8-sig")               # utf-8-sig quita el BOM de Excel
    cabecera = texto.splitlines()[0] if texto.strip() else ""
    # Excel en español guarda con ";" y el resto con ",": el separador se deduce de la cabecera
    sep = ";" if cabecera.count(";") > cabecera.count(",") else ","
    return list(csv.DictReader(texto.splitlines(), delimiter=sep))


def validar(filas):
    errores = []
    if not filas:
        errores.append("el CSV está vacío")
    cab = list(filas[0].keys()) if filas else []
    faltan = [c for c in COLUMNAS if c not in cab]
    if faltan:
        errores.append("faltan columnas: " + ", ".join(faltan) + f" (cabecera leída: {cab})")
        return errores
    vistos = set()
    for n, f in enumerate(filas, start=2):                    # la fila 1 es la cabecera
        pre = f"fila {n}:"
        if not re.fullmatch(r"\d+", (f["id"] or "").strip()):
            errores.append(f"{pre} id debe ser un número entero (es '{f['id']}')")
        elif f["id"].strip() in vistos:
            errores.append(f"{pre} id {f['id']} repetido")
        vistos.add((f["id"] or "").strip())
        for c in ("titulo", "organismo", "categoria", "estado", "ambito"):
            if not (f[c] or "").strip():
                errores.append(f"{pre} '{c}' está vacío")
        if (f["estado"] or "").strip() not in ESTADOS:
            errores.append(f"{pre} estado '{f['estado']}' no válido (usa: {', '.join(sorted(ESTADOS))})")
        for c, m in MAX.items():
            if len((f[c] or "").strip()) > m:
                errores.append(f"{pre} '{c}' supera {m} caracteres")
        enlace = (f["enlace_oficial"] or "").strip()
        if enlace and not re.fullmatch(r"https://\S+", enlace):
            errores.append(f"{pre} enlace_oficial debe empezar por https:// y no llevar espacios")
    return errores


def lit(valor):
    """Texto -> literal SQL (comillas simples duplicadas) o NULL si está vacío."""
    v = (valor or "").strip()
    return "null" if not v else "'" + v.replace("'", "''") + "'"


def bloque(filas):
    cols = ", ".join(COLUMNAS)
    lineas = []
    for f in filas:
        vals = [str(int(f["id"]))] + [lit(f[c]) for c in COLUMNAS[1:]]
        lineas.append("  (" + ", ".join(vals) + ")")
    ids = ", ".join(str(int(f["id"])) for f in filas)
    sets = ",\n  ".join(f"{c} = excluded.{c}" for c in COLUMNAS[1:])
    return (
        f"insert into public.becas_ayudas ({cols}) values\n" + ",\n".join(lineas) + "\n"
        f"on conflict (id) do update set\n  {sets},\n  actualizado = now();\n\n"
        f"-- El CSV manda: lo que ya no esté en el CSV se borra de la tabla\n"
        f"delete from public.becas_ayudas where id not in ({ids});\n"
    )


def main():
    if not CSV.exists():
        sys.exit(f"No encuentro {CSV}")
    filas = leer()
    errores = validar(filas)
    if errores:
        print("El CSV tiene errores, no se ha cambiado nada:")
        for e in errores:
            print("  -", e)
        sys.exit(1)
    sql = SQL.read_text(encoding="utf-8")
    if INICIO not in sql or FIN not in sql:
        sys.exit(f"Faltan las marcas '{INICIO}' / '{FIN}' en {SQL}")
    cabeza, resto = sql.split(INICIO, 1)
    _, cola = resto.split(FIN, 1)
    nuevo = (cabeza + INICIO + " (generado por scripts/csv_a_sql.py: no lo edites a mano)\n"
             + bloque(filas) + FIN + cola)
    SQL.write_text(nuevo, encoding="utf-8")
    print(f"OK: {len(filas)} ayudas volcadas en {SQL.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
