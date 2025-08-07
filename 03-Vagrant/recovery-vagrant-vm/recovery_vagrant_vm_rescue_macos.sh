#!/bin/bash
# ======================================================
# 🔧 Script Ultra-Pro de Recuperación de VMs Vagrant en macOS
# ✅ Soporta .vdi, .vmdk, .vhd, .qcow2
# ✅ Opciones --dry-run, --export, --force-rebuild
# ✅ Backup + Log de auditoría
# Autor: NanelOps
# ======================================================

PROJECT_PATH="$1"
OPTION="$2"  # --dry-run, --export, --force-rebuild
BACKUP_DIR="$HOME/vagrant_backups/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$PROJECT_PATH/recovery_log.txt"

log() { echo -e "$1" | tee -a "$LOG_FILE"; }
run_cmd() {
  if [[ "$OPTION" == "--dry-run" ]]; then
    log "🟡 [SIMULADO] $1"
  else
    log "▶️ Ejecutando: $1"
    eval "$1" >>"$LOG_FILE" 2>&1
  fi
}

# --- Validación ---
if [[ -z "$PROJECT_PATH" ]]; then
  echo "Uso: $0 /ruta/al/proyecto/vagrant [--dry-run|--export|--force-rebuild]"
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
log "🚀 RECUPERACIÓN DE VM VAGRANT (Modo: ${OPTION:-normal})"
log "📂 Proyecto: $PROJECT_PATH"
log "📄 Log: $LOG_FILE"
log "============================================="

# --- Backup ---
log "📦 Backup inicial en $BACKUP_DIR..."
[[ "$OPTION" != "--dry-run" ]] && mkdir -p "$BACKUP_DIR" && cp -r .vagrant "$BACKUP_DIR"/ 2>/dev/null
log "✅ Backup listo."

# --- Detectar VMs ---
VM_NAMES=$(grep "config.vm.define" Vagrantfile | awk -F'"' '{print $2}')
[[ -z "$VM_NAMES" ]] && VM_NAMES="default"
log "✅ VMs detectadas: $VM_NAMES"

# --- Procesar cada VM ---
for VM in $VM_NAMES; do
  log "==============================="
  log "🛠️ Procesando VM: $VM"
  log "==============================="

  VM_DIR=".vagrant/machines/$VM/virtualbox"
  ID_FILE="$VM_DIR/id"
  mkdir -p "$VM_DIR"

  # Detectar UUID de VirtualBox
  VM_UUID=$(VBoxManage list vms | grep "\"$VM\"" | awk '{print $2}' | tr -d '{}')
  if [[ -z "$VM_UUID" ]]; then
    log "⚠️ VM no registrada, buscando .vbox..."
    VBOX_FILE=$(find ~/VirtualBox\ VMs -name "*.vbox" | grep "$VM" | head -n 1)
    [[ -n "$VBOX_FILE" ]] && run_cmd "VBoxManage registervm \"$VBOX_FILE\"" && VM_UUID=$(VBoxManage list vms | grep "\"$VM\"" | awk '{print $2}' | tr -d '{}')
  fi
  [[ -z "$VM_UUID" ]] && log "❌ No se pudo recuperar $VM." && continue
  log "✅ UUID: $VM_UUID"

  # Reparar ID de Vagrant
  [[ ! -f "$ID_FILE" || "$(cat $ID_FILE 2>/dev/null)" != "$VM_UUID" ]] && log "🔄 Corrigiendo ID..." && [[ "$OPTION" != "--dry-run" ]] && echo "$VM_UUID" > "$ID_FILE"

  # --- Detectar disco ---
  DISK_PATH=$(VBoxManage showvminfo "$VM_UUID" --machinereadable | grep -E 'SATA-0-0|IDE-0-0|SCSI-0-0' | cut -d'"' -f2)
  if [[ -z "$DISK_PATH" || ! -f "$DISK_PATH" ]]; then
    log "⚠️ Disco no detectado, buscando..."
    FOUND_DISK=$(find ~/VirtualBox\ VMs -type f \( -name "*.vdi" -o -name "*.vmdk" -o -name "*.vhd" -o -name "*.qcow2" \) | grep "$VM" | head -n 1)
    if [[ -n "$FOUND_DISK" ]]; then
      log "🔗 Encontrado: $FOUND_DISK"
      STORAGE_CTL=$(VBoxManage showvminfo "$VM_UUID" --machinereadable | grep -m1 "storagecontrollername" | cut -d'=' -f2 | tr -d '"')
      [[ -z "$STORAGE_CTL" ]] && STORAGE_CTL="SATA Controller"
      run_cmd "VBoxManage storageattach \"$VM_UUID\" --storagectl \"$STORAGE_CTL\" --port 0 --device 0 --type hdd --medium \"$FOUND_DISK\""
    else
      log "❌ No se halló ningún disco. Se recomienda --force-rebuild."
    fi
  else
    log "✅ Disco detectado: $DISK_PATH"
  fi

  # --- Exportar la VM a .box si se pidió ---
  if [[ "$OPTION" == "--export" ]]; then
    BOX_NAME="${VM}_rescue_$(date +%Y%m%d).box"
    log "📦 Exportando VM como box: $BOX_NAME"
    run_cmd "vagrant package --output $BOX_NAME --base $VM_UUID"
    log "✅ Box exportada: $PROJECT_PATH/$BOX_NAME"
    continue
  fi

  # --- Forzar reconstrucción si falla ---
  if [[ "$OPTION" == "--force-rebuild" ]]; then
    log "🔥 Forzando reconstrucción de $VM..."
    run_cmd "vagrant destroy -f $VM"
    run_cmd "vagrant up --no-provision $VM"
    [[ -n "$FOUND_DISK" ]] && run_cmd "VBoxManage storageattach \"$VM_UUID\" --storagectl \"$STORAGE_CTL\" --port 0 --device 0 --type hdd --medium \"$FOUND_DISK\""
    log "✅ VM reconstruida y disco re-asociado."
    continue
  fi

  # --- Arrancar VM normalmente ---
  run_cmd "vagrant up $VM"

done

log "🎉 Proceso completado. Ver log: $LOG_FILE"

