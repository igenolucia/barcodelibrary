# =============================================================================
# Script: Procesar resultados CSV de BOLD Systems y generar tabla estandarizada
# Usa: dplyr, rvest, stringr, utils (file.choose, choose.dir)
# =============================================================================

if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
if (!requireNamespace("rvest", quietly = TRUE)) install.packages("rvest")
if (!requireNamespace("stringr", quietly = TRUE)) install.packages("stringr")
library(dplyr)
library(rvest)
library(stringr)

# -----------------------------------------------------------------------------
# 1. Leer el archivo CSV tal cual
# -----------------------------------------------------------------------------
cat("Selecciona el archivo CSV de resultados de BOLD...\n")
ruta_csv <- file.choose()
if (!file.exists(ruta_csv)) stop("No se ha seleccionado ningún archivo.")

# BOLD exporta con nombres que R convierte por defecto (Query.ID, ID., PID..BIN., etc.)
df_crudo <- read.csv(ruta_csv, stringsAsFactors = FALSE)
cat("Filas leídas:", nrow(df_crudo), "\n")

# -----------------------------------------------------------------------------
# 2. Filtrar el Top Hit usando los nombres que R asigna por defecto
# -----------------------------------------------------------------------------
datos <- df_crudo %>%
  group_by(Query.ID) %>%
  slice_max(order_by = ID., n = 1, with_ties = FALSE) %>%
  ungroup()
cat("Secuencias únicas:", nrow(datos), "\n")

# -----------------------------------------------------------------------------
# 3. Extraer el ID puro (ej: 'GBMNF35207-22' desde 'PID..BIN.')
# -----------------------------------------------------------------------------
datos$id_puro <- trimws(gsub("\\s*\\[.*$", "", datos$PID..BIN.))

# -----------------------------------------------------------------------------
# 4. Localización por web scraping de la ficha pública BOLD (portal)
# -----------------------------------------------------------------------------

obtener_localizacion <- function(id_puro) {
  if (length(id_puro) != 1 || is.na(id_puro) | id_puro == "") return("No disponible")
  url <- paste0("https://portal.boldsystems.org/record/", id_puro)
  for (intento in 1:3) {
    resultado <- tryCatch({
      pagina <- read_html(url)
      # html_text2 existe en rvest reciente; si no, usar html_text
      texto <- tryCatch(html_text2(pagina), error = function(e) html_text(pagina))
      # Capturar el texto después de 'Country/Ocean:' y 'Province/State:' y cortar antes de 'Collection Date' o \n
      m_pais <- str_match(texto, "Country/Ocean:\\s*([^\n]+)")
      m_prov <- str_match(texto, "Province/State:\\s*([^\n]+)")
      limpia <- function(x) {
        if (is.na(x) || x == "") return(NA_character_)
        x <- str_trim(x)
        x <- str_replace(x, "\\s*Collection Date.*$", "")
        str_trim(x)
      }
      pais <- if (!is.na(m_pais[1, 2])) limpia(m_pais[1, 2]) else NA_character_
      prov <- if (!is.na(m_prov[1, 2])) limpia(m_prov[1, 2]) else NA_character_
      if (is.na(pais) | (length(pais) > 0 && pais == "")) pais <- NA_character_
      if (is.na(prov) | (length(prov) > 0 && prov == "")) prov <- NA_character_
      if (is.na(pais) && is.na(prov)) return("No disponible")
      paste(c(na.omit(c(pais, prov))), collapse = ", ")
    }, error = function(e) {
      message("Fallo de conexión en ", id_puro, ", reintentando (intento ", intento, "/3)...")
      if (intento < 3) Sys.sleep(10)
      NULL
    })
    if (!is.null(resultado)) return(resultado)
  }
  return("No disponible")
}

ids_unicos <- unique(na.omit(datos$id_puro))
n_ids <- length(ids_unicos)
cat("Consultando API BOLD para", n_ids, "código(s)...\n")
localizaciones <- character(n_ids)
for (i in seq_along(ids_unicos)) {
  localizaciones[i] <- obtener_localizacion(ids_unicos[i])
  if (i %% 10 == 0 | i == n_ids) cat("  Progreso:", i, "/", n_ids, "\n")
  if (i < n_ids) Sys.sleep(sample(2:4, 1))
}
names(localizaciones) <- ids_unicos
datos$localizacion <- ifelse(is.na(datos$id_puro) | datos$id_puro == "", "No disponible",
                             localizaciones[datos$id_puro])
datos$localizacion[is.na(datos$localizacion) | datos$localizacion == ""] <- "No disponible"

# -----------------------------------------------------------------------------
# 5. Tabla final: usar nombres originales de BOLD (Query.ID, Family, Species, ID.)
# -----------------------------------------------------------------------------
tabla_final <- datos %>%
  transmute(
    Secuencia = Query.ID,
    Familia = ifelse(is.na(Family) | Family == "", "No disponible", Family),
    Especie_Sugerida = ifelse(is.na(Species) | Species == "", "No disponible", Species),
    Similitud_Porcentaje = ID.,
    Codigo_Acceso = ifelse(is.na(id_puro) | id_puro == "", "No disponible", id_puro),
    Localizacion = ifelse(is.na(localizacion) | localizacion == "", "No disponible", localizacion)
  )

# -----------------------------------------------------------------------------
# 6. Guardado: carpeta con choose.dir() y nombre fijo
# -----------------------------------------------------------------------------
cat("Selecciona la carpeta donde guardar el resultado...\n")
carpeta <- choose.dir()
if (is.na(carpeta)) carpeta <- dirname(ruta_csv)

archivo_salida <- file.path(carpeta, "Resultados_Identificacion_BOLD.csv")
write.csv(tabla_final, archivo_salida, row.names = FALSE)

cat("\nListo. Tabla guardada en:", archivo_salida, "\n")
cat("Filas en la tabla final:", nrow(tabla_final), "\n")
