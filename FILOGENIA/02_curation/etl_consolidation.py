from __future__ import annotations

# =============================================================================
# SCRIPT: Consolidación forense BOLD + NCBI (sin cruce de metadatos)
# =============================================================================
# Flujo: cargar CSVs → detectar clones NCBI via bold_id → purgar SOLO clones →
# concatenar (BOLD + NCBI purgado) → exportar CSV/FASTA finales (4 columnas).
# =============================================================================

import logging
import re
from pathlib import Path
from typing import Any, Optional

import pandas as pd
import tkinter as tk
from tkinter import filedialog, messagebox


# -----------------------------------------------------------------------------
# 1. LOGGING Y UTILIDADES
# -----------------------------------------------------------------------------

def _configure_logging() -> None:
    if logging.getLogger().handlers:
        return
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def _pick_two_csvs_gui(root: tk.Tk) -> Optional[tuple[str, str]]:
    paths = filedialog.askopenfilenames(
        title="Selecciona 2 CSVs: BOLD y NCBI",
        parent=root,
        filetypes=[("CSV", "*.csv"), ("All files", "*.*")],
    )
    if not paths:
        return None
    if len(paths) != 2:
        messagebox.showwarning(
            "Consolidación ETL",
            "Selecciona exactamente 2 archivos CSV: uno de BOLD y otro de NCBI.",
            parent=root,
        )
        return None
    return str(paths[0]), str(paths[1])


def _read_csv(path: str) -> pd.DataFrame:
    # Mantener literalidad: no inferimos tipos raros ni tocamos texto.
    df = pd.read_csv(path, dtype=str, keep_default_na=True, na_values=["", "NA", "NaN", "nan"])
    # Normalizar nombres de columna por si vienen con espacios.
    df.columns = [str(c).strip() for c in df.columns]
    return df


def _is_ncbi_df(df: pd.DataFrame) -> bool:
    return "bold_id" in df.columns


def _strip_bold_prefix(value: Any) -> Any:
    if pd.isna(value):
        return pd.NA
    s = str(value).strip()
    if not s:
        return pd.NA
    s = re.sub(r"^BOLD:\s*", "", s)
    s = s.split(".", 1)[0]
    s = s.strip()
    return s if s else pd.NA

def _underscore_spaces(value: Any) -> str:
    # Encabezados FASTA: evitar espacios (compatibilidad con herramientas).
    s = "Unknown" if pd.isna(value) else str(value).strip()
    return re.sub(r"\s+", "_", s) if s else "Unknown"


def export_fasta(df: pd.DataFrame, filepath: str) -> None:
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

    with open(filepath, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
        if lines:
            fh.write("\n")
    logging.info("FASTA consolidado guardado en: %s", filepath)


# -----------------------------------------------------------------------------
# 2. CONSOLIDACIÓN (LIMPIEZA ESTRICTA)
# -----------------------------------------------------------------------------

def consolidate_bold_ncbi(bold_df: pd.DataFrame, ncbi_df: pd.DataFrame) -> pd.DataFrame:
    # Preparar listas de IDs BOLD para matching exacto.
    bold_ids = (
        bold_df.get("processid", pd.Series([], dtype="object"))
        .astype("string")
        .str.strip()
        .dropna()
        .unique()
    )
    bold_id_set = set([str(x) for x in bold_ids if str(x).strip()])

    # Limpiar bold_id (quitar prefijo BOLD:) SOLO dentro del df de NCBI.
    ncbi = ncbi_df.copy()
    ncbi["bold_id"] = ncbi["bold_id"].map(_strip_bold_prefix)
    ncbi["bold_id"] = ncbi["bold_id"].astype("string").str.strip()

    # Clones confirmados: bold_id exacto que coincide con processid de BOLD.
    clone_mask = ncbi["bold_id"].isin(list(bold_id_set))
    clones = int(clone_mask.fillna(False).sum())
    logging.info("Clones confirmados en NCBI (a eliminar): %s", clones)

    # Purgar SOLO clones; el resto de NCBI se conserva intacto.
    ncbi_purged = ncbi.loc[~clone_mask].copy()

    # Concat visual: BOLD original + NCBI purgado (sin mezclar metadatos).
    combined = pd.concat([bold_df, ncbi_purged], ignore_index=True, sort=False)

    # Eliminar la columna temporal del resultado final.
    if "bold_id" in combined.columns:
        combined = combined.drop(columns=["bold_id"])

    # Asegurar exactamente 4 columnas (y en ese orden).
    out_cols = ["processid", "species_name", "country", "nucleotides"]
    combined = combined.reindex(columns=out_cols)

    # Limpieza visual final: Unknown para vacíos/NaN.
    for c in out_cols:
        combined[c] = combined[c].astype("string")
        combined[c] = combined[c].str.strip()
        combined[c] = combined[c].replace({"": pd.NA})
        combined[c] = combined[c].fillna("Unknown")

    return combined


def export_metadata_csv(df: pd.DataFrame, filepath: str) -> None:
    df.to_csv(
        filepath,
        index=False,
        columns=["processid", "species_name", "country", "nucleotides"],
        encoding="utf-8",
    )
    logging.info("CSV consolidado guardado en: %s", filepath)


# -----------------------------------------------------------------------------
# 3. EJECUCIÓN PRINCIPAL
# -----------------------------------------------------------------------------

def run_pipeline() -> int:
    _configure_logging()
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    root.update()

    try:
        picked = _pick_two_csvs_gui(root)
        if not picked:
            logging.info("Operación cancelada o selección inválida.")
            return 1

        p1, p2 = picked
        df1 = _read_csv(p1)
        df2 = _read_csv(p2)

        # Detectar cuál es NCBI por presencia de bold_id.
        if _is_ncbi_df(df1) and not _is_ncbi_df(df2):
            ncbi_df, bold_df = df1, df2
        elif _is_ncbi_df(df2) and not _is_ncbi_df(df1):
            ncbi_df, bold_df = df2, df1
        else:
            messagebox.showerror(
                "Consolidación ETL — Error",
                "No puedo distinguir BOLD vs NCBI.\n\n"
                "NCBI debe incluir la columna 'bold_id' y BOLD no.",
                parent=root,
            )
            return 1

        combined = consolidate_bold_ncbi(bold_df=bold_df, ncbi_df=ncbi_df)

        out_dir = Path(__file__).resolve().parent
        base = "public_references_clean_run1"
        csv_out = str(out_dir / f"{base}.csv")
        fasta_out = str(out_dir / f"{base}.fasta")

        export_metadata_csv(combined, csv_out)
        export_fasta(combined, fasta_out)

        messagebox.showinfo(
            "Consolidación ETL",
            f"Proceso finalizado.\n\nCSV:\n{csv_out}\n\nFASTA:\n{fasta_out}",
            parent=root,
        )
        return 0
    except Exception as exc:  # noqa: BLE001
        logging.exception("Error en consolidación: %s", exc)
        messagebox.showerror(
            "Consolidación ETL — Error",
            f"Ocurrió un error:\n{exc}",
            parent=root,
        )
        return 1
    finally:
        root.destroy()


if __name__ == "__main__":
    raise SystemExit(run_pipeline())

