# Barcode Tool - NCBI/GenBank Automated Query

Herramienta diseñada para automatizar la consulta de secuencias de referencia en **NCBI/GenBank**, optimizando el flujo de trabajo en proyectos de **Megabarcoding**.

## ¿Para qué sirve este script?
La principal ventaja de esta herramienta es la **automatización del proceso de BLAST**. Este script permite ejecutar comparaciones masivas y estandarizar los resultados en un formato estructurado.

## Contenido del Repositorio
* **Script de consulta (R):** Automatización de la conexión con la API de GenBank y ejecución de búsquedas.
* **Licencia:** MIT License (Código abierto para investigación).

## 🚀 Guía Rápida de Uso

Para ejecutar este flujo de trabajo, sigue estos pasos:

1. **Preparación:** Ten listas tus secuencias en formato .FASTA, el script te acisará de cuándo cargarlas.
2. **Configuración:** Ajusta el umbral de identidad si es necesario (parámetro `threshold` en el script).
3. **Ejecución:** Ejecuta el script completo. El sistema gestionará automáticamente las dependencias necesarias.
4. **Resultado:** Obtendrás un archivo `.csv` con la taxonomía y métricas de calidad ya filtradas.

## ¿Qué resultado devuelve?
Al ejecutar el script, se genera una **tabla** que integra:
* **Asignación taxonómica:** Identificación vinculada a cada secuencia consultada.
* **Métricas de coincidencia:** Porcentaje de similitud con la secuencia de consulta.
* **Metadatos:** Acceso a los códigos de referencia y taxonomía oficial de GenBank.

## Importante
El script incluye un **umbral de identidad (threshold) ajustable**, configurado por defecto al **90%**.

* **Seguridad:** Este valor actúa como un primer filtro para asegurar que las asignaciones taxonómicas tengan una base de similitud sólida.
* **Flexibilidad:** El parámetro es totalmente modificable en el código para adaptarse a diferentes grupos taxonómicos o niveles de conservadurismo (ej. aumentar al 97% para identificaciones a nivel de especie más estrictas).

---
*Esta herramienta transforma una tarea manual en un proceso automático de menor duración, asegurando un control de calidad reproducible y eficiente.*



**Desarrollado por Lucía Igeño** - 2026