#!/bin/bash
# This script is sourced by build-and-run.sh for manual ISO installation

set -e

echo ""
echo -e "${YELLOW}Building NixOS ISO for manual installation...${NC}"

# Build the ISO if needed
if [ ! -L result ] || [ ! -f result/iso/*.iso ]; then
    cd "$SCRIPT_DIR/.."
    git add virtualbox-test 2>/dev/null || true
    cd "$SCRIPT_DIR"
    echo "Building ISO (this may take a while)..."
    nix build .#default -L
fi

ISO_PATH=$(readlink -f result/iso/*.iso)
echo -e "${GREEN}ISO ready: $ISO_PATH${NC}"
echo ""

# Delete existing VM if present
if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
    echo -e "${YELLOW}Removing existing VM...${NC}"
    VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
    sleep 2
    VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
fi

# Create VM
echo -e "${YELLOW}Creating VirtualBox VM...${NC}"
VBoxManage createvm --name "$VM_NAME" --ostype "Linux_64" --register

# Get VM directory
VM_CFG=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "^CfgFile=" | sed 's/CfgFile="//' | sed 's/"$//')
VM_DIR=$(dirname "$VM_CFG")

# Configure VM
VBoxManage modifyvm "$VM_NAME" \
    --memory $VM_MEMORY \
    --cpus $VM_CPUS \
    --vram 32 \
    --graphicscontroller vmsvga \
    --nic1 nat \
    --audio-enabled off \
    --boot1 dvd \
    --boot2 disk \
    --ioapic on \
    --vrde on \
    --vrdeport $VRDE_PORT

# Create virtual disk
VBoxManage createmedium disk --filename "${VM_DIR}/${VM_NAME}.vdi" --size $VM_DISK_SIZE --format VDI

# Add SATA controller and attach disk and ISO
VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "${VM_DIR}/${VM_NAME}.vdi"
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "$ISO_PATH"

echo -e "${GREEN}VM created successfully!${NC}"
echo ""

# Start VM
echo -e "${YELLOW}Starting VM...${NC}"
VBoxManage startvm "$VM_NAME" --type headless

echo ""
echo -e "${GREEN}=== VM Started (ISO Mode) ===${NC}"
echo ""
echo -e "${CYAN}The VM is now booting from the NixOS ISO.${NC}"
echo ""
echo -e "${YELLOW}Follow these steps to install:${NC}"
echo ""
echo "  1. Login as 'root' (press Enter)"
echo ""
echo "  2. Partition the disk:"
echo -e "     ${CYAN}parted /dev/sda -- mklabel msdos${NC}"
echo -e "     ${CYAN}parted /dev/sda -- mkpart primary 1MiB 100%${NC}"
echo -e "     ${CYAN}mkfs.ext4 -L nixos /dev/sda1${NC}"
echo ""
echo "  3. Mount and install:"
echo -e "     ${CYAN}mount /dev/disk/by-label/nixos /mnt${NC}"
echo -e "     ${CYAN}nixos-install --flake /iso/selfprivacy-config#selfprivacy-tor-vm --no-root-passwd${NC}"
echo ""
echo "  4. Eject ISO (Devices → Optical Drives → Remove) and reboot"
echo ""
echo -e "${GREEN}Opening VirtualBox GUI...${NC}"
virtualbox &>/dev/null &
