# Barcode Tool - Database Consensus Merge

Herramienta diseñada para unificar y conciliar los resultados de las búsquedas de similitud (BLAST) obtenidas de GenBank y BOLD Systems, generando una tabla de consenso definitiva para proyectos de Barcoding.

### ¿Para qué sirve este script?

Este flujo de trabajo evalúa los resultados de las dos bases de datos globales y automatiza la toma de decisiones. En lugar de revisar manualmente qué repositorio dio el mejor resultado para cada secuencia, el script compara ambas tablas, filtra los datos incompletos y selecciona automáticamente la mejor identificación aplicando una lógica de desempate estandarizada (priorizando un mayor porcentaje de similitud y una mayor resolución taxonómica). 

Además, **garantiza la trazabilidad absoluta del dato**: los metadatos del mejor hit se mantienen intactos y cualquier información útil del hit descartado (como su ubicación o especie sugerida) se registra de forma segura en una columna de observaciones, evitando mezclas de datos erróneas.

### Contenido del Repositorio

* **`merge_resultados.R`**: Script principal. Lee los resultados previos, aplica los filtros de calidad, unifica los datos y genera el archivo de consenso.

### 🚀 Guía Rápida de Uso

Para ejecutar este flujo de trabajo, sigue estos pasos:

1. **Preparación**: Asegúrate de haber ejecutado previamente los scripts de GenBank y BOLD para tus secuencias y tener ambos archivos `.csv` listos.
2. **Ejecución**: Ejecuta el script `merge_resultados.R` en RStudio.
3. **Selección de Entradas**: El sistema abrirá ventanas emergentes pidiéndote que selecciones manualmente el archivo de resultados de GenBank y, posteriormente, el de BOLD.
4. **Guardado**: Finalmente, una última ventana te pedirá que elijas la carpeta de tu ordenador donde deseas guardar la tabla definitiva. El archivo se guardará automáticamente con un nombre versionado (ej. `Resultados_Consenso_YYYYMMDD_run1.csv`) para evitar sobrescribir análisis anteriores.

### ¿Qué resultado devuelve?

Al ejecutar el script, se genera un archivo `.csv` estructurado exactamente con estas 8 columnas. **Todos los datos (taxonomía, código, ubicación) pertenecen estricta y exclusivamente al "hit" ganador**:

* **`Secuencia`**: Nombre de tu secuencia original consultada.
* **`Familia`**: Familia taxonómica extraída del repositorio ganador.
* **`Especie_Sugerida`**: Nombre de la especie correspondiente a la mejor coincidencia.
* **`Similitud_Porcentaje`**: Porcentaje de identidad más alto entre ambas bases de datos.
* **`Codigo_Acceso`**: Identificador único (Accession Number o BIN) de la base de datos ganadora.
* **`Localizacion`**: País y provincia del espécimen de referencia del hit ganador.
* **`Fuente`**: Base de datos de la que proviene el hit ganador (GenBank o BOLD).
* **`Observaciones`**: Notas automatizadas sobre el segundo mejor hit (información extra o discrepancias taxonómicas).

### Importante

* **Filtrado y Exclusión**: El script evalúa cada coincidencia de BLAST y descarta automáticamente aquellas que carezcan de información útil (es decir, que muestren campos vacíos, "NA" o "No disponible" simultáneamente en Familia y Especie). Si una secuencia no obtiene ningún *hit* válido ni en GenBank ni en BOLD, será eliminada de la tabla de consenso final.
* **Lógica de Desempate**: Si existe un empate exacto en el porcentaje de similitud para la misma secuencia en ambas bases de datos, el sistema prioriza la identificación que llegue a nivel de especie frente a la que solo llega a familia. Si el empate persiste, se prioriza BOLD Systems por defecto.
* **Trazabilidad y Detección de Discrepancias**: El script nunca mezcla metadatos de distintos especímenes. Si la segunda base de datos aporta información relevante, lo anota en la columna `Observaciones`. 
    * *Si sugieren especies distintas*, alertará de la discordancia: `"Discordancia: GenBank sugiere Especie X (98%) [Loc: País]"`. 
    * *Si coinciden*, pero el hit descartado tiene datos de localización útiles, lo registrará como información adicional: `"Info extra Hit 2 (BOLD): Especie Y (99%) [Loc: País]"`. 
    * *Si no hay datos extra ni conflictos*, simplemente indicará `"No hay discordancia"`.