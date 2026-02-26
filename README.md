# Barcode Tool - NCBI/GenBank Automated Query

Herramienta diseñada para automatizar la consulta de secuencias de referencia en **NCBI/GenBank**, optimizando el flujo de trabajo en proyectos de **Megabarcoding**.

## ¿Para qué sirve este script?
La principal ventaja de esta herramienta es la **automatización del proceso de BLAST**. Este script permite:

1. **Consultas Masivas:** Ejecutar comparaciones de secuencias de forma automática mediante código.
2. **Filtrado de Resultados:** Procesar los resultados brutos para extraer solo la información relevante.
3. **Estandarización:** Convertir las respuestas del servidor en un formato de datos estructurado en formato de tabla.

## Contenido del Repositorio
* **Script de consulta (R):** Automatización de la conexión con la API de GenBank y ejecución de búsquedas.
* **Protocolo SOP:** Documentación técnica sobre los parámetros de búsqueda y criterios de selección de secuencias.
* **Licencia:** MIT License (Código abierto para investigación).

## ¿Qué resultado devuelve?
Al ejecutar el script, se genera una **tabla** que integra:
* **Asignación taxonómica:** Identificación vinculada a cada secuencia consultada.
* **Métricas de coincidencia:** Porcentaje de similitud con la secuencia de consulta.
* **Metadatos:** Acceso a los códigos de referencia y taxonomía oficial de GenBank.

## Parámetros de Calidad (Umbrales)
El script incluye un **umbral de identidad (threshold) ajustable**, configurado por defecto al **90%**.

* **Seguridad:** Este valor actúa como un primer filtro para asegurar que las asignaciones taxonómicas tengan una base de similitud sólida.
* **Flexibilidad:** El parámetro es totalmente modificable en el código para adaptarse a diferentes grupos taxonómicos o niveles de conservadurismo (ej. aumentar al 97% para identificaciones a nivel de especie más estrictas).

---
*Esta herramienta transforma una tarea manual de horas en un proceso automático de minutos, asegurando un control de calidad reproducible y eficiente.*

**Desarrollado por Lucía Igeño** - 2026