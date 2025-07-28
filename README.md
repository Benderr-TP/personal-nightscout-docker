# Nightscout Docker Deployment with Cloudflare Tunnel

Comprehensive Docker setup for deploying Nightscout with secure external access via Cloudflare Tunnel. Designed for local development and production deployment.

## Quick Start

### 🚀 One-Liner Setup (Recommended)

**Complete automated setup with Cloudflare tunnel:**
```bash
./setup.sh --domain nightscout.yourdomain.com --setup-tunnel
```

**Basic setup with domain (requires manual tunnel setup):**
```bash
./setup.sh --domain nightscout.yourdomain.com
```

This will:
- Generate secure credentials automatically
- Configure tunnel name as `nightscout-tunnel` (from hostname)
- Set custom title as "Nightscout Nightscout" (e.g., "Ns Nightscout" for ns.mydomain.com)
- Use sensible defaults (America/New_York timezone, mg/dl units)
- Optionally set up Cloudflare tunnel automatically

### Traditional Interactive Setup

1. **Run the setup script:**
   ```bash
   ./setup.sh
   ```
   This will:
   - Create a `.env` file from the template
   - Generate secure API_SECRET and MongoDB password
   - Configure timezone, display units, and custom title
   - Validate the configuration

2. **For local development:**
   ```bash
   docker-compose up -d
   ```



### Manual Cloudflare Tunnel Setup

If you prefer step-by-step setup:

1. **Set up Nightscout:**
   ```bash
   ./setup.sh --domain your.domain.com
   ```

2. **Set up Cloudflare Tunnel:**
   ```bash
   ./setup-cloudflare.sh --domain your.domain.com --tunnel-name your-tunnel
   ```

3. **Start services:**
   ```bash
   docker-compose up -d
   ```

4. **Access your Nightscout instance:**
   - Local: `http://localhost:8080`
   - Cloudflare: `https://your.domain.com`

### Command Line Options

**Setup Script (`./setup.sh`):**
- `--domain DOMAIN` - Set domain for Cloudflare tunnel
- `--setup-tunnel` - Automatically setup Cloudflare tunnel after basic setup
- `--help` - Show help message

**Cloudflare Script (`./setup-cloudflare.sh`):**
- `--domain DOMAIN` - Domain for tunnel routing  
- `--tunnel-name NAME` - Custom tunnel name (default: derived from domain)
- `--non-interactive` - Skip interactive prompts, use defaults
- `--help` - Show help message

### Examples

**Complete automated deployment:**
```bash
# One command to set up everything
./setup.sh --domain ns.mydomain.com --setup-tunnel
docker-compose up -d
# Access at https://ns.mydomain.com
```

**Step-by-step with custom tunnel name:**
```bash
# Setup with domain configuration
./setup.sh --domain monitoring.example.org

# Setup tunnel with custom name
./setup-cloudflare.sh --domain monitoring.example.org --tunnel-name monitoring-tunnel

# Start Nightscout
docker-compose up -d
```

**Interactive setup for customization:**
```bash
# Interactive mode for custom timezone, units, etc.
./setup.sh

# Interactive tunnel setup
./setup-cloudflare.sh
```

### Automatic Tunnel Naming

When you provide a domain like `monitoring.example.org`, the system automatically:
- Extracts hostname: `monitoring`
- Creates tunnel name: `monitoring-tunnel` 
- Sets title: "Monitoring Nightscout"

This ensures consistent, predictable naming across your infrastructure.

### Troubleshooting Cloudflare Issues

If the Cloudflare tunnel setup fails or doesn't provide external access:

1. **Run the comprehensive debug script:**
   ```bash
   ./debug-tunnel.sh
   ```

2. **Check tunnel status:**
   ```bash
   ./tunnel-status.sh
   ```

3. **View real-time logs:**
   ```bash
   ./tunnel-logs.sh
   ```

4. **Common fixes:**
   ```bash
   # Restart the tunnel service
   sudo systemctl restart cloudflared
   
   # Fix tunnel configuration
   ./fix-tunnel.sh
   
   # Complete tunnel cleanup and restart
   ./cleanup-tunnels.sh
   ./setup-cloudflare.sh
   ```

## Configuration

### Setup Scripts

- **`setup.sh`**: Interactive setup script that configures your environment
- **`setup-cloudflare.sh`**: Sets up Cloudflare Tunnel for secure external access
- **`validate.sh`**: Validates your configuration and Docker setup
- **`debug-tunnel.sh`**: Comprehensive diagnostics for Cloudflare tunnel issues
- **`fix-tunnel.sh`**: Quick fix script for common tunnel problems
- **`cleanup.sh`**: Complete cleanup of all containers and configurations
- **`cleanup-tunnels.sh`**: Cleanup unused Cloudflare tunnels

### Required Environment Variables

- `API_SECRET`: Long random string for API authentication (minimum 12 characters)
- `MONGO_INITDB_ROOT_PASSWORD`: MongoDB root password (minimum 8 characters)

### Important Settings

- `TZ`: Your timezone (e.g., `America/New_York`)
- `DISPLAY_UNITS`: `mg/dl` or `mmol/L`
- `CUSTOM_TITLE`: Your Nightscout site title
- `ENABLE`: Features to enable (see Nightscout documentation)



## Management Commands

### Validate configuration
```bash
./validate.sh
```

### View logs
```bash
docker-compose logs -f
```

### Update Nightscout
```bash
docker-compose down
docker-compose pull
docker-compose up -d
```

### Backup MongoDB
```bash
docker exec nightscout_mongo mongodump --out /data/db/backup
```

### Stop services
```bash
docker-compose down
```

### Cloudflare Tunnel Management
```bash
# Check tunnel status
./tunnel-status.sh

# View tunnel logs
./tunnel-logs.sh

# Restart tunnel
./tunnel-restart.sh

# Debug tunnel issues
./debug-tunnel.sh

# Fix common tunnel problems
./fix-tunnel.sh
```

## Security Notes

- Always change the default `API_SECRET` and `MONGO_INITDB_ROOT_PASSWORD`
- Use HTTPS in production (configure reverse proxy)
- Regularly update Docker images
- Consider firewall rules to restrict access

## Accessing Nightscout

After deployment, Nightscout will be available at:
- **Local:** `http://localhost:8080`
- **Cloudflare Tunnel:** `https://your-domain.com` (secure, external access)

**Note:** Port 8080 is mapped to Nightscout's internal port 1337.

## Troubleshooting

### Cloudflare Tunnel Issues

**Tunnel service not starting:**
```bash
# Check service status
sudo systemctl status cloudflared

# View detailed logs
sudo journalctl -u cloudflared -f

# Debug comprehensively
./debug-tunnel.sh
```

**External access not working:**
```bash
# Check tunnel connectivity
./debug-tunnel.sh

# Verify Nightscout is running locally
curl http://localhost:8080/api/v1/status

# Check DNS propagation
nslookup your-domain.com

# Test specific issues
./fix-tunnel.sh
```

**Authentication failures:**
```bash
# Re-authenticate with Cloudflare (browser required)
cloudflared tunnel login

# Check certificate
ls -la ~/.cloudflared/cert.pem

# Transfer certificate from another machine (if needed)
scp ~/.cloudflared/cert.pem user@server:~/.cloudflared/

# Recreate tunnel if needed
./cleanup-tunnels.sh
./setup-cloudflare.sh
```

### General Container Issues

**Container won't start:**
```bash
# Check logs
docker-compose logs nightscout
docker-compose logs mongo

# Validate configuration
./validate.sh
```

**Port 8080 already in use:**
```bash
# Find what's using the port
lsof -i :8080

# Stop conflicting service or change port in docker-compose.yml
```

**MongoDB connection issues:**
```bash
# Check if MongoDB container is running
docker ps | grep mongo

# Test MongoDB connectivity
docker exec nightscout_mongo mongosh --eval "db.adminCommand('ping')"

# Restart MongoDB container
docker-compose restart mongo
```

**Permission issues:**
```bash
# Make all scripts executable
chmod +x *.sh

# Check file permissions
ls -la *.sh
```

### Getting Help

1. **Run validation:** `./validate.sh` to check your configuration
2. **Debug tunnels:** `./debug-tunnel.sh` for Cloudflare issues
3. **Check logs:** `docker-compose logs -f`
4. **Review documentation:** [Nightscout docs](https://nightscout.github.io/) and [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
5. **Check logs and troubleshoot:** Use the provided debug scripts for issues

### Current Cloudflare API Commands (2025)

The scripts use the latest cloudflared command syntax:

**Tunnel Management:**
- `cloudflared tunnel create <name>` - Create a new tunnel
- `cloudflared tunnel list -o json` - List tunnels in JSON format
- `cloudflared tunnel info <name>` - Get tunnel information
- `cloudflared tunnel route dns <name> <domain>` - Route DNS to tunnel
- `cloudflared tunnel delete <name>` - Delete a tunnel

**Authentication:**
- `cloudflared tunnel login` - Browser-based authentication (required)
- Certificate transfer from authenticated machine (alternative)

**Service Management:**
- `cloudflared tunnel --config <path> run` - Run tunnel with config
- Service managed via systemd for production deployment

**Important Notes:**
- All scripts properly handle the `$REPLY` variable from `read -p` commands
- JSON parsing uses Python for reliability instead of grep/sed
- Commands validated against cloudflared 2025 release documentation
- **Browser authentication required** - API tokens not supported for tunnel creation

## Version Information

- **Nightscout Version:** 15.0.3 (pinned for stability)
- **MongoDB Version:** 4.4 (officially supported)
- **Node.js:** Latest LTS (included in official image)
- **Last Updated:** January 2025