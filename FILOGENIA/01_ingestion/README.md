# Phylogeny Tool - BOLD Systems Data Ingestion

Herramienta ETL (Extract, Transform, Load) diseñada para la descarga masiva, estandarización y curación de secuencias genéticas desde la base de datos de BOLD Systems.

### ¿Para qué sirve este script?

A diferencia de las búsquedas locales, esta herramienta automatiza la fase de **ingesta de datos filogenéticos**. Al introducir un taxón (ej. *Pulchellodromus*), el script se conecta directamente a la API del BOLD Data Portal (formato BCDM/JSONL), extrae todas las secuencias públicas disponibles junto con sus metadatos (taxonomía y geografía), y las limpia automáticamente (descartando registros sin secuencia de ADN). 

Genera archivos listos para realizar alineamientos múltiples en software como Geneious, facilitando el trabajo manual para dar formato.

### Contenido del Repositorio

* `etl_bold_ingestion.py`: Script principal.Genera la conexión asíncrona en 3 pasos con BOLD, filtra los datos nulos e inyecta la información en los formatos operativos, aplicando control de versionado para evitar la pérdida de datos.
* `requirements.txt`: Manifiesto estricto de dependencias. Garantiza que el script se ejecute de forma 100% reproducible en cualquier ordenador.

### 🚀 Guía Rápida de Uso

Para ejecutar este flujo de trabajo, asegúrate de tener **Python 3** instalado en tu sistema. Se recomienda utilizar un entorno virtual (`venv`) para no interferir con las librerías globales de tu equipo.

Abre tu terminal o línea de comandos y sigue estos pasos:

1. **Instalación de Dependencias (Solo la primera vez):**
   Instala las librerías requeridas (pandas, requests) utilizando el manifiesto del proyecto.
   ```bash
   pip install -r requirements.txt
   ```

2. **Ejecución:**
   Lanza el script principal.
   ```bash
   python etl_bold_ingestion.py
   ```

3. **Filtro interactivo:** El programa abrirá ventanas emergentes nativas pidiéndote que introduzcas el nombre del taxón a buscar y que selecciones la carpeta de tu ordenador donde quieres guardar los resultados.

4. **Resultado:** El sistema negociará con la API de BOLD y generará los archivos automáticamente (añadiendo la fecha y sufijos como `_run1` si la carpeta ya contiene descargas previas).

### ¿Qué resultado devuelve?

Al ejecutar el script, se generan dos "archivos gemelos" vinculados para garantizar la observabilidad de los datos:

1. **Archivo Operativo (.fasta):** Secuencias genéticas listas para el alineamientos múltiples de secuencias (ej. algoritmo MAFFTA). El encabezado se formatea automáticamente usando barras verticales para que Geneious separe los metadatos en columnas:
   `>processid|species_name|country`

2. **Archivo Forense (.csv):** Tabla estructurada para auditoría visual con las siguientes columnas:
   * `processid`: Identificador único de la muestra en BOLD.
   * `species_name`: Nombre del taxón.
   * `country`: País o región de origen del espécimen de referencia.
   * `nucleotides`: La secuencia de ADN limpia.

### ⚠️ Importante

* **Recomendación - Conservación de Datos:** El pipeline clasifica intencionalmente la ausencia de datos geográficos o taxonómicos como `Unknown` en lugar de borrarlos del output. Una secuencia catalogada como "Pulchellodromus sp." o "Unknown" en BOLD podría ser genéticamente idéntica a linajes endémicos no descritos, por lo que puede ser útil taxonnómicamente conservarla para la evaluación en el árbol filogenético.
* **Resiliencia y Manejo de RAM:** El script incorpora una lógica de reintentos ante caídas del servidor de BOLD y procesa los datos línea por línea (JSON Lines). Esto evita colapsar la memoria de tu equipo al solicitar taxones con decenas de miles de secuencias.