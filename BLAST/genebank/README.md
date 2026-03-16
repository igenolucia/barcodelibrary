  # Barcode Tool - NCBI/GenBank Automated Query

Herramienta diseñada para automatizar la consulta de secuencias de referencia en **NCBI/GenBank**, optimizando el flujo de trabajo en proyectos de **Megabarcoding**.

### ¿Para qué sirve este script?

La principal ventaja de esta herramienta es la **automatización del proceso de BLAST**. Este script permite ejecutar comparaciones masivas de archivos **multi-FASTA** y estandarizar los resultados en un formato estructurado, eliminando la necesidad de realizar consultas manuales una a una.

### Contenido del Repositorio

* **Script de consulta (R)**: Automatización de la conexión con la API de GenBank, procesamiento de múltiples secuencias en un solo flujo y ejecución de búsquedas.


### 🚀 Guía Rápida de Uso

Para ejecutar este flujo de trabajo, sigue estos pasos:

1.  **Preparación**: Ten listas tus secuencias en un único archivo **.FASTA** (multi-FASTA). El script abrirá una ventana emergente para que selecciones el archivo directamente.
2.  **Configuración**: El script está optimizado para gestionar tiempos de espera (*timeout*) en secuencias largas, asegurando estabilidad en la conexión con el servidor.
3.  **Ejecución**: Ejecuta el script completo en RStudio. El sistema gestionará automáticamente las dependencias necesarias e informará en consola de la longitud real de cada secuencia procesada.
4.  **Resultado**: Obtendrás un archivo **.csv** con la taxonomía, métricas de calidad y metadatos extendidos ya organizados.

### ¿Qué resultado devuelve?

Al ejecutar el script, se genera una **tabla** que integra:

* **Asignación taxonómica**: Identificación vinculada a cada secuencia consultada (Especie y Familia).
* **Métricas de coincidencia**: Porcentaje de similitud real detectado para cada secuencia individual.
* **Metadatos (Protocolo CSIC)**: Información detallada que incluye el código de acceso (Accession), la **localidad** de origen de la secuencia de referencia y la **información bibliográfica** o publicación asociada.

  El script incluye un **umbral** de identidad (threshold) ajustable, configurado por defecto al **90%**.

### Importante

* **Control de Calidad**: El script detecta automáticamente la longitud de cada secuencia, garantizando que los resultados de similitud sean precisos y no se acumulen datos de procesos anteriores.
* **Flexibilidad:** El parámetro es totalmente modificable en el código para adaptarse a diferentes grupos taxonómicos o niveles de conservadurismo (ej. aumentar al 97% para identificaciones a nivel de especie más estrictas).

Esta herramienta transforma una tarea manual en un proceso automático de menor duración, asegurando un control de calidad reproducible y eficiente.

---
**Desarrollado por Lucía Igeño** - 2026
