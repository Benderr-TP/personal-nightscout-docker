# Nightscout Docker Deployment

Custom Docker setup for deploying Nightscout on Proxmox.

## Quick Start

1. **Copy environment file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` file with your settings:**
   - Change `API_SECRET` to a long random string
   - Change `MONGO_INITDB_ROOT_PASSWORD` to a secure password
   - Update other settings as needed

3. **For local development:**
   ```bash
   docker-compose up -d
   ```

4. **For Proxmox deployment:**
   ```bash
   docker-compose -f docker-compose.proxmox.yml up -d
   ```

## Configuration

### Required Environment Variables

- `API_SECRET`: Long random string for API authentication
- `MONGO_INITDB_ROOT_PASSWORD`: MongoDB root password

### Important Settings

- `TZ`: Your timezone (e.g., `America/New_York`)
- `DISPLAY_UNITS`: `mg/dl` or `mmol/L`
- `CUSTOM_TITLE`: Your Nightscout site title
- `ENABLE`: Features to enable (see Nightscout documentation)

## Deployment to Proxmox

### Prerequisites

1. Proxmox server with Docker installed
2. Domain name or DDNS setup
3. Reverse proxy configured (optional but recommended)

### Steps

1. **Transfer files to Proxmox:**
   ```bash
   scp -r . user@proxmox-server:/path/to/nightscout/
   ```

2. **SSH into Proxmox and navigate to directory:**
   ```bash
   ssh user@proxmox-server
   cd /path/to/nightscout/
   ```

3. **Set up environment:**
   ```bash
   cp .env.example .env
   nano .env  # Edit with your settings
   ```

4. **Deploy:**
   ```bash
   docker-compose -f docker-compose.proxmox.yml up -d
   ```

5. **Check status:**
   ```bash
   docker-compose -f docker-compose.proxmox.yml ps
   docker-compose -f docker-compose.proxmox.yml logs
   ```

## Management Commands

### View logs
```bash
docker-compose -f docker-compose.proxmox.yml logs -f
```

### Update Nightscout
```bash
docker-compose -f docker-compose.proxmox.yml down
docker-compose -f docker-compose.proxmox.yml pull
docker-compose -f docker-compose.proxmox.yml up -d
```

### Backup MongoDB
```bash
docker exec nightscout_mongo mongodump --out /data/db/backup
```

### Stop services
```bash
docker-compose -f docker-compose.proxmox.yml down
```

## Security Notes

- Always change the default `API_SECRET` and `MONGO_INITDB_ROOT_PASSWORD`
- Use HTTPS in production (configure reverse proxy)
- Regularly update Docker images
- Consider firewall rules to restrict access

## Accessing Nightscout

After deployment, Nightscout will be available at:
- Local: `http://localhost:1337`
- Proxmox: `http://your-proxmox-ip:1337`

For production use, configure a reverse proxy with SSL/TLS.

## Version Information

- **Nightscout Version:** 15.0.3+ (using latest tag)
- **MongoDB Version:** 4.4 (officially supported)
- **Node.js:** Latest LTS (included in official image)
- **Last Updated:** January 2025