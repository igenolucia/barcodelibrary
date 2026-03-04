# =============================================================================
# MERGE RESULTADOS BLAST: GenBank + BOLD → Consenso
# =============================================================================
#
# Este script une los resultados de identificación taxonómica de GenBank y BOLD
# en un único dataframe, filtra hits sin información taxonómica útil y selecciona
# el mejor hit por secuencia (mayor similitud; desempate: especie > familia, BOLD).
#
# Columnas esperadas en ambos CSV (idénticas) + Fuente en salida:
#   Secuencia, Familia, Especie_Sugerida, Similitud_Porcentaje, Codigo_Acceso, Localizacion, Fuente
#
# Uso: ejecutar el script; se abrirán ventanas para elegir archivos y carpeta de salida.
# Dependencias: dplyr; tcltk (solo para elegir carpeta en sistemas no Windows).
#
# =============================================================================

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
cat("    El archivo se guardará con el nombre: Resultados_Consenso_GenBank_BOLD.csv\n\n")
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
ruta_salida <- file.path(carpeta_salida, "Resultados_Consenso_GenBank_BOLD.csv")

cat("\nArchivos y carpeta seleccionados:\n")
cat("  GenBank:", ruta_genbank, "\n")
cat("  BOLD:   ", ruta_bold, "\n")
cat("  Salida: ", ruta_salida, "\n\n")

columnas_esperadas <- c(
  "Secuencia",
  "Familia",
  "Especie_Sugerida",
  "Similitud_Porcentaje",
  "Codigo_Acceso",
  "Localizacion",
  "Fuente"
)

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
# 6. MEJOR HIT POR SECUENCIA
# -----------------------------------------------------------------------------
# - Agrupar por Secuencia.
# - Orden de prioridad: 1) Mayor Similitud_Porcentaje, 2) tener especie > solo familia, 3) BOLD por defecto.

union_df <- union_df %>%
  mutate(
    tiene_especie = .data$Especie_Sugerida_ok,
    # Para ordenar: BOLD primero en desempate (1 = BOLD, 0 = GenBank)
    orden_fuente  = as.integer(.data$Fuente == "BOLD")
  ) %>%
  group_by(.data$Secuencia) %>%
  arrange(
    desc(.data$Similitud_Porcentaje),
    desc(.data$tiene_especie),
    desc(.data$orden_fuente),
    .by_group = TRUE
  ) %>%
  slice(1L) %>%
  ungroup()

# Eliminar columnas auxiliares y dejar solo las columnas de salida (incluye Fuente)
resultado_final <- union_df %>%
  select(all_of(columnas_esperadas))

cat("Número de secuencias en el consenso (mejor hit por secuencia):", nrow(resultado_final), "\n")

# -----------------------------------------------------------------------------
# 7. EXPORTAR RESULTADO
# -----------------------------------------------------------------------------
# Asegurar que no queden NA en columnas de texto (opcional: reemplazar por "No disponible")
resultado_final <- resultado_final %>%
  mutate(across(
    c(Familia, Especie_Sugerida, Codigo_Acceso, Localizacion),
    ~ if_else(is.na(.) | !nzchar(trimws(as.character(.))), "No disponible", as.character(.))
  ))

# La carpeta ya fue elegida por el usuario; por si acaso se asegura que exista
if (!dir.exists(carpeta_salida)) dir.create(carpeta_salida, recursive = TRUE)
write.csv(resultado_final, ruta_salida, row.names = FALSE, fileEncoding = "UTF-8")

cat("\nResultado guardado en:\n  ", ruta_salida, "\n", sep = "")
cat("Columnas exportadas:", paste(names(resultado_final), collapse = ", "), "\n")
