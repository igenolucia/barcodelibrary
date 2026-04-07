# Barcode Tool - NCBI/GenBank Automated Query

Herramienta diseñada para automatizar la consulta de secuencias de referencia en **NCBI/GenBank**, optimizando el flujo de trabajo en proyectos de **Barcoding y Megabarcoding**.

### ¿Para qué sirve este script?

La principal ventaja de esta herramienta es la **automatización del proceso de BLAST**. Este script permite ejecutar comparaciones masivas de archivos **FASTA** y estandarizar los resultados en un formato estructurado, eliminando la necesidad de realizar consultas manuales una a una. 

Además, extrae metadatos profundos (como el país de origen y la institución de la publicación) directamente desde los registros completos de GenBank.

### Contenido del Repositorio

* **Script de consulta (R)**: Automatización de la conexión con la API de GenBank (vía `annotate` y `rentrez`), procesamiento de secuencias en un solo flujo y extracción de metadatos estandarizados.

### 🚀 Guía Rápida de Uso

Para ejecutar este flujo de trabajo, sigue estos pasos:

1.  **Preparación**: Ten listas tus secuencias en formato **.FASTA**. Puedes seleccionar **uno o varios archivos** a la vez cuando el script abra la ventana emergente.
2.  **Destino**: A continuación, se abrirá otra ventana para que elijas la carpeta donde deseas guardar el resultado.
3.  **Ejecución**: El sistema gestionará automáticamente las dependencias (instalando `rentrez`, `ape`, `annotate`, etc. si te faltan) e informará en consola del progreso secuencia a secuencia. Está optimizado para gestionar tiempos de espera (*timeout* de 120s) en secuencias largas, asegurando estabilidad en la conexión.
4.  **Resultado**: Obtendrás un archivo **.csv** auto-versionado (ej. `Resultados_Identificacion_GenBank_YYYYMMDD_run1.csv`) para no sobrescribir datos de ejecuciones anteriores.

### ¿Qué resultado devuelve?

Al ejecutar el script, se genera una **tabla** estructurada bajo el protocolo de reporte estándar (celdas sin NA, usando "No disponible" cuando falta el dato), que integra estas 7 columnas:

* **`ID_Secuencia`**: Nombre limpio de tu secuencia original consultada.
* **`Especie_Sugerida`**: Especie de la mejor coincidencia (o aviso si no supera el umbral).
* **`Familia`**: Familia taxonómica (extraída buscando sufijos *-idae* en la taxonomía).
* **`Localidad`**: País o región de origen de la secuencia de referencia.
* **`Publicacion_Info`**: País o institución principal extraída del bloque *Submitted* de la publicación asociada.
* **`Similitud_Perc`**: Porcentaje de identidad real detectado (BLASTn).
* **`Accession_GenBank`**: Código de acceso único del hit ganador.

### Importante

* **Filtro de Longitud**: El script omite automáticamente el análisis de secuencias excesivamente cortas (menores a 50 pares de bases) para evitar ruido o falsos positivos.
* **Umbral de Calidad (Threshold)**: El script incluye un umbral de identidad configurable, establecido por defecto al **80%**. Si una secuencia no alcanza este porcentaje de similitud, la tabla registrará automáticamente *"Baja similitud (<80%)"* en las columnas de Especie y Familia.
* **Flexibilidad:** Este parámetro de umbral (`umbral_similitud = 80`) es totalmente modificable en el código para adaptarse a diferentes grupos taxonómicos o niveles de conservadurismo (ej. aumentarlo al 97% para identificaciones a nivel de especie más estrictas).

---
**Desarrollado por Lucía Igeño** - 2026