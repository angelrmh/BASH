#!/bin/bash

# Variables para el banner
SCRIPT_NAME="Backup index.html"
VERSION="1.0.0"
DESCRIPTION="Script para hacer backup del archivo index.html ubicado en /var/www/html."
RECOMENDACION="Correr este script con privilegio sudo o insertar en cron y que se ejecute cada hora."

# Incluir banner desde archivo o directamente si está embebido
source /home/vagrant/Banner_NanelOps.sh
nanelops_banner

# Detener servicio nginex
sudo systemctl stop nginx

# Ingresar a la carpeta /var/www/html
cd /var/www/html

# Nombre original del archivo
ORIGINAL="index.html"

# Nombre base del nuevo archivo
NUEVO="index_backup.html"

# Verificar si el archivo original existe
if [ ! -f "$ORIGINAL" ]; then
  echo "El archivo '$ORIGINAL' no existe. No se puede renombrar."
  exit 1
fi

# Si el nuevo archivo no existe, renombrar directamente
if [ ! -e "$NUEVO" ]; then
  sudo mv "$ORIGINAL" "$NUEVO"
  echo "Archivo renombrado como '$NUEVO'"
  exit 0
  fi

# Si ya existe, buscar un nombre con número consecutivo
i=1
while [ -e "${NUEVO%.html}_$i.html" ]; do
  ((i++))
done

# Nombre final disponible
FINAL="${NUEVO%.html}_$i.html"

# Renombrar archivo original
sudo mv "$ORIGINAL" "$FINAL"
echo "Archivo renombrado como '$FINAL'"
