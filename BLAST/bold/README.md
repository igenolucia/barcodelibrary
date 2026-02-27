# Herramientas para BOLD Systems

Este sub-módulo contiene el flujo de trabajo específico para interactuar con la plataforma **Barcode of Life Data Systems (BOLD)**.

## 📜 Scripts Incluidos

1. **`limpiador_fasta.R`**: Prepara los archivos `.fasta` eliminando caracteres prohibidos y nombres excesivamente largos que causan errores en la subida a BOLD.
2. **`identificacion_bold.R`**: Realiza un *web scraping* automatizado de las fichas públicas de BOLD para extraer la localización (País/Provincia) de los *top hits*.

## ⚠️ Nota sobre el uso ético (Rate Limiting)
El script de identificación incluye pausas aleatorias (`Sys.sleep`) y un sistema de reintentos. **No modifiques estos tiempos**, ya que están diseñados para evitar la saturación de los servidores de BOLD y prevenir bloqueos de IP.