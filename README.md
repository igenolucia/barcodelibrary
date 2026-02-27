# Barcode Library 🧬

Bienvenido/a a **Barcode Library**, un repositorio diseñado para alojar un flujo de trabajo (pipeline) bioinformático automatizado y reproducible para el procesamiento de secuencias de ADN (DNA barcoding).

Este proyecto está pensado para agilizar las etapas computacionales del trabajo de laboratorio. El flujo de trabajo cubierto por estos scripts **comienza una vez obtenidos los archivos `.fasta`** (tras las fases previas de extracción de ADN, amplificación, secuenciación y alineamiento en software como Geneious).

## Flujo de Trabajo y Estructura del Repositorio

El proyecto está modularizado para reflejar el orden secuencial de los análisis, desde el cruce de datos con bases de datos públicas hasta la visualización de resultados.

```text
📁 barcodelibrary/
│
├── 📄 README.md                 <-- Documentación principal del proyecto
├── 📄 .gitignore                
├── 📄 LICENSE                   
│
└── 📁 BLAST/                    <-- Fase 1: Consulta automatizada de secuencias
    ├── 📄 README.md             
    │
    ├── 📁 genbank/
    │   ├── 📄 README.md         
    │   └── 📜 blast_genbank_v1.R   
    │
    └── 📁 bold/
        ├── 📄 README.md         
        ├── 📜 limpiador_fasta.R    
        └── 📜 identificacion_bold.R