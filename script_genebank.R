# =============================================================================
# IDENTIFICACIÓN TAXONÓMICA MEDIANTE GENBANK (BLAST + METADATOS)
# =============================================================================
#
# Flujo: lectura de secuencias FASTA, BLAST contra la base nt de NCBI,
# obtención del mejor hit y extracción de metadatos (especie, familia,
# localidad, publicacion_info) desde el registro completo en GenBank vía rentrez.
# Celdas sin dato se rellenan con 'No disponible' (protocolo de reporte).
#
# Paquetes: ape, rentrez, annotate (BLAST), dplyr.""
#
# =============================================================================

# -----------------------------------------------------------------------------
# PARTE 1: INSTALACIÓN Y CARGA DE PAQUETES
# -----------------------------------------------------------------------------

instalar_si_falta <- function(paquetes_cran, paquetes_bioc = character(0)) {
  if (length(paquetes_bioc) > 0 && !requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager", dependencies = TRUE)
  for (p in paquetes_cran) {
    if (!require(p, character.only = TRUE, quietly = TRUE))
      install.packages(p, dependencies = TRUE)
  }
  for (p in paquetes_bioc) {
    if (!require(p, character.only = TRUE, quietly = TRUE))
      BiocManager::install(p, update = TRUE, ask = FALSE)
  }
}

instalar_si_falta(c("dplyr", "ape", "rentrez"), c("annotate"))
library(dplyr)
library(ape)
library(rentrez)
library(annotate)

# -----------------------------------------------------------------------------
# PARTE 2: ENTRADA DE DATOS
# -----------------------------------------------------------------------------
# Solo se requieren archivos FASTA (p. ej. exportados desde Geneious).
# La carpeta de guardado se elige después de seleccionar los FASTA.

cat("\n  Selecciona los archivos FASTA a analizar.\n")
archivos_fasta <- choose.files(caption = "Selecciona los archivos FASTA", multi = TRUE)
if (length(archivos_fasta) == 0 || !nzchar(archivos_fasta[1])) stop("No se seleccionó ningún archivo FASTA.")

cat("  Selecciona la carpeta donde guardar los resultados.\n")
ruta_destino <- utils::choose.dir(caption = "Selecciona la carpeta para guardar los resultados")
if (is.na(ruta_destino) || !nzchar(ruta_destino)) stop("No se seleccionó carpeta de destino.")

# -----------------------------------------------------------------------------
# PARTE 3: LEER FASTA Y LIMPIAR NOMBRES
# -----------------------------------------------------------------------------
# Geneious y otros programas pueden añadir texto extra al nombre de la secuencia.
# Se conserva solo la primera palabra antes de cualquier espacio/tabulación y
# se aplica trimws para eliminar caracteres invisibles.

nombres_secuencias <- character(0)
secuencias_char <- character(0)

for (archivo in archivos_fasta) {
  sec_dna <- tryCatch(read.dna(archivo, format = "fasta", as.character = TRUE), error = function(e) NULL)
  if (is.null(sec_dna)) next
  if (is.list(sec_dna)) {
    for (j in seq_along(sec_dna)) {
      nom_limpio <- trimws(gsub("\\s+.*", "", names(sec_dna)[j]))
      if (is.na(nom_limpio) || !nzchar(nom_limpio)) nom_limpio <- trimws(names(sec_dna)[j])
      nombres_secuencias <- c(nombres_secuencias, nom_limpio)
      secuencias_char <- c(secuencias_char, paste(toupper(sec_dna[[j]]), collapse = ""))
    }
  } else if (is.matrix(sec_dna)) {
    for (j in seq_len(nrow(sec_dna))) {
      nom_limpio <- trimws(gsub("\\s+.*", "", rownames(sec_dna)[j]))
      if (is.na(nom_limpio) || !nzchar(nom_limpio)) nom_limpio <- trimws(rownames(sec_dna)[j])
      nombres_secuencias <- c(nombres_secuencias, nom_limpio)
      secuencias_char <- c(secuencias_char, paste(toupper(sec_dna[j, ]), collapse = ""))
    }
  }
}

n_total <- length(secuencias_char)
cat("  Secuencias a analizar:", n_total, "\n\n")

# -----------------------------------------------------------------------------
# FUNCIÓN: extraer_metadatos_genbank(id_acceso)
# -----------------------------------------------------------------------------
# Descarga el registro completo en formato GenBank y extrae:
#   - Especie: primera línea bajo ORGANISM.
#   - Familia: en la línea de taxonomía, el taxón que termina en '-idae'.
#   - Localidad: valor de /country o /geo_loc_name en FEATURES.
#   - Publicacion_Info: solo el país del bloque JOURNAL con "Submitted" (texto tras la última coma).
# Devuelve lista (especie, familia, localidad, publicacion_info); NA si no hay dato.

extraer_metadatos_genbank <- function(id_acceso) {
  out <- list(especie = NA_character_, familia = NA_character_, localidad = NA_character_, publicacion_info = NA_character_)
  if (is.na(id_acceso) || !nzchar(trimws(id_acceso))) return(out)

  gb <- tryCatch(
    rentrez::entrez_fetch(db = "nucleotide", id = trimws(as.character(id_acceso)), rettype = "gb", retmode = "text"),
    error = function(e) NULL
  )
  if (is.null(gb) || !nzchar(trimws(gb))) return(out)

  # --- Especie: primera línea tras "ORGANISM"
  if (grepl("ORGANISM", gb, ignore.case = TRUE)) {
    bloque_org <- sub("^.*?ORGANISM\\s+", "", gb, ignore.case = TRUE)
    lineas <- strsplit(bloque_org, "[\r\n]+")[[1]]
    if (length(lineas) >= 1 && nzchar(trimws(lineas[1])))
      out$especie <- trimws(lineas[1])
  }

  # --- Familia: en la taxonomía (líneas bajo ORGANISM), buscar palabra que termina en -idae
  if (grepl("ORGANISM", gb, ignore.case = TRUE)) {
    bloque_org <- sub("^.*?ORGANISM\\s+", "", gb, ignore.case = TRUE)
    lineas <- strsplit(bloque_org, "[\r\n]+")[[1]]
    if (length(lineas) > 1) {
      tax_lineas <- paste(lineas[-1], collapse = " ")
      tax_lineas <- gsub("\\s+", " ", trimws(tax_lineas))
      fam <- regmatches(tax_lineas, regexpr("[A-Za-z]+idae", tax_lineas))
      if (length(fam) > 0) out$familia <- fam[1]
    }
  }

  # --- Localidad: /country o /geo_loc_name en el registro
  if (grepl("/country\\s*=", gb, ignore.case = TRUE)) {
    m <- regmatches(gb, regexpr('/country\\s*=\\s*"([^"]*)"', gb, ignore.case = TRUE))
    if (length(m) > 0) out$localidad <- sub('.*"([^"]*)"$', "\\1", m[1])
  }
  if ((is.na(out$localidad) || !nzchar(out$localidad)) && grepl("/geo_loc_name\\s*=", gb, ignore.case = TRUE)) {
    m <- regmatches(gb, regexpr('/geo_loc_name\\s*=\\s*"([^"]*)"', gb, ignore.case = TRUE))
    if (length(m) > 0) out$localidad <- sub('.*"([^"]*)"$', "\\1", m[1])
  }

  # --- Publicacion_Info: solo el país (última ubicación) del bloque JOURNAL que contenga "Submitted".
  # Se toma el texto después de la última coma; se eliminan puntos finales, códigos postales y espacios.
  # Si el bloque es tipo "Unpublished" o no hay dirección, se devuelve NA -> "No disponible".
  out$publicacion_info <- tryCatch({
    pos <- gregexpr("JOURNAL\\s+", gb, ignore.case = TRUE)[[1]]
    if (length(pos) == 0 || pos[1] == -1) return(NA_character_)
    len_attr <- attr(pos, "match.length")
    blocks <- character(0)
    for (i in seq_along(pos)) {
      start <- pos[i] + len_attr[i]
      rest <- substr(gb, start, nchar(gb))
      end_match <- regexpr("[\r\n]+\\s*(REFERENCE|COMMENT|FEATURES|ORIGIN|//)\\s", rest, ignore.case = TRUE)
      block <- if (end_match > 0) substr(rest, 1L, end_match - 1L) else rest
      if (nchar(block) > 2500L) block <- substr(block, 1L, 2500L)
      blocks <- c(blocks, block)
    }
    idx <- which(grepl("Submitted", blocks, ignore.case = TRUE))[1]
    if (is.na(idx)) return(NA_character_)
    bloc <- blocks[idx]
    if (!grepl("Submitted", bloc, ignore.case = TRUE)) return(NA_character_)
    texto <- gsub("[\r\n]+", " ", bloc)
    texto <- gsub("\\s+", " ", trimws(texto))
    if (nchar(texto) > 1500L) texto <- substr(texto, 1L, 1500L)
    # País = texto después de la última coma (dirección típica: "Institution, City, Country")
    partes <- strsplit(texto, ",")[[1]]
    if (length(partes) == 0) return(NA_character_)
    ultimo <- trimws(partes[length(partes)])
    # Limpieza: quitar punto final, códigos postales (dígitos al final) y espacios sobrantes
    ultimo <- gsub("\\.+\\s*$", "", ultimo)
    ultimo <- gsub("\\s+[0-9]{4,}\\s*$", "", ultimo)
    ultimo <- gsub("\\s+", " ", trimws(ultimo))
    # Descartar "Unpublished" o referencias sin dirección real
    if (!nzchar(ultimo)) return(NA_character_)
    if (grepl("Unpublished", ultimo, ignore.case = TRUE)) return(NA_character_)
    if (grepl("^[0-9\\s.]+$", ultimo)) return(NA_character_)
    ultimo
  }, error = function(e) NA_character_)

  out
}

# -----------------------------------------------------------------------------
# FUNCIÓN: obtener_mejor_genbank(secuencia)
# -----------------------------------------------------------------------------
# BLAST contra nt; toma el hit con mayor % de identidad; obtiene id_acceso,
# descarga el registro con rentrez y extrae especie, familia, localidad y publicacion_info.

obtener_mejor_genbank <- function(secuencia) {
  out <- list(especie = "Sin coincidencias", familia = NA_character_, localidad = NA_character_, publicacion_info = NA_character_, similitud = 0, id_acceso = NA_character_)
  secuencia <- trimws(secuencia)
  if (nchar(secuencia) < 50) return(out)

  res <- tryCatch(
    blastSequences(x = secuencia, program = "blastn", database = "nt", hitListSize = 20, expect = 1e-5, timeout = 120, as = "data.frame"),
    error = function(e) NULL
  )
  if (is.null(res) || !is.data.frame(res) || nrow(res) == 0) return(out)

  nn <- names(res)
  id_col <- nn[grepl("Hsp_identity", nn, fixed = TRUE)]
  len_col <- nn[grepl("Hsp_align", nn)]
  if (length(id_col) == 0 || length(len_col) == 0) return(out)

  ident <- as.numeric(res[[id_col[1]]])
  leng <- as.numeric(res[[len_col[1]]])
  pident <- ifelse(leng > 0, 100 * ident / leng, 0)
  idx_mejor <- which.max(pident)
  if (length(idx_mejor) == 0 || is.na(pident[idx_mejor])) return(out)

  similitud <- round(pident[idx_mejor], 2)
  fila <- res[idx_mejor, ]
  hit_id_col <- nn[grepl("Hit_id", nn, fixed = TRUE)]
  hit_def_col <- nn[grepl("Hit_def", nn, fixed = TRUE)]
  texto <- paste(
    if (length(hit_id_col) > 0) as.character(fila[[hit_id_col[1]]]) else "",
    if (length(hit_def_col) > 0) as.character(fila[[hit_def_col[1]]]) else "",
    sep = " "
  )
  m <- regmatches(texto, regexpr("[A-Z]{2}[0-9]{5,}\\.?[0-9]*", texto, ignore.case = TRUE))
  id_acceso <- if (length(m) > 0 && nzchar(m[1])) m[1] else NA_character_

  if (is.na(id_acceso) || !nzchar(id_acceso)) {
    out$similitud <- similitud
    return(out)
  }

  meta <- extraer_metadatos_genbank(id_acceso)
  out$especie <- if (is.na(meta$especie) || !nzchar(trimws(meta$especie))) "Sin coincidencias" else trimws(meta$especie)
  out$familia <- if (is.na(meta$familia) || !nzchar(trimws(meta$familia))) NA_character_ else trimws(meta$familia)
  out$localidad <- if (is.na(meta$localidad) || !nzchar(trimws(meta$localidad))) NA_character_ else trimws(meta$localidad)
  out$publicacion_info <- if (is.na(meta$publicacion_info) || !nzchar(trimws(meta$publicacion_info))) NA_character_ else trimws(meta$publicacion_info)
  out$similitud <- similitud
  out$id_acceso <- id_acceso
  out
}

# -----------------------------------------------------------------------------
# PARTE 4: BUCLE PRINCIPAL (SOLO GENBANK)
# -----------------------------------------------------------------------------
# Por cada secuencia: BLAST, extracción de metadatos, mensaje de progreso
# y acumulación de filas para la tabla final.

resultados <- vector("list", n_total)

for (i in seq_len(n_total)) {
  nombre_sec <- nombres_secuencias[i]
  secuencia <- secuencias_char[i]
  longitud_bp <- nchar(secuencia)

  gb <- tryCatch(
    obtener_mejor_genbank(secuencia),
    error = function(e) list(especie = "Sin coincidencias", familia = NA_character_, localidad = NA_character_, publicacion_info = NA_character_, similitud = 0, id_acceso = NA_character_)
  )

  similitud <- if (length(gb$similitud) == 1 && !is.na(gb$similitud)) gb$similitud else 0
  cat("  Analizando ", nombre_sec, " | Longitud: ", longitud_bp, " bp | Similitud: ", similitud, "%\n", sep = "")

  # Protocolo CSIC: ninguna celda vacía ni NA; usar 'No disponible' cuando falte el dato
  especie_txt   <- if (is.na(gb$especie) || !nzchar(trimws(gb$especie))) "No disponible" else trimws(gb$especie)
  familia_txt   <- if (is.na(gb$familia) || !nzchar(trimws(gb$familia))) "No disponible" else trimws(gb$familia)
  localidad_txt <- if (is.na(gb$localidad) || !nzchar(trimws(gb$localidad))) "No disponible" else trimws(gb$localidad)
  publicacion_txt <- if (is.na(gb$publicacion_info) || !nzchar(trimws(gb$publicacion_info))) "No disponible" else trimws(gb$publicacion_info)
  accession_txt <- if (is.na(gb$id_acceso) || !nzchar(trimws(gb$id_acceso))) "No disponible" else as.character(trimws(gb$id_acceso))

  resultados[[i]] <- data.frame(
    ID_Secuencia      = nombre_sec,
    Especie_Sugerida  = especie_txt,
    Familia           = familia_txt,
    Localidad         = localidad_txt,
    Publicacion_Info  = publicacion_txt,
    Similitud_Perc    = similitud,
    Accession_GenBank = accession_txt,
    stringsAsFactors  = FALSE
  )
}

tabla_final <- dplyr::bind_rows(resultados)

# -----------------------------------------------------------------------------
# PARTE 5: EXPORTAR RESULTADOS
# -----------------------------------------------------------------------------
# Nombre por defecto: Resultados_Identificacion_GenBank.csv
# Si el archivo ya existe en la carpeta, se añade la fecha al nombre para no sobrescribir.

nombre_base <- "Resultados_Identificacion_GenBank.csv"
ruta_csv_final <- file.path(ruta_destino, nombre_base)
if (file.exists(ruta_csv_final)) {
  nombre_fecha <- paste0("Resultados_Identificacion_GenBank_", format(Sys.Date(), "%Y_%m_%d"), ".csv")
  ruta_csv_final <- file.path(ruta_destino, nombre_fecha)
}
write.csv(tabla_final, ruta_csv_final, row.names = FALSE, fileEncoding = "UTF-8")
cat("\n  Resultados guardados en:\n    ", ruta_csv_final, "\n", sep = "")
print(tabla_final)
