# Limpiar cabeceras FASTA para BOLD (solo seqinr + utils)
library(seqinr)

# 1. Seleccionar archivo FASTA
cat("Selecciona tu archivo FASTA...\n")
ruta_entrada <- file.choose()
datos <- read.fasta(ruta_entrada, seqtype = "DNA", as.string = TRUE, forceDNAtolower = FALSE)

# 2. Quedarse solo con la primera palabra de cada nombre (antes del primer espacio)
limpiar <- function(nombre) {
  primera <- strsplit(trimws(nombre), "\\s+")[[1]][1]
  if (is.na(primera) || nchar(primera) == 0) primera <- "secuencia"
  gsub("[^A-Za-z0-9_]", "", primera)
}
nombres_limpios <- vapply(names(datos), limpiar, character(1), USE.NAMES = FALSE)

# 3. Elegir carpeta de salida (choose.dir solo disponible en Windows)
cat("Selecciona la carpeta donde guardar...\n")
carpeta <- choose.dir()
if (is.na(carpeta)) carpeta <- dirname(ruta_entrada)

# 4. Guardar con nombre fijo
archivo_salida <- file.path(carpeta, "secuencias_limpias_para_BOLD.fasta")
write.fasta(sequences = datos, names = nombres_limpios, file.out = archivo_salida)

cat("Listo. Guardado en:", archivo_salida, "\n")
