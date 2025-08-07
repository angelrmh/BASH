#!/bin/bash
# ======================================================
# 🔧 Script Avanzado para Recuperar VMs de Vagrant en macOS
# ✅ Con soporte --dry-run y log de auditoría
# Autor: NanelOps
# ======================================================

PROJECT_PATH="$1"
MODE="$2"  # Si el usuario pasa --dry-run
BACKUP_DIR="$HOME/vagrant_backups/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$PROJECT_PATH/recovery_log.txt"

log() {
  echo -e "$1" | tee -a "$LOG_FILE"
}

run_cmd() {
  if [[ "$MODE" == "--dry-run" ]]; then
    log "🟡 [SIMULADO] $1"
  else
    log "▶️ Ejecutando: $1"
    eval "$1" >>"$LOG_FILE" 2>&1
  fi
}

# --- Validación inicial ---
if [[ -z "$PROJECT_PATH" ]]; then
  echo "Uso: $0 /ruta/al/proyecto/vagrant [--dry-run]"
  exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "❌ Ruta no válida: $PROJECT_PATH"
  exit 1
fi

cd "$PROJECT_PATH" || exit 1

if [[ ! -f "Vagrantfile" ]]; then
  echo "❌ No se encontró Vagrantfile en $PROJECT_PATH"
  exit 1
fi

log "============================================="
log "🚀 INICIANDO RECUPERACIÓN DE VAGRANT VM"
log "📂 Proyecto: $PROJECT_PATH"
log "📄 Log: $LOG_FILE"
log "============================================="

# --- Backup automático ---
log "📦 Creando backup de seguridad en $BACKUP_DIR..."
if [[ "$MODE" != "--dry-run" ]]; then
  mkdir -p "$BACKUP_DIR"
  cp -r .vagrant "$BACKUP_DIR"/ 2>/dev/null
fi
log "✅ Backup creado."

# --- Detectar VMs definidas en el Vagrantfile ---
log "🔍 Buscando VMs definidas..."
VM_NAMES=$(grep "config.vm.define" Vagrantfile | awk -F'"' '{print $2}')
[[ -z "$VM_NAMES" ]] && VM_NAMES="default"
log "✅ Máquinas detectadas: $VM_NAMES"

# --- Procesar cada VM ---
for VM in $VM_NAMES; do
  log "==============================="
  log "🛠️ Procesando VM: $VM"
  log "==============================="

  VM_DIR=".vagrant/machines/$VM/virtualbox"
  ID_FILE="$VM_DIR/id"
  mkdir -p "$VM_DIR"

  # Buscar UUID en VirtualBox
  VM_UUID=$(VBoxManage list vms | grep "\"$VM\"" | awk '{print $2}' | tr -d '{}')

  if [[ -z "$VM_UUID" ]]; then
    log "⚠️ VM '$VM' no registrada. Buscando archivo .vbox..."
    VBOX_FILE=$(find ~/VirtualBox\ VMs -name "*.vbox" | grep "$VM" | head -n 1)
    if [[ -n "$VBOX_FILE" ]]; then
      run_cmd "VBoxManage registervm \"$VBOX_FILE\""
      VM_UUID=$(VBoxManage list vms | grep "\"$VM\"" | awk '{print $2}' | tr -d '{}')
    fi
  fi

  if [[ -z "$VM_UUID" ]]; then
    log "❌ No se pudo recuperar la VM '$VM'."
    continue
  fi

  log "✅ UUID detectado: $VM_UUID"

  # Reparar ID si es necesario
  if [[ ! -f "$ID_FILE" || "$(cat $ID_FILE 2>/dev/null)" != "$VM_UUID" ]]; then
    log "🔄 Reparando ID de Vagrant..."
    [[ "$MODE" != "--dry-run" ]] && echo "$VM_UUID" > "$ID_FILE"
    log "✅ ID corregido para $VM."
  fi

  # Verificar disco .vdi
  VDI_PATH=$(VBoxManage showvminfo "$VM_UUID" --machinereadable | grep -m1 "SATA-0-0" | cut -d'"' -f2)
  if [[ -z "$VDI_PATH" || ! -f "$VDI_PATH" ]]; then
    log "⚠️ Disco .vdi no encontrado. Buscando uno..."
    FOUND_VDI=$(find ~/VirtualBox\ VMs -name "*.vdi" | grep "$VM" | head -n 1)
    if [[ -n "$FOUND_VDI" ]]; then
      run_cmd "VBoxManage storageattach \"$VM_UUID\" --storagectl 'SATA Controller' --port 0 --device 0 --type hdd --medium \"$FOUND_VDI\""
      log "✅ Disco re-asociado."
    else
      log "❌ No se encontró disco para $VM. Revisión manual requerida."
    fi
  else
    log "✅ Disco .vdi presente."
  fi

  # Arrancar VM (si no es dry-run)
  run_cmd "vagrant up $VM"

done

log "🎉 Recuperación completada. Revisa el log: $LOG_FILE"

