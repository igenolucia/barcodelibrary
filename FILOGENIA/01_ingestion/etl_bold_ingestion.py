"""
ETL para descargar secuencias y metadatos desde el BOLD Data Portal (API JSON/BCDM).

Dependencias: ``requests``, ``pandas`` (``pip install requests pandas``).
"""

from __future__ import annotations

import json
import logging
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Final, Iterator, Mapping, Optional
from urllib.parse import quote, urljoin

import pandas as pd
import requests
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog

# --- Constantes ---------------------------------------------------------------------------

PORTAL_BASE: Final[str] = "https://portal.boldsystems.org/api/"
URL_PREPROCESSOR: Final[str] = urljoin(PORTAL_BASE, "query/preprocessor")
URL_QUERY: Final[str] = urljoin(PORTAL_BASE, "query")

DEFAULT_TIMEOUT: Final[tuple[float, float]] = (30.0, 300.0)
MAX_RETRIES: Final[int] = 4
RETRY_BACKOFF_SEC: Final[float] = 2.0

HTTP_HEADERS: Final[dict[str, str]] = {
    "User-Agent": "barcodelibray-etl/1.0 (+https://github.com; research TFM)",
    "Accept": "application/json, text/plain, */*",
}

# Campos BCDM y alias habituales tras json_normalize
_ID_KEYS: Final[tuple[str, ...]] = ("processid", "sampleid", "record_id", "process_id")
_SPECIES_KEYS: Final[tuple[str, ...]] = (
    "species",
    "species_name",
    "scientific_name",
    "identification",
)
_GEO_KEYS: Final[tuple[str, ...]] = (
    "country/ocean",
    "country_ocean",
    "country",
    "ocean",
)
_SEQ_KEYS: Final[tuple[str, ...]] = (
    "nucleotides",
    "nuc",
    "sequence",
    "nucleotide",
    "barcode",
)


def _configure_logging() -> None:
    """Configura el registro de eventos en consola con formato uniforme."""
    if logging.getLogger().handlers:
        return
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def _sanitize_filename_token(name: str) -> str:
    """Convierte una cadena en un fragmento seguro para nombres de archivo en Windows."""
    cleaned = re.sub(r'[<>:"/\\|?*]', "_", name.strip())
    cleaned = re.sub(r"\s+", "_", cleaned)
    return cleaned or "BOLD_export"


def _underscore_spaces(value: Any) -> str:
    """Reemplaza espacios por guiones bajos para encabezados FASTA (especie/país)."""
    s = "Unknown" if pd.isna(value) else str(value).strip()
    return re.sub(r"\s+", "_", s) if s else "Unknown"


def get_unique_filepath(base_dir: Path, base_name: str, ext: str) -> Path:
    """Devuelve una ruta única con fecha y sufijo de ejecución para evitar sobreescritura.

    La ruta se construye como:
        ``{base_name}_BOLD_{YYYYMMDD}{ext}`` o ``{base_name}_BOLD_{YYYYMMDD}_runN{ext}``

    Args:
        base_dir: Directorio destino.
        base_name: Nombre base (normalmente el taxón saneado).
        ext: Extensión incluyendo el punto (por ejemplo ``.csv`` o ``.fasta``).

    Returns:
        Ruta que no existe todavía en disco.
    """
    date_tag = datetime.now().strftime("%Y%m%d")
    base = f"{base_name}_BOLD_{date_tag}"

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
    """Obtiene rutas únicas para CSV y FASTA compartiendo el mismo sufijo run."""
    csv_path = get_unique_filepath(base_dir, base_name, ".csv")
    fasta_path = csv_path.with_suffix(".fasta")

    # Si el FASTA ya existe para ese mismo run, avanzar al siguiente run para ambos.
    if not fasta_path.exists():
        return csv_path, fasta_path

    stem = csv_path.stem
    m = re.search(r"_run(\d+)$", stem)
    next_run = int(m.group(1)) + 1 if m else 1

    date_tag = datetime.now().strftime("%Y%m%d")
    base = f"{base_name}_BOLD_{date_tag}"
    while True:
        csv_candidate = base_dir / f"{base}_run{next_run}.csv"
        fasta_candidate = base_dir / f"{base}_run{next_run}.fasta"
        if not csv_candidate.exists() and not fasta_candidate.exists():
            return csv_candidate, fasta_candidate
        next_run += 1


def ask_taxon_gui(root: tk.Tk) -> Optional[str]:
    """Solicita al usuario el nombre del taxón mediante un diálogo modal."""
    taxon = simpledialog.askstring(
        title="BOLD ETL — Taxón",
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


def _http_log_snippet(response: requests.Response, max_len: int = 300) -> str:
    """Primeros caracteres del cuerpo de respuesta para auditoría (una línea)."""
    text = response.text or ""
    return text[:max_len].replace("\n", "\\n")


def portal_get(
    url: str,
    *,
    session: requests.Session,
    params: Optional[Mapping[str, Any]] = None,
    step_name: str = "GET",
) -> requests.Response:
    """GET con reintentos ante timeout y errores 500 del portal.

    Args:
        url: URL completa.
        session: Sesión ``requests``.
        params: Parámetros de consulta.
        step_name: Etiqueta para logs.

    Returns:
        Objeto ``Response`` con código 2xx.

    Raises:
        requests.HTTPError: Tras agotar reintentos o ante 4xx no recuperables.
        requests.RequestException: Errores de red tras agotar reintentos.
    """
    last_error: Optional[BaseException] = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            logging.info("%s — intento HTTP %s/%s → %s", step_name, attempt, MAX_RETRIES, url)
            resp = session.get(
                url,
                params=params,
                timeout=DEFAULT_TIMEOUT,
                headers=HTTP_HEADERS,
            )
            code = resp.status_code

            if code == 404:
                logging.error(
                    "%s — HTTP 404. Cuerpo (recorte): %s",
                    step_name,
                    _http_log_snippet(resp),
                )
                resp.raise_for_status()

            if code == 500:
                logging.error(
                    "%s — HTTP 500 (intento %s/%s). Recorte: %s",
                    step_name,
                    attempt,
                    MAX_RETRIES,
                    _http_log_snippet(resp),
                )
                if attempt < MAX_RETRIES:
                    time.sleep(RETRY_BACKOFF_SEC * attempt)
                    continue
                resp.raise_for_status()

            if code >= 400:
                logging.error(
                    "%s — HTTP %s. Recorte: %s",
                    step_name,
                    code,
                    _http_log_snippet(resp),
                )
                resp.raise_for_status()

            return resp

        except requests.Timeout as exc:
            last_error = exc
            logging.warning(
                "%s — Timeout (intento %s/%s): %s",
                step_name,
                attempt,
                MAX_RETRIES,
                exc,
            )
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_BACKOFF_SEC * attempt)
        except requests.HTTPError:
            raise
        except requests.RequestException as exc:
            last_error = exc
            logging.exception("%s — Error de red: %s", step_name, exc)
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_BACKOFF_SEC * attempt)
            else:
                raise

    if last_error:
        raise last_error
    raise RuntimeError(f"{step_name}: sin respuesta tras reintentos.")


def _extract_query_id(obj: Any) -> Optional[str]:
    """Busca un identificador de consulta en la respuesta JSON del paso 2."""
    if obj is None:
        return None
    if isinstance(obj, str) and obj.strip():
        return obj.strip()
    if isinstance(obj, dict):
        for key in (
            "query_id",
            "queryId",
            "id",
            "token",
            "query_token",
            "document_id",
        ):
            val = obj.get(key)
            if val is not None and str(val).strip():
                return str(val).strip()
        for val in obj.values():
            found = _extract_query_id(val)
            if found:
                return found
    if isinstance(obj, list):
        for item in obj:
            found = _extract_query_id(item)
            if found:
                return found
    return None


def _validated_query_from_preprocessor(data1: Any) -> str:
    """Construye el parámetro ``query`` del paso 2 a partir del JSON del preprocesador.

    BOLD devuelve términos validados en ``successful_terms``; cada elemento incluye
    ``matched`` (p. ej. ``tax:genus:Pulchellodromus``). El endpoint ``/api/query``
    espera esos términos unidos por punto y coma, no JSON serializado.

    Args:
        data1: Objeto JSON del GET ``/api/query/preprocessor``.

    Returns:
        Cadena con uno o más términos ``matched`` separados por ``;``.

    Raises:
        ValueError: Si no hay términos validados utilizables.
    """
    if not isinstance(data1, dict):
        raise ValueError(
            "El preprocesador de BOLD no validó el taxón. Verifica que esté bien escrito."
        )
    raw_terms = data1.get("successful_terms")
    if not isinstance(raw_terms, list) or not raw_terms:
        raise ValueError(
            "El preprocesador de BOLD no validó el taxón. Verifica que esté bien escrito."
        )
    matched_parts: list[str] = []
    for entry in raw_terms:
        if not isinstance(entry, dict):
            continue
        m = entry.get("matched")
        if isinstance(m, str) and m.strip():
            matched_parts.append(m.strip())
    if not matched_parts:
        raise ValueError(
            "El preprocesador de BOLD no validó el taxón. Verifica que esté bien escrito."
        )
    return ";".join(matched_parts)


def _iter_json_lists(obj: Any) -> Iterator[list[Any]]:
    """Localiza listas candidatas (registros) en estructuras JSON anidadas."""
    if isinstance(obj, list):
        yield obj
        for item in obj:
            yield from _iter_json_lists(item)
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from _iter_json_lists(v)


def _pick_record_list(payload: Any) -> list[dict[str, Any]]:
    """Elige la lista de dicts más prometedora como filas BCDM."""
    if isinstance(payload, list) and payload and isinstance(payload[0], dict):
        return [x for x in payload if isinstance(x, dict)]

    best: list[dict[str, Any]] = []
    for lst in _iter_json_lists(payload):
        dict_rows = [x for x in lst if isinstance(x, dict)]
        if len(dict_rows) > len(best):
            best = dict_rows
    return best


def _norm_col_key(name: str) -> str:
    """Normaliza nombre de columna para emparejar alias BCDM (p. ej. country/ocean)."""
    return re.sub(r"[/\s]+", "_", str(name).strip().lower())


def _bcdm_json_to_dataframe(payload: Any) -> pd.DataFrame:
    """Convierte el JSON BCDM descargado en un DataFrame tabular."""
    if payload is None or (isinstance(payload, dict) and not payload):
        logging.warning("JSON vacío o nulo tras la descarga.")
        return pd.DataFrame()

    if isinstance(payload, dict) and "error" in payload:
        logging.error("El JSON incluye clave 'error': %s", payload.get("error"))

    records = _pick_record_list(payload)
    if not records:
        logging.warning(
            "No se encontró una lista de registros reconocible; se intenta json_normalize "
            "sobre la raíz."
        )
        try:
            return pd.json_normalize(payload, sep=".")
        except Exception as exc:  # noqa: BLE001
            logging.error("json_normalize falló: %s", exc)
            return pd.DataFrame()

    norm_rows: list[dict[str, Any]] = []
    for rec in records:
        try:
            flat = pd.json_normalize(rec, sep=".").to_dict(orient="records")[0]
        except Exception:  # noqa: BLE001
            flat = dict(rec)
        norm_rows.append(flat)

    df = pd.DataFrame(norm_rows)
    if df.empty:
        return df

    # Unificar posibles columnas anidadas típicas (secuencia en subobjetos)
    lower_cols = {str(c).lower(): c for c in df.columns}
    for lc, canonical in (
        ("nuc", "nuc"),
        ("nucleotides", "nucleotides"),
        ("sequence", "sequence"),
    ):
        if lc in lower_cols and canonical not in df.columns:
            df[canonical] = df[lower_cols[lc]]

    return df


def _first_matching_column(df: pd.DataFrame, candidates: tuple[str, ...]) -> Optional[str]:
    """Devuelve el nombre de columna presente en ``df`` (alias BCDM flexibles)."""
    norm_map = {_norm_col_key(str(c)): c for c in df.columns}
    for cand in candidates:
        for variant in (cand, cand.replace("/", "_")):
            nk = _norm_col_key(variant)
            if nk in norm_map:
                return norm_map[nk]
    for cand in candidates:
        for col in df.columns:
            if str(col).strip().lower() == cand.strip().lower():
                return str(col)
    return None


def _sequence_from_row(row: pd.Series) -> str:
    """Obtiene la secuencia nucleotídica de una fila si no hubo columna dedicada."""
    for name in row.index:
        ln = str(name).lower()
        if not any(
            x in ln
            for x in ("nuc", "nucleotide", "sequence", "barcode")
        ):
            continue
        val = row[name]
        if pd.isna(val):
            continue
        s = str(val).strip()
        if not s or s.lower() == "nan":
            continue
        if re.match(r"^[ACGTURYSWKMBDHVN\-\s]+$", s, re.I):
            return s
    for key in _SEQ_KEYS:
        if key in row.index and pd.notna(row[key]):
            s = str(row[key]).strip()
            if s:
                return s
    return ""


def fetch_bold_portal_json(taxon: str, session: Optional[requests.Session] = None) -> pd.DataFrame:
    """Ejecuta el flujo de 3 pasos del portal BOLD y devuelve un DataFrame BCDM.

    Pasos:
        1. GET ``/api/query/preprocessor?query=tax:<taxon>``
        2. GET ``/api/query?query=<términos validados>&extent=full`` → ``query_id``
        3. GET ``/api/documents/<query_id>/download?format=json``

    Args:
        taxon: Término taxonómico (sin el prefijo ``tax:``).
        session: Sesión HTTP opcional.

    Returns:
        DataFrame con columnas BCDM aplanadas (puede estar vacío).

    Raises:
        requests.HTTPError: Errores HTTP no resueltos tras reintentos.
        ValueError: JSON inválido, taxón no validado por el preprocesador, sin
            ``query_id``, o cuerpo vacío.
    """
    sess = session or requests.Session()
    q = f"tax:{taxon.strip()}"

    logging.info("Paso 1/3: validación (preprocessor) para %r.", q)
    r1 = portal_get(
        URL_PREPROCESSOR,
        session=sess,
        params={"query": q},
        step_name="preprocessor",
    )
    try:
        data1 = r1.json()
    except json.JSONDecodeError as exc:
        logging.error(
            "La respuesta del preprocesador no es JSON. Recorte: %s",
            (r1.text or "")[:500].replace("\n", "\\n"),
        )
        raise ValueError("El paso 1 no devolvió JSON válido (tripletes).") from exc

    logging.info("Respuesta preprocesador: %s", data1)
    validated_query = _validated_query_from_preprocessor(data1)
    logging.info("Término validado por BOLD: %s", validated_query)

    logging.info("Paso 2/3: obtención de query_id (query + extent=full).")
    r2 = portal_get(
        URL_QUERY,
        session=sess,
        params={"query": validated_query, "extent": "full"},
        step_name="query",
    )
    try:
        data2 = r2.json()
    except json.JSONDecodeError as exc:
        logging.error(
            "La respuesta del paso 2 no es JSON. Recorte: %s",
            (r2.text or "")[:500].replace("\n", "\\n"),
        )
        raise ValueError("El paso 2 no devolvió JSON válido (query_id).") from exc

    query_id = _extract_query_id(data2)
    if not query_id:
        logging.error(
            "No se pudo extraer query_id del JSON del paso 2. Claves raíz: %s",
            list(data2.keys()) if isinstance(data2, dict) else type(data2),
        )
        raise ValueError(
            "Respuesta del portal sin identificador de consulta (query_id). "
            "Revisa el taxón o inténtalo más tarde."
        )

    logging.info("query_id obtenido (longitud=%s).", len(query_id))

    safe_id = quote(query_id, safe="")
    download_url = f"{PORTAL_BASE.rstrip('/')}/documents/{safe_id}/download"

    logging.info("Paso 3/3: descarga JSON BCDM.")
    r3 = portal_get(
        download_url,
        session=sess,
        params={"format": "json"},
        step_name="download_json",
    )

    if not (r3.text or "").strip():
        logging.error("Respuesta vacía en la descarga JSON (paso 3).")
        raise ValueError("El paso 3 devolvió un cuerpo vacío.")

    records: list[Any] = []
    for line in r3.text.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as exc:
            logging.warning("Se omitió una línea corrupta en el JSONL: %s", exc)

    if not records:
        raise ValueError("No se pudieron extraer registros válidos del JSONL.")

    df = _bcdm_json_to_dataframe(records)
    logging.info("Descarga completada: %s filas en DataFrame.", len(df))
    return df


def curate_bold_dataframe(raw: pd.DataFrame) -> pd.DataFrame:
    """Filtra filas con secuencia y unifica columnas para CSV/FASTA."""
    if raw.empty:
        return raw.copy()

    logging.info("Limpiando datos (portal JSON / BCDM)...")

    nuc_col = _first_matching_column(raw, _SEQ_KEYS)

    if nuc_col is None:
        logging.warning(
            "No hay columna única de secuencia; se buscará por fila entre columnas."
        )

    pid_col = _first_matching_column(raw, _ID_KEYS)
    sp_col = _first_matching_column(raw, _SPECIES_KEYS)
    geo_col = _first_matching_column(raw, _GEO_KEYS)

    if pid_col is None:
        logging.warning("No se encontró columna de ID BCDM; processid será Unknown.")
    if sp_col is None:
        logging.warning("No se encontró columna de especie; species_name será Unknown.")
    if geo_col is None:
        logging.warning("No se encontró columna geográfica; country será Unknown.")

    rows_out: list[dict[str, Any]] = []
    for _, row in raw.iterrows():
        if nuc_col:
            seq_val = row.get(nuc_col)
            seq = (
                str(seq_val).strip()
                if pd.notna(seq_val) and str(seq_val).strip().lower() != "nan"
                else ""
            )
        else:
            seq = _sequence_from_row(row)

        if seq:
            seq = seq.replace("-", "")

        if not seq:
            continue

        def pick(col: Optional[str]) -> str:
            if col and col in row.index:
                v = row[col]
                if pd.isna(v) or str(v).strip() == "" or str(v).lower() == "nan":
                    return "Unknown"
                return str(v).strip()
            return "Unknown"

        rows_out.append(
            {
                "processid": pick(pid_col),
                "species_name": pick(sp_col),
                "country": pick(geo_col),
                "nucleotides": seq,
            }
        )

    out = pd.DataFrame(rows_out)
    logging.info(
        "Filas con secuencia válida: %s (descartadas sin secuencia: %s).",
        len(out),
        len(raw) - len(out),
    )
    return out


def export_metadata_csv(df: pd.DataFrame, output_path: str) -> None:
    """Escribe el CSV de metadatos con codificación UTF-8."""
    export_cols = ["processid", "species_name", "country", "nucleotides"]
    df[export_cols].to_csv(output_path, index=False, encoding="utf-8")
    logging.info("Metadatos guardados en: %s", output_path)


def export_fasta(df: pd.DataFrame, output_path: str) -> None:
    """Genera FASTA con encabezados ``>processid|species_name|country``."""
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
    """Orquesta diálogos, descarga portal, curación y archivos gemelos."""
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

        base = _sanitize_filename_token(taxon)
        out_path = Path(out_dir)
        csv_path_p, fasta_path_p = _get_unique_twin_filepaths(out_path, base)
        csv_path = str(csv_path_p)
        fasta_path = str(fasta_path_p)

        raw = fetch_bold_portal_json(taxon)
        curated = curate_bold_dataframe(raw)

        if curated.empty:
            messagebox.showwarning(
                "BOLD ETL",
                "No hay secuencias con datos genéticos para este taxón o el conjunto descargado está vacío.",
                parent=root,
            )
            logging.warning("No se generaron archivos: dataset vacío tras el filtrado.")
            return 1

        export_metadata_csv(curated, csv_path)
        export_fasta(curated, fasta_path)

        logging.info("Archivos guardados en: %s", out_dir)
        messagebox.showinfo(
            "BOLD ETL",
            f"Proceso finalizado.\n\nCSV:\n{csv_path}\n\nFASTA:\n{fasta_path}",
            parent=root,
        )
        return 0
    except Exception as exc:  # noqa: BLE001
        logging.exception("Error en el pipeline ETL: %s", exc)
        messagebox.showerror(
            "BOLD ETL — Error",
            f"Ocurrió un error:\n{exc}",
            parent=root,
        )
        return 1
    finally:
        root.destroy()


if __name__ == "__main__":
    raise SystemExit(run_pipeline())
