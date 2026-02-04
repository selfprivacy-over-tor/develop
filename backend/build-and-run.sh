#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

VM_NAME="SelfPrivacy-Tor-Test"
VM_MEMORY=2048
VM_CPUS=2
VM_DISK_SIZE=10240
SSH_PORT=2222

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${GREEN}=== SelfPrivacy Tor VirtualBox Builder ===${NC}"
echo ""

# Check dependencies
if ! command -v VBoxManage &> /dev/null; then
    echo -e "${RED}Error: VirtualBox is not installed${NC}"
    exit 1
fi

if ! command -v sshpass &> /dev/null; then
    echo -e "${YELLOW}Installing sshpass...${NC}"
    sudo apt-get update && sudo apt-get install -y sshpass
fi

# SSH command helper
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o PreferredAuthentications=password"
do_ssh() {
    sshpass -p '' ssh -tt $SSH_OPTS -p $SSH_PORT root@localhost "$@"
}

# Check if VM exists
if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
    STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "^VMState=" | cut -d'"' -f2)

    if [ "$STATE" = "running" ]; then
        echo -e "${GREEN}VM is already running.${NC}"
        echo ""
        echo -e "SSH into VM:        ${CYAN}sshpass -p '' ssh $SSH_OPTS -p $SSH_PORT root@localhost${NC}"
        echo -e "Get .onion address: ${CYAN}sshpass -p '' ssh $SSH_OPTS -p $SSH_PORT root@localhost cat /var/lib/tor/hidden_service/hostname${NC}"
        echo ""

        # Try to get onion address
        ONION=$(sshpass -p '' ssh $SSH_OPTS -p $SSH_PORT root@localhost cat /var/lib/tor/hidden_service/hostname 2>/dev/null || echo "")
        if [ -n "$ONION" ]; then
            echo -e "Your .onion address: ${GREEN}$ONION${NC}"
            echo -e "Test in Tor Browser: ${CYAN}https://$ONION/${NC}"
        fi
        exit 0
    else
        echo -e "${YELLOW}VM exists but is stopped.${NC}"
        read -p "Delete and reinstall? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            # Just start it
            VBoxManage startvm "$VM_NAME" --type headless
            echo "Starting VM..."
            sleep 10
            echo -e "SSH into VM: ${CYAN}sshpass -p '' ssh $SSH_OPTS -p $SSH_PORT root@localhost${NC}"
            exit 0
        fi
        VBoxManage unregistervm "$VM_NAME" --delete
    fi
fi

# Build ISO
echo -e "${YELLOW}Step 1/7: Building NixOS ISO...${NC}"
cd "$SCRIPT_DIR/.."
git add virtualbox-test 2>/dev/null || true
cd "$SCRIPT_DIR"

if [ ! -L result ]; then
    nix build .#default
fi
ISO_PATH=$(readlink -f result/iso/*.iso)
echo -e "${GREEN}ISO: $ISO_PATH${NC}"

# Create VM
echo -e "${YELLOW}Step 2/7: Creating VM...${NC}"
VBoxManage createvm --name "$VM_NAME" --ostype "Linux_64" --register

VM_CFG=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "^CfgFile=" | sed 's/CfgFile="//' | sed 's/"$//')
VM_DIR=$(dirname "$VM_CFG")

VBoxManage modifyvm "$VM_NAME" \
    --memory $VM_MEMORY \
    --cpus $VM_CPUS \
    --vram 32 \
    --graphicscontroller vmsvga \
    --nic1 nat \
    --natpf1 "ssh,tcp,,$SSH_PORT,,22" \
    --audio-enabled off \
    --boot1 dvd \
    --boot2 disk \
    --ioapic on

VBoxManage createmedium disk --filename "${VM_DIR}/${VM_NAME}.vdi" --size $VM_DISK_SIZE --format VDI
VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "${VM_DIR}/${VM_NAME}.vdi"
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "$ISO_PATH"

echo -e "${GREEN}VM created${NC}"

# Start VM
echo -e "${YELLOW}Step 3/7: Booting from ISO...${NC}"
VBoxManage startvm "$VM_NAME" --type headless

# Wait for SSH
echo -e "${YELLOW}Step 4/7: Waiting for SSH (this takes ~60 seconds)...${NC}"
for i in $(seq 1 90); do
    if sshpass -p '' ssh $SSH_OPTS -o ConnectTimeout=2 -p $SSH_PORT root@localhost true 2>/dev/null; then
        echo -e "${GREEN}SSH ready!${NC}"
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

# Install NixOS
echo -e "${YELLOW}Step 5/7: Installing NixOS (this takes several minutes)...${NC}"

sshpass -p '' ssh $SSH_OPTS -p $SSH_PORT root@localhost 'bash -s' << 'EOF'
set -e
echo ">>> Partitioning..."
parted -s /dev/sda mklabel msdos
parted -s /dev/sda mkpart primary 1MiB 100%
echo ">>> Formatting..."
mkfs.ext4 -F -L nixos /dev/sda1
echo ">>> Waiting for disk to settle..."
sleep 2
udevadm settle 2>/dev/null || true
echo ">>> Mounting..."
mount /dev/sda1 /mnt
echo ">>> Installing NixOS..."
nixos-install --flake /iso/selfprivacy-config#selfprivacy-tor-vm --no-root-passwd --no-channel-copy
echo ">>> Done!"
EOF

echo -e "${GREEN}Installation complete!${NC}"

# Reboot into installed system
echo -e "${YELLOW}Step 6/7: Rebooting into installed system...${NC}"
VBoxManage controlvm "$VM_NAME" poweroff || true
sleep 3

VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 --medium emptydrive
VBoxManage modifyvm "$VM_NAME" --boot1 disk --boot2 none
VBoxManage startvm "$VM_NAME" --type headless

# Wait for SSH on installed system
echo "Waiting for system to boot..."
for i in $(seq 1 90); do
    if sshpass -p '' ssh $SSH_OPTS -o ConnectTimeout=2 -p $SSH_PORT root@localhost true 2>/dev/null; then
        echo -e "${GREEN}System ready!${NC}"
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

# Get onion address
echo -e "${YELLOW}Step 7/7: Getting .onion address...${NC}"
ONION=""
for i in $(seq 1 60); do
    ONION=$(sshpass -p '' ssh $SSH_OPTS -p $SSH_PORT root@localhost cat /var/lib/tor/hidden_service/hostname 2>/dev/null || true)
    if [ -n "$ONION" ]; then
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

# Final output
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   SelfPrivacy Tor VM is ready!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "Your .onion address:"
echo -e "  ${CYAN}$ONION${NC}"
echo ""
echo -e "Test in Tor Browser:"
echo -e "  ${CYAN}https://$ONION/${NC}"
echo ""
echo -e "SSH into VM:"
echo -e "  ${CYAN}ssh -p $SSH_PORT root@localhost${NC}"
echo ""
echo -e "Get .onion address:"
echo -e "  ${CYAN}ssh -p $SSH_PORT root@localhost cat /var/lib/tor/hidden_service/hostname${NC}"
echo ""
echo -e "Watch live requests:"
echo -e "  ${CYAN}ssh -p $SSH_PORT root@localhost journalctl -u nginx -u tor -f${NC}"
echo ""
