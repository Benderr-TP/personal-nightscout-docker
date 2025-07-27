# Nightscout Docker Deployment

Custom Docker setup for deploying Nightscout on Proxmox.

## Quick Start

### Basic Setup

1. **Run the setup script:**
   ```bash
   ./setup.sh
   ```
   This will:
   - Create a `.env` file from the template
   - Generate secure API_SECRET and MongoDB password
   - Configure timezone, display units, and custom title
   - Validate the configuration

2. **Alternative manual setup:**
   ```bash
   cp .env.example .env
   # Edit .env file with your settings
   ```

3. **For local development:**
   ```bash
   docker-compose up -d
   ```

4. **For Proxmox deployment:**
   ```bash
   docker-compose -f docker-compose.proxmox.yml up -d
   ```

### With Cloudflare Tunnel (Recommended for Production)

1. **Set up Nightscout:**
   ```bash
   ./setup.sh
   ```

2. **Set up Cloudflare Tunnel:**
   ```bash
   ./setup-cloudflare.sh
   ```
   This will:
   - Install cloudflared
   - Create a Cloudflare tunnel
   - Configure your domain
   - Set up HTTPS with SSL certificates
   - Create management scripts

3. **Start services:**
   ```bash
   docker-compose up -d
   ```

4. **Access your Nightscout instance:**
   - Local: `http://localhost:1337`
   - Cloudflare: `https://your-domain.com`

## Configuration

### Setup Scripts

- `setup.sh`: Interactive setup script that configures your environment
- `validate.sh`: Validates your configuration and Docker setup

### Required Environment Variables

- `API_SECRET`: Long random string for API authentication (minimum 12 characters)
- `MONGO_INITDB_ROOT_PASSWORD`: MongoDB root password (minimum 8 characters)

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

### Validate configuration
```bash
./validate.sh
```

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

### Cloudflare Tunnel Management
```bash
# Check tunnel status
./tunnel-status.sh

# View tunnel logs
./tunnel-logs.sh

# Restart tunnel
./tunnel-restart.sh
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

## Troubleshooting

### Common Issues

**Container won't start:**
```bash
# Check logs
docker-compose logs nightscout
docker-compose logs mongo

# Validate configuration
./validate.sh
```

**Port 1337 already in use:**
```bash
# Find what's using the port
lsof -i :1337

# Stop conflicting service or change port in .env
```

**MongoDB connection issues:**
```bash
# Check if MongoDB container is running
docker ps | grep mongo

# Restart MongoDB container
docker-compose restart mongo
```

**Permission issues:**
```bash
# Make scripts executable
chmod +x setup.sh validate.sh

# Check file permissions
ls -la
```

### Getting Help

1. Run `./validate.sh` to check your configuration
2. Check the logs: `docker-compose logs -f`
3. Review the [Nightscout documentation](https://nightscout.github.io/)
4. Check [DEPLOY.md](DEPLOY.md) for Proxmox-specific issues

## Version Information

- **Nightscout Version:** 15.0.3 (pinned for stability)
- **MongoDB Version:** 4.4 (officially supported)
- **Node.js:** Latest LTS (included in official image)
- **Last Updated:** January 2025