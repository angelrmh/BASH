#!/bin/bash
# ===========================================
# Script Avanzado para Recuperar VMs de Vagrant en macOS
# Autor: NanelOps
# ===========================================

PROJECT_PATH="$1"
BACKUP_DIR="$HOME/vagrant_backups/$(date +%Y%m%d_%H%M%S)"

# --- Validación inicial ---
if [[ -z "$PROJECT_PATH" ]]; then
  echo "Uso: $0 /ruta/al/proyecto/vagrant"
  exit 1
fi

cd "$PROJECT_PATH" || { echo "❌ No se pudo acceder a $PROJECT_PATH"; exit 1; }

if [[ ! -f "Vagrantfile" ]]; then
  echo "❌ No se encontró Vagrantfile en $PROJECT_PATH"
  exit 1
fi

# --- Backup automático ---
echo "📦 Creando backup de seguridad en $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
cp -r .vagrant "$BACKUP_DIR"/ 2>/dev/null
echo "✅ Backup de .vagrant guardado."

# --- Detectar VMs definidas en el Vagrantfile ---
echo "🔍 Detectando VMs definidas..."
VM_NAMES=$(grep "config.vm.define" Vagrantfile | awk -F'"' '{print $2}')
if [[ -z "$VM_NAMES" ]]; then
  VM_NAMES="default"
fi
echo "✅ Máquinas encontradas: $VM_NAMES"

# --- Procesar cada VM ---
for VM in $VM_NAMES; do
  echo "==============================="
  echo "🛠️ Recuperando VM: $VM"
  echo "==============================="

  VM_DIR=".vagrant/machines/$VM/virtualbox"
  ID_FILE="$VM_DIR/id"
  mkdir -p "$VM_DIR"

  # Buscar UUID en VirtualBox
  VM_UUID=$(VBoxManage list vms | grep "$VM" | awk '{print $2}' | tr -d '{}')

  if [[ -z "$VM_UUID" ]]; then
    echo "⚠️ No se encontró VM '$VM' en VirtualBox. Intentando registrar .vbox..."
    VBOX_FILE=$(find ~/VirtualBox\ VMs -name "*.vbox" | grep "$VM" | head -n 1)
    if [[ -n "$VBOX_FILE" ]]; then
      echo "📂 Registrando VM desde: $VBOX_FILE"
      VBoxManage registervm "$VBOX_FILE"
      VM_UUID=$(VBoxManage list vms | grep "$VM" | awk '{print $2}' | tr -d '{}')
    fi
  fi

  if [[ -z "$VM_UUID" ]]; then
    echo "❌ No se pudo recuperar VM '$VM'. Verifica los archivos .vbox/.vdi."
    continue
  fi

  echo "✅ UUID detectado: $VM_UUID"

  # Reasociar UUID si falta o está corrupto
  if [[ ! -f "$ID_FILE" || "$(cat $ID_FILE 2>/dev/null)" != "$VM_UUID" ]]; then
    echo "🔄 Reasociando ID de Vagrant con UUID real..."
    echo "$VM_UUID" > "$ID_FILE"
    echo "✅ ID corregido para $VM."
  fi

  # --- Verificar disco .vdi ---
  VDI_PATH=$(VBoxManage showvminfo "$VM_UUID" --machinereadable | grep -m1 "SATA-0-0" | cut -d'"' -f2)
  if [[ -z "$VDI_PATH" || ! -f "$VDI_PATH" ]]; then
    echo "⚠️ Disco .vdi no encontrado. Buscando uno coincidente..."
    FOUND_VDI=$(find ~/VirtualBox\ VMs -name "*.vdi" | grep "$VM" | head -n 1)
    if [[ -n "$FOUND_VDI" ]]; then
      echo "🔗 Asociando disco encontrado: $FOUND_VDI"
      VBoxManage storageattach "$VM_UUID" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$FOUND_VDI"
      echo "✅ Disco re-asociado."
    else
      echo "❌ No se encontró disco .vdi para $VM. Revisión manual requerida."
    fi
  else
    echo "✅ Disco .vdi está presente."
  fi

  # --- Arrancar VM ---
  echo "🚀 Iniciando $VM..."
  vagrant up "$VM" || echo "⚠️ Error al iniciar $VM. Revisa logs."

done

echo "🎉 Proceso de recuperación finalizado."

