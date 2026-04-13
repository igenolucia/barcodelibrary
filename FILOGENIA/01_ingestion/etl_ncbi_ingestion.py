# =============================================================================
# SCRIPT: Ingesta de datos filogenéticos desde NCBI (GenBank)
# =============================================================================
# Flujo: Conexión a Entrez, descarga masiva en XML completo (gb), extracción de
# secuencias limpias de gaps (-) y metadatos taxonómicos y geográficos.
# Genera archivos gemelos estandarizados.
# =============================================================================

from __future__ import annotations

import logging
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Final, Optional

import pandas as pd
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog

from Bio import Entrez

# -----------------------------------------------------------------------------
# 1. IMPORTACIÓN DE PAQUETES Y CONSTANTES
# -----------------------------------------------------------------------------
# NCBI (Entrez) exige el email para identificar peticiones y reducir el riesgo de
# bloqueos (baneos de IP) durante descargas masivas.

BATCH_SIZE: Final[int] = 100
NCBI_THROTTLE_SEC: Final[float] = 0.3


def _configure_logging() -> None:
    # Logging estructurado para trazabilidad (en lugar de print()).
    if logging.getLogger().handlers:
        return
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def _sanitize_filename_token(name: str) -> str:
    # Sanea caracteres no válidos en nombres de archivo (Windows).
    cleaned = re.sub(r'[<>:"/\\|?*]', "_", name.strip())
    cleaned = re.sub(r"\s+", "_", cleaned)
    return cleaned or "NCBI_export"


def _underscore_spaces(value: Any) -> str:
    # Encabezados FASTA: evitar espacios (compatibilidad con herramientas).
    s = "Unknown" if pd.isna(value) else str(value).strip()
    return re.sub(r"\s+", "_", s) if s else "Unknown"

# -----------------------------------------------------------------------------
# 2. FUNCIONES AUXILIARES Y VERSIONADO (PREVENCIÓN DE SOBREESCRITURA)
# -----------------------------------------------------------------------------

def get_unique_filepath(base_dir: Path, base_name: str, ext: str) -> Path:
    # Fecha + _runN: evita sobreescritura y mantiene ejecuciones inmutables.
    date_tag = datetime.now().strftime("%Y%m%d")
    base = f"{base_name}_NCBI_{date_tag}"

    candidate = base_dir / f"{base}{ext}"
    if not candidate.exists():
        return candidate

    run = 1
    while True:
        candidate = base_dir / f"{base}_run{run}{ext}"
        if not candidate.exists():
            return candidate
        run += 1


def _get_unique_twin_filepaths(base_dir: Path, base_name: str) -> tuple[Path, Path]:
    # CSV y FASTA deben compartir el mismo _runN (archivos gemelos).
    csv_path = get_unique_filepath(base_dir, base_name, ".csv")
    fasta_path = csv_path.with_suffix(".fasta")

    if not fasta_path.exists():
        return csv_path, fasta_path

    stem = csv_path.stem
    m = re.search(r"_run(\d+)$", stem)
    next_run = int(m.group(1)) + 1 if m else 1

    date_tag = datetime.now().strftime("%Y%m%d")
    base = f"{base_name}_NCBI_{date_tag}"
    while True:
        csv_candidate = base_dir / f"{base}_run{next_run}.csv"
        fasta_candidate = base_dir / f"{base}_run{next_run}.fasta"
        if not csv_candidate.exists() and not fasta_candidate.exists():
            return csv_candidate, fasta_candidate
        next_run += 1


def ask_taxon_gui(root: tk.Tk) -> Optional[str]:
    """Solicita al usuario el nombre del taxón mediante un diálogo modal."""
    taxon = simpledialog.askstring(
        title="NCBI ETL — Taxón",
        prompt="Escribe el nombre del taxón a buscar (ej. Pulchellodromus):",
        parent=root,
    )
    if taxon is None:
        return None
    taxon = taxon.strip()
    return taxon if taxon else None


def ask_output_directory_gui(root: tk.Tk) -> Optional[str]:
    """Abre un selector de carpeta para el directorio de salida."""
    path = filedialog.askdirectory(
        title="Selecciona el directorio de destino para CSV y FASTA",
        parent=root,
    )
    return path if path else None


def ask_entrez_email_gui(root: tk.Tk) -> Optional[str]:
    # NCBI Entrez exige/recomienda un email para identificar peticiones y evitar bloqueos por IP.
    email = simpledialog.askstring(
        title="NCBI ETL — Entrez.email",
        prompt="Introduce tu email para NCBI Entrez (recomendado). Deja vacío para usar placeholder:",
        parent=root,
    )
    if email is None:
        return None
    email = email.strip()
    return email if email else None


# -----------------------------------------------------------------------------
# 3. CONEXIÓN A LA API DE NCBI (ENTREZ)
# -----------------------------------------------------------------------------
# Descarga en bloques (batch) y uso de retmode=xml y rettype=gb para forzar la inclusión
# de datos geográficos que el formato fasta omite.


def _ncbi_esearch_ids(taxon: str) -> list[str]:
    # Paso 1 (esearch): devolver IDs (UIDs) para usarlos luego en efetch.
    term = f"{taxon}[Organism]"
    logging.info("NCBI esearch: %r", term)

    # Retmax=0 para obtener el total y paginar.
    handle = Entrez.esearch(db="nucleotide", term=term, retmax=0)
    result0 = Entrez.read(handle)
    handle.close()

    count = int(result0.get("Count", "0"))
    if count <= 0:
        return []

    ids: list[str] = []
    retstart = 0
    page_size = min(BATCH_SIZE * 10, 1000)

    while retstart < count:
        handle = Entrez.esearch(
            db="nucleotide",
            term=term,
            retstart=retstart,
            retmax=min(page_size, count - retstart),
        )
        res = Entrez.read(handle)
        handle.close()

        batch_ids = res.get("IdList", [])
        if batch_ids:
            ids.extend([str(x) for x in batch_ids])

        # Entrez devuelve RetMax como string a veces.
        retstart += int(res.get("RetMax", len(batch_ids)))
        time.sleep(NCBI_THROTTLE_SEC)

    logging.info("NCBI esearch: %s IDs recuperados.", len(ids))
    return ids


def fetch_ncbi_xml(taxon: str, email: str) -> list[dict[str, Any]]:
    # Paso 2 (efetch): XML GenBank completo. FASTA es estandarizado por la API, pero puede omitir geografía/features.
    Entrez.email = email

    ids = _ncbi_esearch_ids(taxon)
    if not ids:
        return []

    all_records: list[dict[str, Any]] = []
    for start in range(0, len(ids), BATCH_SIZE):
        batch = ids[start : start + BATCH_SIZE]
        logging.info(
            "NCBI efetch: batch %s-%s/%s",
            start + 1,
            start + len(batch),
            len(ids),
        )
        handle = Entrez.efetch(
            db="nucleotide",
            id=",".join(batch),
            rettype="gb",
            retmode="xml",
        )
        parsed = Entrez.read(handle)
        handle.close()

        if isinstance(parsed, list):
            for item in parsed:
                if isinstance(item, dict):
                    all_records.append(item)

        time.sleep(NCBI_THROTTLE_SEC)

    logging.info("NCBI efetch: %s registros descargados.", len(all_records))
    return all_records

# -----------------------------------------------------------------------------
# 4. CURACIÓN, EXTRACCIÓN DE METADATOS Y LIMPIEZA
# -----------------------------------------------------------------------------
# GenBank no estandariza la localización. Actuamos como red de arrastre priorizandose hace una búsqueda en conceptos como
# geo_loc_name, country, isolation_source o locality. Además, eliminamos los gaps
# '-' para entregar la secuencia cruda.

def curate_ncbi_dataframe(records: list[dict[str, Any]]) -> pd.DataFrame:
    rows_out: list[dict[str, Any]] = []
    for rec in records:
        pid = str(rec.get("GBSeq_accession-version", "Unknown")).strip()
        sp = str(rec.get("GBSeq_organism", "Unknown")).strip()
        seq = str(rec.get("GBSeq_sequence", "")).replace("-", "").upper().strip()

        if not seq or seq.lower() == "nan":
            continue

        # Extraer ID original de BOLD si existe como cruce en db_xref.
        bold_id: Any = pd.NA
        for feat in rec.get("GBSeq_feature-table", []):
            for qual in feat.get("GBFeature_quals", []):
                if qual.get("GBQualifier_name") != "db_xref":
                    continue
                val = str(qual.get("GBQualifier_value", "")).strip()
                if val.startswith("BOLD:"):
                    bold_id = val
                    break
            if bold_id is not pd.NA:
                break

        # Búsqueda de datos geográficos: el estándar moderno es geo_loc_name, pero también aparecen
        # country / isolation_source / locality. Concatenamos con comas; nunca usar '|' porque
        # '|' es el delimitador del encabezado FASTA y rompería la lectura en Geneious.
        country = "Unknown"
        for feat in rec.get("GBSeq_feature-table", []):
            if feat.get("GBFeature_key") == "source":
                geo_data = []
                for qual in feat.get("GBFeature_quals", []):
                    q_name = qual.get("GBQualifier_name", "")
                    # Añadimos geo_loc_name, que es el estándar moderno de GenBank
                    if q_name in ["geo_loc_name", "country", "isolation_source", "locality"]:
                        val = str(qual.get("GBQualifier_value", "")).strip()
                        if val:
                            geo_data.append(val)
                
                if geo_data:
                    # Unimos con coma y espacio.
                    country = ", ".join(geo_data)
                break

        rows_out.append(
            {
                "processid": pid,
                "species_name": sp,
                "country": country,
                "nucleotides": seq,
                "bold_id": bold_id,
            }
        )
    return pd.DataFrame(rows_out)


def export_metadata_csv(df: pd.DataFrame, output_path: str) -> None:
    # CSV “forense”: tabla de metadatos + secuencia por registro.
    df.to_csv(
        output_path,
        index=False,
        columns=["processid", "species_name", "country", "nucleotides", "bold_id"],
        encoding="utf-8",
    )
    logging.info("Metadatos guardados en: %s", output_path)

# -----------------------------------------------------------------------------
# 5. EXPORTACIÓN A FASTA/CSV Y EJECUCIÓN PRINCIPAL
# -----------------------------------------------------------------------------

def export_fasta(df: pd.DataFrame, output_path: str) -> None:
    # FASTA “operativo”: encabezado estandarizado -> >processid|species_name|country
    lines: list[str] = []
    for _, row in df.iterrows():
        pid = "Unknown" if pd.isna(row["processid"]) else str(row["processid"]).strip()
        if not pid or pid.lower() == "nan":
            pid = "Unknown"
        sp = _underscore_spaces(row["species_name"])
        ct = _underscore_spaces(row["country"])

        header = f">{pid}|{sp}|{ct}"
        seq = str(row["nucleotides"]).strip()

        lines.append(header)
        lines.append(seq)

    with open(output_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
        if lines:
            fh.write("\n")
    logging.info("Secuencias FASTA guardadas en: %s", output_path)


def run_pipeline() -> int:
    # Ejecución principal: GUI → Entrez → curación → outputs gemelos versionados.
    _configure_logging()
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    root.update()

    try:
        taxon = ask_taxon_gui(root)
        if not taxon:
            logging.info("Operación cancelada o taxón vacío.")
            return 1

        out_dir = ask_output_directory_gui(root)
        if not out_dir:
            logging.info("Operación cancelada: no se seleccionó directorio.")
            return 1

        email = ask_entrez_email_gui(root)
        if not email:
            email = "your.email@example.com"
            logging.warning("Entrez.email no proporcionado; usando placeholder: %s", email)

        base = _sanitize_filename_token(taxon)
        out_path = Path(out_dir)
        csv_path_p, fasta_path_p = _get_unique_twin_filepaths(out_path, base)
        csv_path = str(csv_path_p)
        fasta_path = str(fasta_path_p)

        logging.info("Iniciando descarga desde NCBI...")
        raw_records = fetch_ncbi_xml(taxon, email)
        curated = curate_ncbi_dataframe(raw_records)

        if curated.empty:
            messagebox.showwarning(
                "NCBI ETL",
                "No hay secuencias con datos genéticos para este taxón o el conjunto descargado está vacío.",
                parent=root,
            )
            logging.warning("No se generaron archivos: dataset vacío tras el filtrado.")
            return 1

        export_metadata_csv(curated, csv_path)
        export_fasta(curated, fasta_path)

        logging.info("Archivos guardados en: %s", out_dir)
        messagebox.showinfo(
            "NCBI ETL",
            f"Proceso finalizado.\n\nCSV:\n{csv_path}\n\nFASTA:\n{fasta_path}",
            parent=root,
        )
        return 0
    except Exception as exc:  # noqa: BLE001
        logging.exception("Error en el pipeline ETL: %s", exc)
        messagebox.showerror(
            "NCBI ETL — Error",
            f"Ocurrió un error:\n{exc}",
            parent=root,
        )
        return 1
    finally:
        root.destroy()


if __name__ == "__main__":
    raise SystemExit(run_pipeline())
