# Barcode Tool - BOLD Systems Data Processor

Herramienta diseñada para procesar y filtrar los resultados de búsquedas en el repositorio global de BOLD Systems.

## ¿Para qué sirve este script?

El proceso de búsqueda en BOLD se realiza de forma manual subiendo un archivo FASTA. Como la plataforma devuelve múltiples coincidencias (hasta 20 resultados) por cada secuencia consultada, esta herramienta limpia los datos (descartando coincidencias sin resolución taxonómica) y selecciona **hasta las 5 mejores coincidencias externas** para cada secuencia. Además, incorpora un filtro interactivo para ignorar las secuencias propias subidas a BOLD y se conecta a la base de datos para extraer la información taxonómica y geográfica del voucher original, facilitando inferencias biogeográficas.

## Contenido del Repositorio

* **`limpiador_fasta.R` (Opcional):** Script para limpiar y acortar los nombres de las secuencias en tu archivo `.fasta`. Solo es necesario usarlo si BOLD te da errores de lectura al intentar subir tus secuencias originales.
* **`script_bold.R`:** Script principal. Filtra el CSV de resultados de BOLD, elimina coincidencias vacías, excluye opcionalmente códigos de proyectos internos y automatiza la extracción del "Top 5" de metadatos geográficos externos.

## 🚀 Guía Rápida de Uso

Para ejecutar este flujo de trabajo, sigue estos pasos:

1. **Preparación y Búsqueda:** Genera un archivo único `.fasta` con todas tus secuencias (pásalo por el limpiador si BOLD da error de formato). Sube el archivo manualmente al motor de búsqueda de BOLD Systems.
2. **Descarga:** Una vez BOLD termine, descarga los resultados en formato `.csv`.
3. **Ejecución:** Ejecuta el script `script_bold.R` en RStudio. El programa te pedirá que selecciones el archivo `.csv` que acabas de descargar.
4. **Filtro interactivo:** La consola de R te preguntará si deseas excluir algún código de proyecto propio (ej. `CICOL`) para evitar autocoincidencias. Si quieres ver todos los resultados, simplemente pulsa `Enter`.
5. **Resultado:** El sistema procesará las secuencias, se conectará a las fichas públicas y generará una tabla final estandarizada.

## ¿Qué resultado devuelve?

Al ejecutar el script, se genera un archivo `.csv` estructurado en estas columnas:

* **Secuencia:** Nombre de tu secuencia original consultada.
* **Familia:** Familia taxonómica extraída del repositorio.
* **Especie_Sugerida:** Nombre de la especie correspondiente a la coincidencia.
* **Similitud_Porcentaje:** Porcentaje de identidad del resultado devuelto por BOLD.
* **Codigo_Acceso:** Identificador único en BOLD (Process ID o BIN).
* **Localizacion:** País y provincia del espécimen de referencia (extraídos automáticamente de la web).
* **Hit_Extraido:** El orden de la coincidencia (del 1 al 5) respecto a los resultados externos válidos.

## ⚠️ Importante

**Scraping:** Para la extracción de la localización, el código incorpora pausas aleatorias (entre 2 y 4 segundos) y un sistema de reintentos. Esto evita la saturación de los servidores de BOLD y previene el bloqueo de tu conexión IP durante procesamientos masivos.


