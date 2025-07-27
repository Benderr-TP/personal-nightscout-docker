# Proxmox Container Deployment Guide

This guide covers deploying Nightscout as a container in Proxmox with automated backups.

## Option 1: LXC Container Deployment (Development Only)

⚠️ **Security Warning:** Docker in LXC containers exposes security risks by providing write access to host `/sys` and `/proc`. Use VM deployment for production environments.

### Create LXC Container

1. **Download Ubuntu template in Proxmox:**
   ```bash
   # In Proxmox shell
   pveam update
   pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
   ```

2. **Create LXC container:**
   ```bash
   pct create 200 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
     --hostname nightscout \
     --memory 2048 \
     --cores 2 \
     --rootfs local-lvm:8 \
     --net0 name=eth0,bridge=vmbr0,ip=dhcp \
     --unprivileged 1 \
     --features nesting=1 \
     --start 1
   ```

3. **Configure container for Docker:**
   ```bash
   # Enter container
   pct enter 200
   
   # Update system
   apt update && apt upgrade -y
   
   # Install Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sh get-docker.sh
   
   # Install Docker Compose
   apt install docker-compose-plugin -y
   
   # Create nightscout user
   useradd -m -s /bin/bash nightscout
   usermod -aG docker nightscout
   
   # Create app directory
   mkdir -p /opt/nightscout
   chown nightscout:nightscout /opt/nightscout
   ```

### Deploy Nightscout

4. **Transfer files to container:**
   ```bash
   # From your local machine
   scp -r . root@proxmox-ip:/tmp/nightscout-files/
   
   # In Proxmox, copy to container
   pct push 200 /tmp/nightscout-files /opt/nightscout --user nightscout --group nightscout
   ```

5. **Configure and start:**
   ```bash
   # Enter container as nightscout user
   pct enter 200
   su - nightscout
   cd /opt/nightscout
   
   # Set up environment
   cp .env.example .env
   nano .env  # Edit with your settings
   
   # Deploy
   docker compose -f docker-compose.proxmox.yml up -d
   ```

## Option 2: VM Deployment (Recommended for Production)

### Create VM Template

1. **Create Ubuntu VM:**
   ```bash
   # Create VM
   qm create 201 \
     --name nightscout-vm \
     --memory 2048 \
     --cores 2 \
     --net0 virtio,bridge=vmbr0 \
     --scsihw virtio-scsi-pci \
     --scsi0 local-lvm:32 \
     --ide2 local:iso/ubuntu-22.04-server-amd64.iso,media=cdrom \
     --boot c \
     --bootdisk scsi0 \
     --ostype l26
   
   # Start VM and complete Ubuntu installation
   qm start 201
   ```

2. **Configure VM post-installation:**
   ```bash
   # SSH into VM
   ssh user@vm-ip
   
   # Install Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo apt install docker-compose-plugin -y
   
   # Add user to docker group
   sudo usermod -aG docker $USER
   
   # Create app directory
   sudo mkdir -p /opt/nightscout
   sudo chown $USER:$USER /opt/nightscout
   ```

## Backup Configuration

### Proxmox Backup Jobs

1. **Create backup job for LXC container:**
   ```bash
   # In Proxmox shell - create backup job
   pvesh create /cluster/backup --id nightscout-backup \
     --node $(hostname) \
     --vmid 200 \
     --storage local \
     --dow mon,wed,fri \
     --starttime 02:00 \
     --mailnotification always \
     --mailto admin@yourdomain.com \
     --compress lzo \
     --mode snapshot
   ```

2. **Manual backup commands:**
   ```bash
   # Backup LXC container
   vzdump 200 --storage local --compress lzo --mode snapshot
   
   # Backup VM
   vzdump 201 --storage local --compress lzo --mode snapshot
   ```

### Application-Level Backups

3. **MongoDB backup script:**
   ```bash
   # Create backup script in container/VM
   cat > /opt/nightscout/backup.sh << 'EOF'
   #!/bin/bash
   
   BACKUP_DIR="/opt/nightscout/backups"
   DATE=$(date +%Y%m%d_%H%M%S)
   
   # Create backup directory
   mkdir -p $BACKUP_DIR
   
   # Backup MongoDB
   docker exec nightscout_mongo mongodump --out /data/db/backup_$DATE
   
   # Copy backup to host
   docker cp nightscout_mongo:/data/db/backup_$DATE $BACKUP_DIR/
   
   # Compress backup
   cd $BACKUP_DIR
   tar -czf nightscout_backup_$DATE.tar.gz backup_$DATE/
   rm -rf backup_$DATE/
   
   # Keep only last 7 backups
   ls -t nightscout_backup_*.tar.gz | tail -n +8 | xargs rm -f
   
   echo "Backup completed: nightscout_backup_$DATE.tar.gz"
   EOF
   
   chmod +x /opt/nightscout/backup.sh
   ```

4. **Set up cron job for regular backups:**
   ```bash
   # Add to crontab
   crontab -e
   
   # Add this line for daily backups at 3 AM
   0 3 * * * /opt/nightscout/backup.sh >> /var/log/nightscout-backup.log 2>&1
   ```

## Monitoring and Maintenance

### Health Check Script

```bash
# Create health check script
cat > /opt/nightscout/health-check.sh << 'EOF'
#!/bin/bash

# Check if containers are running
if ! docker compose -f /opt/nightscout/docker-compose.proxmox.yml ps | grep -q "Up"; then
    echo "ERROR: Nightscout containers not running"
    docker compose -f /opt/nightscout/docker-compose.proxmox.yml up -d
    exit 1
fi

# Check if Nightscout is responding
if ! curl -s http://localhost:1337 > /dev/null; then
    echo "ERROR: Nightscout not responding"
    exit 1
fi

echo "Nightscout is healthy"
EOF

chmod +x /opt/nightscout/health-check.sh
```

### Update Script

```bash
# Create update script
cat > /opt/nightscout/update.sh << 'EOF'
#!/bin/bash

cd /opt/nightscout

echo "Stopping Nightscout..."
docker compose -f docker-compose.proxmox.yml down

echo "Backing up before update..."
./backup.sh

echo "Pulling latest images..."
docker compose -f docker-compose.proxmox.yml pull

echo "Starting Nightscout..."
docker compose -f docker-compose.proxmox.yml up -d

echo "Update completed!"
EOF

chmod +x /opt/nightscout/update.sh
```

## Restore Procedures

### Restore from Proxmox Backup

```bash
# List available backups
vzdump list

# Restore LXC container
pct restore 200 /var/lib/vz/dump/vzdump-lxc-200-YYYY_MM_DD-HH_MM_SS.tar.lzo

# Restore VM
qmrestore /var/lib/vz/dump/vzdump-qemu-201-YYYY_MM_DD-HH_MM_SS.vma.lzo 201
```

### Restore MongoDB Data

```bash
# Stop Nightscout
docker compose -f docker-compose.proxmox.yml down

# Extract backup
cd /opt/nightscout/backups
tar -xzf nightscout_backup_YYYYMMDD_HHMMSS.tar.gz

# Restore to MongoDB
docker compose -f docker-compose.proxmox.yml up -d mongo
docker cp backup_YYYYMMDD_HHMMSS nightscout_mongo:/data/db/
docker exec nightscout_mongo mongorestore /data/db/backup_YYYYMMDD_HHMMSS

# Start Nightscout
docker compose -f docker-compose.proxmox.yml up -d
```

## Network Configuration

### Reverse Proxy Setup (Optional)

If using Nginx Proxy Manager or similar:

```nginx
# Nginx configuration snippet
location / {
    proxy_pass http://container-ip:1337;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 300;
    proxy_send_timeout 300;
    proxy_read_timeout 300;
}
```

### Firewall Rules

```bash
# Allow Nightscout port through Proxmox firewall
# In Proxmox web interface: Datacenter > Firewall > Add rule
# Or via CLI:
pvesh create /nodes/$(hostname)/firewall/rules --type in --action ACCEPT --proto tcp --dport 1337 --comment "Nightscout"
```

## Troubleshooting

### Common Commands

```bash
# Check container status
pct status 200

# View container logs
pct enter 200
docker compose -f /opt/nightscout/docker-compose.proxmox.yml logs -f

# Restart container
pct restart 200

# Check resource usage
pct config 200
```

### Performance Monitoring

```bash
# Monitor resource usage
docker stats

# Check disk usage
df -h
docker system df

# View system logs
journalctl -u docker
```