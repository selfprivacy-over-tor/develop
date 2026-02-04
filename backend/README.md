# SelfPrivacy NixOS Backend over Tor (VirtualBox)

This folder contains the NixOS configuration to deploy a SelfPrivacy backend accessible via Tor hidden service (.onion address) in VirtualBox.

## What This Does

- Deploys the **real** SelfPrivacy GraphQL API (fetched from upstream)
- Configures Tor hidden service to expose the API via .onion address
- Sets up Redis, Nginx, and all required services
- Runs in VirtualBox on Ubuntu (or any Linux host)

## Prerequisites

- Ubuntu/Linux host with VirtualBox installed
- Nix package manager with flakes enabled
- Tor installed on host (for SOCKS5 proxy)

Install Nix if needed:
```bash
curl -L https://nixos.org/nix/install | sh -s -- --daemon
```

Enable flakes in `~/.config/nix/nix.conf`:
```
experimental-features = nix-command flakes
```

## A. Automatic Deployment (One Command)

```bash
./build-and-run.sh 2>&1 | tee /tmp/backend-build.log
```

This script:
1. Builds the NixOS system image
2. Creates a VirtualBox VM
3. Installs NixOS with SelfPrivacy backend
4. Starts Tor hidden service
5. Outputs the .onion address

## B. Manual Deployment Steps

### Step 1: Build the NixOS ISO

```bash
nix build .#default
```

This creates `result/iso/nixos-*.iso`.

### Step 2: Create VirtualBox VM

```bash
VM_NAME="SelfPrivacy-Tor-Test"
VBoxManage createvm --name "$VM_NAME" --ostype Linux_64 --register
VBoxManage modifyvm "$VM_NAME" --memory 2048 --cpus 2 --nic1 nat
VBoxManage modifyvm "$VM_NAME" --natpf1 "ssh,tcp,,2222,,22"
VBoxManage createmedium disk --filename "$HOME/VirtualBox VMs/$VM_NAME/$VM_NAME.vdi" --size 20000
VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAHCI
VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$HOME/VirtualBox VMs/$VM_NAME/$VM_NAME.vdi"
VBoxManage storagectl "$VM_NAME" --name "IDE Controller" --add ide
VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium result/iso/nixos-*.iso
```

### Step 3: Start VM and Install

```bash
VBoxManage startvm "$VM_NAME" --type headless
```

Wait for boot, then SSH in:
```bash
sshpass -p '' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost
```

Inside VM, install NixOS:
```bash
# Partition disk
parted /dev/sda -- mklabel msdos
parted /dev/sda -- mkpart primary ext4 1MiB 100%
mkfs.ext4 -L nixos /dev/sda1
mount /dev/sda1 /mnt

# Copy config from ISO
mkdir -p /mnt/etc/nixos
cp -r /selfprivacy-config/* /mnt/etc/nixos/

# Install
nixos-install --flake /mnt/etc/nixos#selfprivacy-tor-vm --no-root-passwd

# Reboot
reboot
```

### Step 4: Remove ISO and Restart

```bash
VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium emptydrive
VBoxManage startvm "$VM_NAME" --type headless
```

### Step 5: Get .onion Address

```bash
sshpass -p '' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost cat /var/lib/tor/hidden_service/hostname
```

## C. Viewing Backend Logs

### Live API Request Logs

```bash
sshpass -p '' ssh -p 2222 root@localhost journalctl -u selfprivacy-api -f
```

### Nginx Access Logs (see incoming requests)

```bash
sshpass -p '' ssh -p 2222 root@localhost journalctl -u nginx -f
```

### Combined Logs

```bash
sshpass -p '' ssh -p 2222 root@localhost journalctl -u nginx -u selfprivacy-api -f
```

### Check Service Status

```bash
sshpass -p '' ssh -p 2222 root@localhost systemctl status selfprivacy-api
sshpass -p '' ssh -p 2222 root@localhost systemctl status tor
sshpass -p '' ssh -p 2222 root@localhost systemctl status nginx
```

## Recovery Key

The backend stores recovery tokens in Redis. To view/create tokens:

```bash
# SSH into VM
sshpass -p '' ssh -p 2222 root@localhost

# Check Redis for tokens
redis-cli -s /run/redis-sp-api/redis.sock KEYS '*'
```

## VM Management Commands

```bash
# Start VM
VBoxManage startvm "SelfPrivacy-Tor-Test" --type headless

# Stop VM
VBoxManage controlvm "SelfPrivacy-Tor-Test" poweroff

# Check if running
VBoxManage list runningvms

# Delete VM completely
VBoxManage unregistervm "SelfPrivacy-Tor-Test" --delete
```

## Troubleshooting

### Tor not starting
```bash
sshpass -p '' ssh -p 2222 root@localhost journalctl -u tor -n 50
```

### API not responding
```bash
sshpass -p '' ssh -p 2222 root@localhost curl http://127.0.0.1:5050/api/version
```

### Check .onion is accessible
From host (requires Tor SOCKS proxy on port 9050):
```bash
curl --socks5-hostname 127.0.0.1:9050 http://YOUR_ONION_ADDRESS.onion/api/version
```
