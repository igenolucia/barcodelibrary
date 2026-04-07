# =============================================================================
# MERGE RESULTADOS BLAST: GenBank + BOLD → Consenso
# =============================================================================
#
# Este script une los resultados de identificación taxonómica de GenBank y BOLD
# en un único dataframe, filtra hits sin información taxonómica útil y selecciona
# el mejor hit por secuencia (mayor similitud; desempate: especie > familia, BOLD).
#
# Columnas esperadas en ambos CSV (idénticas) + columna añadida en salida:
#   Secuencia, Familia, Especie_Sugerida, Similitud_Porcentaje, Codigo_Acceso, Localizacion, Fuente,
#   Observaciones
#
# Uso: ejecutar el script; se abrirán ventanas para elegir archivos y carpeta de salida.
# Dependencias: dplyr; tcltk (solo para elegir carpeta en sistemas no Windows).
#
# =============================================================================

generar_nombre_salida <- function(nombre_base, extension = ".csv", directorio = ".") {
  fecha_hoy <- format(Sys.Date(), "%Y%m%d")
  patron <- paste0("^", nombre_base, "_", fecha_hoy, "_run[0-9]+", extension, "$")
  archivos <- list.files(path = directorio, pattern = patron)
  return(file.path(directorio, paste0(nombre_base, "_", fecha_hoy, "_run", length(archivos) + 1, extension)))
}

# -----------------------------------------------------------------------------
# 1. SELECCIÓN INTERACTIVA DE ARCHIVOS Y CARPETA DE SALIDA
# -----------------------------------------------------------------------------
# No hay rutas fijas: el usuario elige todo mediante ventanas emergentes.

cat("\n")
cat("================================================================================\n")
cat("  MERGE RESULTADOS BLAST - GenBank + BOLD\n")
cat("================================================================================\n\n")

cat(">>> Por favor, selecciona el archivo CSV de resultados de GENBANK\n")
cat("    (ej.: Resultados_Identificacion_GenBank.csv)\n\n")
ruta_genbank <- file.choose()
if (length(ruta_genbank) == 0 || !nzchar(ruta_genbank)) {
  stop("No se seleccionó ningún archivo de GenBank. Ejecución cancelada.")
}

cat(">>> Por favor, selecciona el archivo CSV de resultados de BOLD\n")
cat("    (ej.: Resultados_Identificacion_BOLD.csv)\n\n")
ruta_bold <- file.choose()
if (length(ruta_bold) == 0 || !nzchar(ruta_bold)) {
  stop("No se seleccionó ningún archivo de BOLD. Ejecución cancelada.")
}

cat(">>> Ahora selecciona la CARPETA donde quieres guardar el archivo de resultados.\n")
cat("    El archivo se guardará con el nombre: Resultados_Consenso_YYYYMMDD_runX.csv\n\n")
# choose.dir() existe en Windows; en otros sistemas se usa tcltk
if (exists("choose.dir") && is.function(get("choose.dir", mode = "function"))) {
  carpeta_salida <- choose.dir()
} else {
  if (!requireNamespace("tcltk", quietly = TRUE)) {
    install.packages("tcltk", dependencies = TRUE)
  }
  carpeta_salida <- tcltk::tk_choose.dir()
}
if (length(carpeta_salida) == 0 || is.na(carpeta_salida) || !nzchar(carpeta_salida)) {
  stop("No se seleccionó ninguna carpeta de destino. Ejecución cancelada.")
}
directorio_salida <- carpeta_salida
ruta_salida <- NA_character_

cat("\nArchivos y carpeta seleccionados:\n")
cat("  GenBank:", ruta_genbank, "\n")
cat("  BOLD:   ", ruta_bold, "\n")
cat("  Salida: ", directorio_salida, "\n\n")

columnas_esperadas <- c(
  "Secuencia",
  "Familia",
  "Especie_Sugerida",
  "Similitud_Porcentaje",
  "Codigo_Acceso",
  "Localizacion",
  "Fuente"
)
columnas_salida <- c(columnas_esperadas, "Observaciones")

# -----------------------------------------------------------------------------
# 2. CARGA DE PAQUETES
# -----------------------------------------------------------------------------
if (!requireNamespace("dplyr", quietly = TRUE)) {
  install.packages("dplyr", dependencies = TRUE)
}
library(dplyr)

# Forzar uso de funciones dplyr (evitar masking por Bioconductor/otros paquetes)
select   <- dplyr::select
slice    <- dplyr::slice
filter   <- dplyr::filter
mutate   <- dplyr::mutate
arrange  <- dplyr::arrange
group_by <- dplyr::group_by
ungroup  <- dplyr::ungroup
bind_rows <- dplyr::bind_rows
across   <- dplyr::across
if_else  <- dplyr::if_else
left_join <- dplyr::left_join
full_join <- dplyr::full_join
case_when <- dplyr::case_when

# -----------------------------------------------------------------------------
# 3. FUNCIONES AUXILIARES
# -----------------------------------------------------------------------------

#' Comprueba si un valor se considera "información disponible" (no vacío, no NA, no "No disponible").
es_valido <- function(x) {
  if (is.null(x)) return(FALSE)
  if (length(x) == 0) return(FALSE)
  x <- as.character(x)
  x <- trimws(x)
  !is.na(x) & nzchar(x) & tolower(x) != "no disponible"
}

#' Lee un CSV de resultados BLAST y normaliza nombres de columnas y tipos.
#' Devuelve el dataframe con columnas estándar y columna extra 'Fuente' (GenBank/BOLD).
leer_resultados <- function(ruta, fuente = c("GenBank", "BOLD")) {
  fuente <- match.arg(fuente)
  if (!file.exists(ruta)) {
    stop("No se encuentra el archivo: ", ruta)
  }
  df <- read.csv(ruta, stringsAsFactors = FALSE, fileEncoding = "UTF-8", na.strings = c("", "NA"))
  # Normalizar nombres por si acaso vienen con espacios o variantes
  names(df) <- trimws(names(df))
  # Aceptar nombres alternativos típicos de GenBank (mapeo a nombres estándar)
  if ("ID_Secuencia" %in% names(df) && !"Secuencia" %in% names(df)) df$Secuencia <- df$ID_Secuencia
  if ("Similitud_Perc" %in% names(df) && !"Similitud_Porcentaje" %in% names(df)) df$Similitud_Porcentaje <- df$Similitud_Perc
  if ("Localidad" %in% names(df) && !"Localizacion" %in% names(df)) df$Localizacion <- df$Localidad
  if ("Accession_GenBank" %in% names(df) && !"Codigo_Acceso" %in% names(df)) df$Codigo_Acceso <- df$Accession_GenBank
  # Asegurar columna Fuente para desempate posterior
  df$Fuente <- fuente
  # Coerción de similitud a numérico (por si viene como carácter con coma decimal)
  if ("Similitud_Porcentaje" %in% names(df)) {
    df$Similitud_Porcentaje <- as.numeric(gsub(",", ".", as.character(df$Similitud_Porcentaje)))
  }
  df
}

# -----------------------------------------------------------------------------
# 4. LECTURA Y UNIÓN DE TABLAS
# -----------------------------------------------------------------------------
cat("Leyendo resultados de GenBank...\n")
genbank <- leer_resultados(ruta_genbank, "GenBank")

cat("Leyendo resultados de BOLD...\n")
bold <- leer_resultados(ruta_bold, "BOLD")

# Seleccionar solo las columnas estándar (Fuente ya está en columnas_esperadas)
columnas_con_fuente <- unique(c(columnas_esperadas, "Fuente"))
genbank <- genbank %>% select(any_of(columnas_con_fuente))
bold    <- bold %>% select(any_of(columnas_con_fuente))

# Comprobar que existen las columnas necesarias
faltan <- setdiff(columnas_esperadas, names(genbank))
if (length(faltan) > 0) {
  stop("En GenBank faltan columnas: ", paste(faltan, collapse = ", "))
}
faltan <- setdiff(columnas_esperadas, names(bold))
if (length(faltan) > 0) {
  stop("En BOLD faltan columnas: ", paste(faltan, collapse = ", "))
}

union_df <- bind_rows(genbank, bold)
cat("Total de filas unidas (GenBank + BOLD):", nrow(union_df), "\n")

# -----------------------------------------------------------------------------
# 5. FILTRADO: mantener solo hits con información taxonómica útil
# -----------------------------------------------------------------------------
# Se descartan filas donde tanto Familia como Especie_Sugerida están vacíos, NA o "No disponible".

union_df <- union_df %>%
  mutate(
    Familia_ok         = es_valido(.data$Familia),
    Especie_Sugerida_ok = es_valido(.data$Especie_Sugerida),
    tiene_info         = .data$Familia_ok | .data$Especie_Sugerida_ok
  )

antes_filtro <- nrow(union_df)
union_df <- union_df %>% filter(.data$tiene_info)
cat("Filas tras filtrar (al menos Familia o Especie_Sugerida válidos):", nrow(union_df),
    "(eliminadas:", antes_filtro - nrow(union_df), ")\n")

# -----------------------------------------------------------------------------
# 6. DISCREPANCIAS ENTRE FUENTES + RESCATE DE LOCALIZACION
# -----------------------------------------------------------------------------
# Antes de seleccionar el "Mejor Hit" final (slice(1)), preparamos:
# - Localizacion de cada fuente (siempre que exista), para rescatar si el mejor hit final queda con NA/"No disponible".
# - Observaciones: se calcula justo antes del slice dentro del bloque group_by + arrange.

# Normalización de similitud para evitar que NA arruinen el orden.
union_df <- union_df %>%
  mutate(
    Similitud_Porcentaje_orden = if_else(is.na(.data$Similitud_Porcentaje), -Inf, .data$Similitud_Porcentaje)
  )

# Resumen representativo de Localizacion por secuencia y fuente (sin seleccionar el "Mejor Hit" global aún).
per_fuente_localizacion <- union_df %>%
  group_by(.data$Secuencia, .data$Fuente) %>%
  summarise(
    Localizacion_mejor_fuente = {
      d <- dplyr::cur_data_all()
      d <- d[order(-d$Similitud_Porcentaje_orden), , drop = FALSE]
      loc_ok <- !is.na(d$Localizacion) &
        nzchar(trimws(as.character(d$Localizacion))) &
        tolower(trimws(as.character(d$Localizacion))) != "no disponible"
      d_valid <- d[loc_ok, , drop = FALSE]
      if (nrow(d_valid) > 0) as.character(d_valid$Localizacion[1]) else NA_character_
    },
    .groups = "drop"
  )

genbank_fuente <- per_fuente_localizacion %>%
  filter(.data$Fuente == "GenBank") %>%
  select(.data$Secuencia, Localizacion_GenBank = .data$Localizacion_mejor_fuente)

bold_fuente <- per_fuente_localizacion %>%
  filter(.data$Fuente == "BOLD") %>%
  select(.data$Secuencia, Localizacion_BOLD = .data$Localizacion_mejor_fuente)

localizacion_fuentes <- full_join(
  genbank_fuente,
  bold_fuente,
  by = "Secuencia"
)

# -----------------------------------------------------------------------------
# 7. MEJOR HIT POR SECUENCIA (con jerarquía de decisión)
# -----------------------------------------------------------------------------
# Jerarquía:
# 1) Mayor Similitud_Porcentaje.
# 2) Información a nivel de Especie (frente a solo Familia o "No disponible").
# 3) En caso de empate, priorizar BOLD.

union_df_mejor <- union_df %>%
  mutate(
    tiene_especie = .data$Especie_Sugerida_ok,
    orden_fuente  = as.integer(.data$Fuente == "BOLD")
  ) %>%
  group_by(.data$Secuencia) %>%
  arrange(
    desc(.data$Similitud_Porcentaje_orden),
    desc(.data$tiene_especie),
    desc(.data$orden_fuente),
    .by_group = TRUE
  ) %>%
  mutate(
    Observaciones = {
      valid_idx <- which(.data$Especie_Sugerida_ok)
      if (n() > 1 && length(valid_idx) > 1) {
        first_i <- valid_idx[1]
        last_i  <- valid_idx[length(valid_idx)]
        esp_first <- as.character(.data$Especie_Sugerida[first_i])
        esp_last  <- as.character(.data$Especie_Sugerida[last_i])
        if (!is.na(esp_first) && !is.na(esp_last) && esp_first != esp_last) {
          fuente_perdedora <- as.character(.data$Fuente[last_i])
          especie_perdedora <- esp_last
          similitud_perdedora <- .data$Similitud_Porcentaje[last_i]
          paste0(
            "Discordancia: ",
            fuente_perdedora,
            " sugiere ",
            especie_perdedora,
            " (",
            similitud_perdedora,
            "%)"
          )
        } else {
          "No hay discordancia"
        }
      } else {
        "No hay discordancia"
      }
    }
  ) %>%
  slice(1L) %>%
  ungroup()

# Eliminar columnas auxiliares y dejar solo columnas de salida (incluye Fuente y Observaciones)
resultado_final <- union_df_mejor %>%
  left_join(localizacion_fuentes, by = "Secuencia") %>%
  mutate(
    # Rescate de Localizacion: si el mejor hit final tiene NA/"No disponible",
    # usamos la Localizacion disponible de la otra fuente.
    Localizacion = case_when(
      !es_valido(.data$Localizacion) & .data$Fuente == "GenBank" & es_valido(.data$Localizacion_BOLD) ~ .data$Localizacion_BOLD,
      !es_valido(.data$Localizacion) & .data$Fuente == "BOLD" & es_valido(.data$Localizacion_GenBank) ~ .data$Localizacion_GenBank,
      TRUE ~ .data$Localizacion
    )
  ) %>%
  select(all_of(columnas_salida))

cat("Número de secuencias en el consenso (mejor hit por secuencia):", nrow(resultado_final), "\n")

# -----------------------------------------------------------------------------
# 8. EXPORTAR RESULTADO (con versionado dinámico)
# -----------------------------------------------------------------------------
# Asegurar que no queden NA en columnas de texto (opcional: reemplazar por "No disponible")
resultado_final <- resultado_final %>%
  mutate(across(
    c(Familia, Especie_Sugerida, Codigo_Acceso, Localizacion),
    ~ if_else(is.na(.) | !nzchar(trimws(as.character(.))), "No disponible", as.character(.))
  )) %>%
  # FILTRO RADICAL: Nos quedamos única y exclusivamente con las 8 columnas oficiales
  select(
    Secuencia,
    Familia,
    Especie_Sugerida,
    Similitud_Porcentaje,
    Codigo_Acceso,
    Localizacion,
    Fuente,
    Observaciones
  )

# Generar nombre de salida versionado dinámico
if (!dir.exists(directorio_salida)) dir.create(directorio_salida, recursive = TRUE)
ruta_salida <- generar_nombre_salida(
  nombre_base = "Resultados_Consenso",
  extension = ".csv",
  directorio = directorio_salida
)

write.csv(resultado_final, ruta_salida, row.names = FALSE, fileEncoding = "UTF-8")

cat("\nResultado guardado en:\n  ", ruta_salida, "\n", sep = "")
cat("Columnas exportadas:", paste(names(resultado_final), collapse = ", "), "\n")
