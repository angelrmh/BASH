#!/bin/bash
# ======================================================
# 🛠️ Script Universal para Recuperar VMs Vagrant (Multi-Proveedor)
# ✅ VirtualBox, VMware, Parallels, QEMU/libvirt
# ✅ Opciones --dry-run, --export, --force-rebuild
# Autor: NanelOps
# ======================================================

PROJECT_PATH="$1"
OPTION="$2"
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

# --- Validación inicial ---
if [[ -z "$PROJECT_PATH" ]]; then
  echo "Uso: $0 /ruta/proyecto [--dry-run|--export|--force-rebuild]"
  exit 1
fi
if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "❌ Ruta no válida: $PROJECT_PATH"
  exit 1
fi
cd "$PROJECT_PATH" || exit 1
[[ ! -f "Vagrantfile" ]] && echo "❌ No se encontró Vagrantfile" && exit 1

log "============================================="
log "🚀 RECUPERACIÓN MULTI-PROVEEDOR VAGRANT"
log "📂 Proyecto: $PROJECT_PATH"
log "📄 Log: $LOG_FILE"
log "============================================="

# --- Detectar proveedor desde el Vagrantfile ---
PROVIDER=$(grep -i "provider" Vagrantfile | awk -F'"' '{print $2}' | head -n 1)
[[ -z "$PROVIDER" ]] && PROVIDER="virtualbox"  # Default
log "✅ Proveedor detectado: $PROVIDER"

# --- Backup ---
log "📦 Backup en $BACKUP_DIR..."
[[ "$OPTION" != "--dry-run" ]] && mkdir -p "$BACKUP_DIR" && cp -r .vagrant "$BACKUP_DIR" 2>/dev/null
log "✅ Backup listo."

# --- Detectar VMs ---
VM_NAMES=$(grep "config.vm.define" Vagrantfile | awk -F'"' '{print $2}')
[[ -z "$VM_NAMES" ]] && VM_NAMES="default"
log "✅ Máquinas: $VM_NAMES"

# --- Funciones específicas por proveedor ---

recover_virtualbox() {
  VM="$1"
  VM_DIR=".vagrant/machines/$VM/virtualbox"
  ID_FILE="$VM_DIR/id"; mkdir -p "$VM_DIR"

  VM_UUID=$(VBoxManage list vms | grep "\"$VM\"" | awk '{print $2}' | tr -d '{}')
  [[ -z "$VM_UUID" ]] && log "⚠️ VM no registrada, buscando .vbox..." && VBOX_FILE=$(find ~/VirtualBox\ VMs -name "*.vbox" | grep "$VM" | head -n 1) && [[ -n "$VBOX_FILE" ]] && run_cmd "VBoxManage registervm \"$VBOX_FILE\"" && VM_UUID=$(VBoxManage list vms | grep "\"$VM\"" | awk '{print $2}' | tr -d '{}')
  if [[ "$OPTION" == "--dry-run" && -n "$VBOX_FILE" ]]; then
    log "🟡 [SIMULADO] Registrando VM con VBoxManage registervm..."
    VM_UUID="SIMULATED-UUID-DRYRUN-$RANDOM"
fi

[[ -z "$VM_UUID" ]] && log "❌ No se pudo recuperar $VM." && return

  log "✅ UUID: $VM_UUID"
  [[ ! -f "$ID_FILE" || "$(cat $ID_FILE)" != "$VM_UUID" ]] && [[ "$OPTION" != "--dry-run" ]] && echo "$VM_UUID" > "$ID_FILE"

  DISK_PATH=$(VBoxManage showvminfo "$VM_UUID" --machinereadable | grep -E 'SATA-0-0|IDE-0-0|SCSI-0-0' | cut -d'"' -f2)
  if [[ -z "$DISK_PATH" || ! -f "$DISK_PATH" ]]; then
    log "⚠️ Buscando disco (.vdi, .vmdk, .qcow2)..."
    FOUND_DISK=$(find ~/VirtualBox\ VMs -type f \( -name "*.vdi" -o -name "*.vmdk" -o -name "*.qcow2" -o -name "*.vhd" \) | grep "$VM" | head -n 1)
    [[ -n "$FOUND_DISK" ]] && STORAGE_CTL=$(VBoxManage showvminfo "$VM_UUID" --machinereadable | grep storagecontrollername | head -n 1 | cut -d'=' -f2 | tr -d '"') && [[ -z "$STORAGE_CTL" ]] && STORAGE_CTL="SATA Controller" && run_cmd "VBoxManage storageattach \"$VM_UUID\" --storagectl \"$STORAGE_CTL\" --port 0 --device 0 --type hdd --medium \"$FOUND_DISK\""
  else
    log "✅ Disco detectado: $DISK_PATH"
  fi

  [[ "$OPTION" == "--export" ]] && run_cmd "vagrant package --output ${VM}_rescue.box --base $VM_UUID" && return
  [[ "$OPTION" == "--force-rebuild" ]] && run_cmd "vagrant destroy -f $VM" && run_cmd "vagrant up --no-provision $VM"

  run_cmd "vagrant up $VM"
}

recover_vmware() {
  VMX=$(find ~/Documents ~/Virtual\ Machines -name "*.vmx" | head -n 1)
  [[ -z "$VMX" ]] && log "❌ No se encontró VM VMware." && return
  log "✅ VMX detectado: $VMX"
  [[ "$OPTION" == "--export" ]] && run_cmd "ovftool \"$VMX\" ${VM}_rescue.ova" && return
  [[ "$OPTION" == "--force-rebuild" ]] && run_cmd "vmrun stop \"$VMX\"" && run_cmd "vmrun start \"$VMX\" nogui"
  run_cmd "vmrun start \"$VMX\" nogui"
}

recover_parallels() {
  PVM=$(find ~/Parallels -name "*.pvm" | head -n 1)
  [[ -z "$PVM" ]] && log "❌ No se encontró VM Parallels." && return
  log "✅ PVM detectado: $PVM"
  [[ "$OPTION" == "--export" ]] && run_cmd "prlctl backup \"$PVM\"" && return
  [[ "$OPTION" == "--force-rebuild" ]] && run_cmd "prlctl stop \"$PVM\" --kill" && run_cmd "prlctl start \"$PVM\""
  run_cmd "prlctl start \"$PVM\""
}

recover_qemu() {
  QCOW=$(find ~/ -name "*.qcow2" | head -n 1)
  [[ -z "$QCOW" ]] && log "❌ No se encontró disco QEMU." && return
  log "✅ QCOW detectado: $QCOW"
  [[ "$OPTION" == "--export" ]] && run_cmd "qemu-img convert -O qcow2 \"$QCOW\" ${VM}_rescue.qcow2" && return
  log "ℹ️ Para iniciar usa tu gestor libvirt/virt-manager."
}

# --- Ejecutar recuperación según proveedor ---
for VM in $VM_NAMES; do
  case "$PROVIDER" in
    virtualbox) recover_virtualbox "$VM" ;;
    vmware*)    recover_vmware ;;
    parallels)  recover_parallels ;;
    libvirt|qemu) recover_qemu ;;
    *) log "⚠️ Proveedor $PROVIDER no soportado automáticamente." ;;
  esac
done

log "🎉 Proceso completado. Ver log: $LOG_FILE"

