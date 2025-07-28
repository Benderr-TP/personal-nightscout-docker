# DevOps Quick Reference Guide

## Essential Commands

### Setup and Deployment
```bash
# One-liner complete setup
./setup.sh --domain your.domain.com --setup-tunnel
docker-compose up -d

# Step-by-step setup
./setup.sh --domain your.domain.com
./setup-cloudflare.sh --domain your.domain.com
docker-compose up -d

# Production deployment
docker-compose up -d
```

### Health Checks
```bash
# Validate configuration
./validate.sh

# Comprehensive diagnostics
./diagnose.sh

# Check container status
docker-compose ps
docker-compose top

# Test Nightscout API
curl -f http://localhost:8080/api/v1/status
```

### Logs and Debugging
```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f nightscout
docker-compose logs -f mongo

# Debug Cloudflare tunnel
./debug-tunnel.sh
./fix-tunnel.sh

# Check tunnel status
./tunnel-status.sh
```

### Backup and Restore
```bash
# MongoDB backup
docker exec nightscout_mongo mongodump --out /data/db/backup

# Volume backup
docker run --rm -v nightscout_mongo_data:/data -v $(pwd):/backup alpine tar czf /backup/mongo-backup.tar.gz -C /data .

# Restore MongoDB
docker exec -i nightscout_mongo mongorestore --archive < backup.archive
```

### Updates and Maintenance
```bash
# Update Nightscout
docker-compose down
docker-compose pull
docker-compose up -d

# Clean up Docker
docker system prune -f
docker volume prune -f

# Restart services
docker-compose restart
```

## Troubleshooting Commands

### Container Issues
```bash
# Check container health
docker-compose ps
docker stats

# Restart specific container
docker-compose restart nightscout
docker-compose restart mongo

# View container details
docker inspect nightscout
docker inspect nightscout_mongo
```

### Network Issues
```bash
# Test internal connectivity
docker exec nightscout ping mongo
docker exec nightscout_mongo ping nightscout

# Check network configuration
docker network ls
docker network inspect nightscout_network

# Test external connectivity
curl -I https://your.domain.com
```

### Database Issues
```bash
# Test MongoDB connection
docker exec nightscout_mongo mongosh --eval "db.adminCommand('ping')"

# Check MongoDB status
docker exec nightscout_mongo mongosh --eval "db.serverStatus()"

# View MongoDB logs
docker-compose logs mongo | grep -i error
```

### Cloudflare Tunnel Issues
```bash
# Check tunnel service
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f

# Recreate tunnel
./cleanup-tunnels.sh
./setup-cloudflare.sh --domain your.domain.com

# Test tunnel connectivity
cloudflared tunnel info your-tunnel-name
```

## Environment Management

### View Current Configuration
```bash
# Check environment variables
cat .env

# Validate configuration
./validate.sh

# Check Docker Compose config
docker-compose config
```

### Update Configuration
```bash
# Edit environment
nano .env

# Reload configuration
docker-compose down
docker-compose up -d

# Validate changes
./validate.sh
```

## Performance Monitoring

### Resource Usage
```bash
# Container resource usage
docker stats

# System resource usage
htop
df -h
free -h

# Disk usage by containers
docker system df
```

### Application Performance
```bash
# Test Nightscout response time
curl -w "@curl-format.txt" -o /dev/null -s http://localhost:8080/api/v1/status

# Monitor MongoDB performance
docker exec nightscout_mongo mongosh --eval "db.stats()"

# Check log file sizes
docker-compose logs --tail=100 | wc -l
```

## Security Commands

### Credential Management
```bash
# Generate new API secret
openssl rand -hex 32

# Generate new MongoDB password
openssl rand -base64 32

# Update credentials
sed -i 's/API_SECRET=.*/API_SECRET=new_secret/' .env
sed -i 's/MONGO_INITDB_ROOT_PASSWORD=.*/MONGO_INITDB_ROOT_PASSWORD=new_password/' .env
```

### Security Checks
```bash
# Check for exposed ports
netstat -tlnp | grep :8080

# Verify Cloudflare tunnel security
curl -I https://your.domain.com

# Check container security
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image nightscout/cgm-remote-monitor:15.0.3
```

## Backup and Recovery

### Automated Backup Script
```bash
#!/bin/bash
# backup.sh - Automated backup script

BACKUP_DIR="/opt/nightscout/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup MongoDB
docker exec nightscout_mongo mongodump --out /data/db/backup_$DATE
docker cp nightscout_mongo:/data/db/backup_$DATE $BACKUP_DIR/

# Backup volumes
docker run --rm -v nightscout_mongo_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/volume-backup_$DATE.tar.gz -C /data .

# Cleanup old backups (keep last 7)
find $BACKUP_DIR -name "backup_*" -mtime +7 -delete
find $BACKUP_DIR -name "volume-backup_*" -mtime +7 -delete

echo "Backup completed: $DATE"
```

### Recovery Procedures
```bash
# Stop services
docker-compose down

# Restore MongoDB
docker-compose up -d mongo
docker cp backup_YYYYMMDD_HHMMSS nightscout_mongo:/data/db/
docker exec nightscout_mongo mongorestore /data/db/backup_YYYYMMDD_HHMMSS

# Restore volumes
docker run --rm -v nightscout_mongo_data:/data -v $(pwd):/backup alpine tar xzf /backup/volume-backup_YYYYMMDD_HHMMSS.tar.gz -C /data

# Start services
docker-compose up -d
```

## Monitoring Scripts

### Health Check Script
```bash
#!/bin/bash
# health-check.sh - Automated health check

# Check if containers are running
if ! docker-compose ps | grep -q "Up"; then
    echo "ERROR: Containers not running"
    docker-compose up -d
    exit 1
fi

# Check Nightscout API
if ! curl -f http://localhost:8080/api/v1/status > /dev/null 2>&1; then
    echo "ERROR: Nightscout API not responding"
    exit 1
fi

# Check Cloudflare tunnel
if ! curl -f https://your.domain.com > /dev/null 2>&1; then
    echo "WARNING: Cloudflare tunnel may be down"
fi

echo "All systems operational"
```

### Resource Monitor
```bash
#!/bin/bash
# resource-monitor.sh - Monitor system resources

echo "=== System Resources ==="
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "Memory Usage: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
echo "Disk Usage: $(df / | tail -1 | awk '{print $5}')"

echo -e "\n=== Docker Resources ==="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

echo -e "\n=== Container Status ==="
docker-compose ps
```

## Emergency Procedures

### Service Recovery
```bash
# Complete restart
docker-compose down
docker-compose up -d

# Force restart with cleanup
docker-compose down
docker system prune -f
docker-compose up -d

# Emergency tunnel restart
sudo systemctl restart cloudflared
./fix-tunnel.sh
```

### Data Recovery
```bash
# Emergency backup before recovery
docker exec nightscout_mongo mongodump --out /data/db/emergency_backup

# Restore from latest backup
./restore.sh latest

# Verify data integrity
docker exec nightscout_mongo mongosh --eval "db.stats()"
```

### Complete Reset
```bash
# Complete cleanup
./cleanup.sh

# Fresh setup
./setup.sh --domain your.domain.com --setup-tunnel
docker-compose up -d
```

## Useful Aliases

Add these to your `~/.bashrc` or `~/.zshrc`:

```bash
# Nightscout aliases
alias ns-status='docker-compose ps'
alias ns-logs='docker-compose logs -f'
alias ns-restart='docker-compose restart'
alias ns-up='docker-compose up -d'
alias ns-down='docker-compose down'
alias ns-validate='./validate.sh'
alias ns-diagnose='./diagnose.sh'
alias ns-backup='docker exec nightscout_mongo mongodump --out /data/db/backup_$(date +%Y%m%d_%H%M%S)'
alias ns-tunnel-status='./tunnel-status.sh'
alias ns-debug='./debug-tunnel.sh'
```

## Common Error Solutions

### "Port already in use"
```bash
# Find what's using the port
lsof -i :8080
sudo netstat -tlnp | grep :8080

# Kill the process or change port in docker-compose.yml
```

### "MongoDB connection failed"
```bash
# Check MongoDB container
docker-compose logs mongo

# Restart MongoDB
docker-compose restart mongo

# Check network connectivity
docker exec nightscout ping mongo
```

### "Cloudflare tunnel not working"
```bash
# Debug tunnel
./debug-tunnel.sh

# Recreate tunnel
./cleanup-tunnels.sh
./setup-cloudflare.sh --domain your.domain.com

# Check DNS propagation
nslookup your.domain.com
```

### "Container won't start"
```bash
# Check logs
docker-compose logs

# Validate configuration
./validate.sh

# Check resource limits
docker stats

# Restart Docker daemon
sudo systemctl restart docker
```

---

**Remember**: Always test commands in a development environment before running in production! 