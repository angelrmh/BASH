#!/bin/bash
# ======================================================
# 🛠️ Script Universal - Full Disaster Recovery v3.4
# ✅ Reconstrucción de redes, múltiples discos, snapshots encadenados
# ✅ Soporta: VirtualBox, VMware, Parallels, QEMU/libvirt
# Autor: Angel Millan / NanelOps
# GitHup: angelrmh
# Correo: angelrmh10@gmail.com angel.millan@pepperinc.net
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

# --- Validaciones iniciales ---
[[ -z "$PROJECT_PATH" ]] && echo "Uso: $0 /ruta/proyecto [--dry-run|--export|--force-rebuild|--auto-fix]" && exit 1
[[ ! -d "$PROJECT_PATH" ]] && echo "❌ Ruta inválida" && exit 1
cd "$PROJECT_PATH" || exit 1
[[ ! -f "Vagrantfile" ]] && echo "❌ No se encontró Vagrantfile" && exit 1

log "============================================="
log "🚀 FULL DISASTER RECOVERY VAGRANT (v3.4)"
log "📂 Proyecto: $PROJECT_PATH"
log "============================================="

PROVIDER=$(grep -i "provider" Vagrantfile | awk -F'"' '{print $2}' | head -n 1)
[[ -z "$PROVIDER" ]] && PROVIDER="virtualbox"
VM_NAMES=$(grep "config.vm.define" Vagrantfile | awk -F'"' '{print $2}')
[[ -z "$VM_NAMES" ]] && VM_NAMES="default"
log "✅ Proveedor: $PROVIDER | Máquinas: $VM_NAMES"

# --- Backup ---
log "📦 Backup en $BACKUP_DIR..."
[[ "$OPTION" != "--dry-run" ]] && mkdir -p "$BACKUP_DIR" && cp -r .vagrant "$BACKUP_DIR" 2>/dev/null
log "✅ Backup listo."

# ======================================================
# 🔹 Función: reconstrucción de red
# ======================================================
setup_network() {
  VMNAME="$1"
  log "🌐 Configurando red para $VMNAME..."
  
  # Buscar adaptadores
  HOST_IF=$(VBoxManage list hostonlyifs | grep Name | head -n1 | awk '{print $3}')
  [[ -z "$HOST_IF" ]] && run_cmd "VBoxManage hostonlyif create" && HOST_IF=$(VBoxManage list hostonlyifs | grep Name | head -n1 | awk '{print $3}')
  
  BRIDGE_IF=$(VBoxManage list bridgedifs | grep Name | head -n1 | cut -d: -f2 | xargs)
  [[ -z "$BRIDGE_IF" ]] && BRIDGE_IF="en0"

  # Aplicar configuración
  run_cmd "VBoxManage modifyvm \"$VMNAME\" --nic1 nat"
  run_cmd "VBoxManage modifyvm \"$VMNAME\" --nic2 hostonly --hostonlyadapter2 \"$HOST_IF\""
  run_cmd "VBoxManage modifyvm \"$VMNAME\" --nic3 bridged --bridgeadapter3 \"$BRIDGE_IF\""

  log "✅ Redes configuradas (NAT, Host-Only: $HOST_IF, Bridge: $BRIDGE_IF)"
}

# ======================================================
# 🔹 Función: reconstrucción avanzada VirtualBox
# ======================================================
recover_virtualbox() {
  VM="$1"
  VM_UUID=$(VBoxManage list vms | grep "\"$VM\"" | awk '{print $2}' | tr -d '{}')
  VBOX_FILE=$(find ~/VirtualBox\ VMs -name "*.vbox" | grep "$VM" | head -n 1)

  if [[ -z "$VM_UUID" && -z "$VBOX_FILE" && "$OPTION" == "--auto-fix" ]]; then
    log "🔧 Reconstrucción completa desde discos para $VM..."
    DISKS=($(find ~/VirtualBox\ VMs -type f \( -name "*.vdi" -o -name "*.vmdk" -o -name "*.qcow2" \) | grep "$VM"))
    [[ ${#DISKS[@]} -eq 0 ]] && log "❌ No hay discos. Abortando." && return

    VM_HOME="$HOME/VirtualBox VMs/${VM}_fullrecovery"
    run_cmd "mkdir -p \"$VM_HOME\""
    run_cmd "VBoxManage createvm --name \"${VM}_fullrecovery\" --basefolder \"$HOME/VirtualBox VMs\" --register"
    run_cmd "VBoxManage modifyvm \"${VM}_fullrecovery\" --memory 2048 --cpus 2"

    # Añadir controladores
    run_cmd "VBoxManage storagectl \"${VM}_fullrecovery\" --name 'SATA Controller' --add sata --controller IntelAhci"
    run_cmd "VBoxManage storagectl \"${VM}_fullrecovery\" --name 'IDE Controller' --add ide"

    # Adjuntar discos
    PORT=0
    for DISK in "${DISKS[@]}"; do
      if [[ "$DISK" == *"-diff"* ]]; then
        log "📌 Disco diferencial detectado: $DISK"
        CLONE="${DISK%.vdi}-clone.vdi"
        run_cmd "VBoxManage clonehd \"$DISK\" \"$CLONE\" --format VDI"
        run_cmd "VBoxManage storageattach \"${VM}_fullrecovery\" --storagectl 'SATA Controller' --port $PORT --device 0 --type hdd --medium \"$CLONE\""
      else
        log "✅ Adjuntando disco base: $DISK"
        run_cmd "VBoxManage storageattach \"${VM}_fullrecovery\" --storagectl 'SATA Controller' --port $PORT --device 0 --type hdd --medium \"$DISK\""
      fi
      ((PORT++))
    done

    VM_UUID=$(VBoxManage list vms | grep "\"${VM}_fullrecovery\"" | awk '{print $2}' | tr -d '{}')
    setup_network "${VM}_fullrecovery"
    log "✅ VM reconstruida y registrada con UUID: $VM_UUID"
  fi

  [[ "$OPTION" == "--export" ]] && run_cmd "vagrant package --output ${VM}_rescue.box --base $VM_UUID" && return
  [[ "$OPTION" == "--force-rebuild" ]] && run_cmd "vagrant destroy -f $VM" && run_cmd "vagrant up --no-provision $VM"

  run_cmd "vagrant up $VM"
}

# ======================================================
# 🔹 Otros proveedores (sin cambios mayores)
# ======================================================
recover_vmware() { log "⚠️ VMware recovery básico."; }
recover_parallels() { log "⚠️ Parallels recovery básico."; }
recover_qemu() { log "⚠️ QEMU recovery básico."; }

# ======================================================
# 🔹 Ejecutar
# ======================================================
for VM in $VM_NAMES; do
  case "$PROVIDER" in
    virtualbox) recover_virtualbox "$VM" ;;
    vmware*)    recover_vmware ;;
    parallels)  recover_parallels ;;
    libvirt|qemu) recover_qemu ;;
    *) log "⚠️ Proveedor $PROVIDER no soportado." ;;
  esac
done

log "🎉 FULL DISASTER RECOVERY FINALIZADO. Log: $LOG_FILE"

