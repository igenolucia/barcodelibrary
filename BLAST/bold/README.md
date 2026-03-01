# Barcode Tool - BOLD Systems Data Processor

Herramienta diseñada para procesar y filtrar los resultados de búsquedas el repositorios global de BOLD Systems.

### ¿Para qué sirve este script?

El proceso de búsqueda en BOLD se realiza de forma manual subiendo un archivo FASTA. Como la plataforma devuelve múltiples coincidencias (hasta 20 resultados) por cada secuencia consultada, esta herramienta filtra y selecciona únicamente el mejor resultado para cada secuencia y, además, se conecta a la base de datos para extraer la información taxonómica y geográfica del voucher original.

### Contenido del Repositorio

* **`limpiador_fasta.R`** (Opcional): Script para limpiar y acortar los nombres de las secuencias en tu archivo .fasta. Solo es necesario usarlo si BOLD te da errores de lectura al intentar subir tus secuencias originales.
* **`script_bold.R`**: Script principal. Filtra el CSV de resultados de BOLD para quedarse con la mejor coincidencia por secuencia y automatiza la extracción de metadatos geográficos.

### 🚀 Guía Rápida de Uso

Para ejecutar este flujo de trabajo, sigue estos pasos:

1. **Preparación y Búsqueda**: Genera un archivo único .fasta con todas tus secuencias (pásalo por el limpiador si BOLD da error de formato). Sube el archivo manualmente al motor de búsqueda de BOLD Systems.
2. **Descarga**: Una vez BOLD termine, descarga los resultados en formato .csv.
3. **Ejecución**: Ejecuta el script `script_bold.R` en RStudio. El programa te pedirá que selecciones el archivo .csv que acabas de descargar.
4. **Resultado**: El sistema procesará las secuencias, se conectará a las fichas públicas y generará una tabla final estandarizada.

### ¿Qué resultado devuelve?

Al ejecutar el script, se genera un archivo .csv estructurado en estas columnas:

* **`Secuencia`**: Nombre de tu secuencia original consultada.
* **`Familia`**: Familia taxonómica extraída del repositorio.
* **`Especie_Sugerida`**: Nombre de la especie correspondiente a la mejor coincidencia.
* **`Similitud_Porcentaje`**: Porcentaje de identidad del mejor resultado devuelto por BOLD.
* **`Codigo_Acceso`**: Identificador único en BOLD (Process ID o BIN).
* **`Localizacion`**: País y provincia del espécimen de referencia (extraídos automáticamente de la web).

### Importante

* **Scraping**: Para la extracción de la localización, el código incorpora pausas aleatorias (entre 2 y 4 segundos) y un sistema de reintentos. Esto evita la saturación de los servidores de BOLD y previene el bloqueo de tu conexión durante procesamientos masivos.
