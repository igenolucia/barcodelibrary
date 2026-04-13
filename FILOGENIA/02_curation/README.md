# Phylogeny Tool - Public References Curation & Consolidation

Herramienta ETL (Extract, Transform, Load) diseñada para la fusión, limpieza y deduplicación forense de secuencias genéticas provenientes de las bases de datos de BOLD Systems y NCBI GenBank.

## ¿Para qué sirve este script?

Siguiendo el flujo de trabajo, este script busca resolver la redudancia entre los datos descargados de BOLD y NCBI, eliminando registros del mismo especímen.

Rastrea identificadores ocultos (`db_xref`) en NCBI, corta los sufijos de los marcadores genéticos (ej. `.COI-5P`), y elimina la copia de NCBI solo si coincide exactamente con el ID original de BOLD. Genera un dataset maestro unificado, eliminando clones sin destruir la información de variabilidad poblacional, dejándolo listo para el alineamiento múltiple (MAFFT/Geneious).

## Contenido del Repositorio

* **`etl_consolidation.py`**: Script principal. Fusiona los DataFrames, purga los duplicados confirmados mediante identificadores cruzados, y exporta la información manteniendo un formato visual de 4 columnas. Incluye control de versionado para evitar la sobrescritura de datos.
* **`requirements.txt`**: Manifiesto de dependencias *(heredado de la fase de ingesta)*. Ayuda a mantener la trazabilidad de los datos.

## 🚀 Guía Rápida de Uso

Para ejecutar este pipeline, asegúrate de tener **Python 3** instalado y las librerías activas en tu entorno virtual (venv), si lo tuvieses.

Abre tu terminal o línea de comandos y sigue estos pasos:

1. **Instalación de Dependencias** (Si no lo hiciste en la fase anterior):
   ```bash
   pip install pandas
   ```
2. **Ejecución**: Lanza el script principal.
   ```bash
   python etl_consolidation.py
   ```
3. **Filtro interactivo**: El programa abrirá una ventana emergente nativa pidiéndote que selecciones los dos archivos .csv generados en la fase de ingesta (BOLD y NCBI). A continuación, te pedirá seleccionar la carpeta de destino.

4. **Resultado**: El sistema cruzará los metadatos, purgará los clones detectados en NCBI y generará los archivos maestros consolidados.

## ¿Qué resultado devuelve?
Al ejecutar el script, se generan dos archivos vinculados para garantizar la observabilidad de los datos:

1. **Archivo Operativo (.fasta):**  Secuencias genéticas curadas listas para algoritmos de alineamiento. El encabezado mantiene el formato compatible con Geneious: >processid|species_name|country

2. **Archivo (.csv):** Tabla estructurada y unificada con las siguientes columnas:

 * `processid`: Identificador único de la muestra en BOLD.
   * `species_name`: Nombre del taxón.
   * `country`: País o región de origen del espécimen de referencia.
   * `nucleotides`: La secuencia de ADN limpia.

### ⚠️ Importante

* **Protección de Frecuencias Haplotípicas:** El script no elimina secuencias basándose en su identidad nucleotídica (lo cual destruiría datos valiosos de genética de poblaciones). Solo elimina registros si existe una prueba técnica (bold_id) de que se trata de un volcado redundante entre bases de datos.

