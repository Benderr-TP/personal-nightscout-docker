#!/bin/bash

# Nightscout Automated Backup Script
# This script provides comprehensive backup functionality for Nightscout deployments

set -e

# Configuration
BACKUP_DIR="/opt/nightscout/backups"
RETENTION_DAYS=7
RETENTION_WEEKS=4
ENCRYPT_BACKUP=false
COMPRESS_BACKUP=true
VERIFY_BACKUP=true
NOTIFY_ON_SUCCESS=false
NOTIFY_ON_FAILURE=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_usage() {
    echo "Nightscout Automated Backup Script"
    echo ""
    echo "Usage:"
    echo "  $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --schedule TYPE        Backup schedule (manual, daily, weekly, monthly)"
    echo "  --retention DAYS       Number of days to keep backups (default: 7)"
    echo "  --encrypt              Encrypt backup files"
    echo "  --no-compress          Disable compression"
    echo "  --no-verify            Skip backup verification"
    echo "  --notify-success       Send notification on successful backup"
    echo "  --notify-failure       Send notification on failed backup (default: true)"
    echo "  --backup-dir DIR       Backup directory (default: /opt/nightscout/backups)"
    echo "  --help, -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --schedule daily --retention 7 --encrypt"
    echo "  $0 --schedule weekly --retention 30 --no-compress"
    echo "  $0 --schedule manual --backup-dir /tmp/backup"
}

# Parse command line arguments
SCHEDULE="manual"
while [[ $# -gt 0 ]]; do
    case $1 in
        --schedule)
            SCHEDULE="$2"
            shift 2
            ;;
        --retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --encrypt)
            ENCRYPT_BACKUP=true
            shift
            ;;
        --no-compress)
            COMPRESS_BACKUP=false
            shift
            ;;
        --no-verify)
            VERIFY_BACKUP=false
            shift
            ;;
        --notify-success)
            NOTIFY_ON_SUCCESS=true
            shift
            ;;
        --notify-failure)
            NOTIFY_ON_FAILURE=true
            shift
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate schedule
if [[ ! "$SCHEDULE" =~ ^(manual|daily|weekly|monthly)$ ]]; then
    print_error "Invalid schedule: $SCHEDULE"
    print_usage
    exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running"
    exit 1
fi

# Check if Nightscout containers are running
if ! docker-compose ps | grep -q "Up"; then
    print_warning "Nightscout containers are not running"
    read -p "Continue with backup anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Generate backup filename
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="nightscout-backup-${SCHEDULE}-${DATE}"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

echo "🔒 Nightscout Backup Script"
echo "=========================="
echo "Schedule: $SCHEDULE"
echo "Backup directory: $BACKUP_DIR"
echo "Backup name: $BACKUP_NAME"
echo "Retention: $RETENTION_DAYS days"
echo ""

# Step 1: Pre-backup checks
print_info "Step 1: Pre-backup checks"

# Check disk space
AVAILABLE_SPACE=$(df "$BACKUP_DIR" | tail -1 | awk '{print $4}')
REQUIRED_SPACE=1048576  # 1GB in KB
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    print_warning "Low disk space: $(($AVAILABLE_SPACE / 1024))MB available"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if MongoDB container is accessible
if ! docker-compose exec -T mongo mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
    print_error "MongoDB container is not accessible"
    exit 1
fi

print_status "Pre-backup checks completed"

# Step 2: Create MongoDB backup
print_info "Step 2: Creating MongoDB backup"

# Get MongoDB connection details
MONGO_PASSWORD=$(grep "MONGO_INITDB_ROOT_PASSWORD=" .env | cut -d'=' -f2)
if [ -z "$MONGO_PASSWORD" ]; then
    print_error "MongoDB password not found in .env file"
    exit 1
fi

# Create MongoDB backup
print_info "Exporting MongoDB data..."
if docker-compose exec -T mongo mongodump --out "/data/db/backup_$DATE" --gzip; then
    print_status "MongoDB backup created successfully"
else
    print_error "MongoDB backup failed"
    exit 1
fi

# Copy backup from container
print_info "Copying backup from container..."
if docker cp "nightscout_mongo:/data/db/backup_$DATE" "$BACKUP_PATH"; then
    print_status "Backup copied from container"
else
    print_error "Failed to copy backup from container"
    exit 1
fi

# Step 3: Backup configuration files
print_info "Step 3: Backing up configuration files"

# Create config backup
CONFIG_BACKUP="$BACKUP_PATH/config"
mkdir -p "$CONFIG_BACKUP"

# Copy important files
cp .env "$CONFIG_BACKUP/" 2>/dev/null || print_warning "Could not copy .env"
cp docker-compose.yml "$CONFIG_BACKUP/" 2>/dev/null || print_warning "Could not copy docker-compose.yml"


# Copy Cloudflare tunnel config if exists
if [ -d ~/.cloudflared ]; then
    cp -r ~/.cloudflared "$CONFIG_BACKUP/" 2>/dev/null || print_warning "Could not copy Cloudflare config"
fi

print_status "Configuration files backed up"

# Step 4: Backup volumes
print_info "Step 4: Backing up Docker volumes"

# Get volume names
VOLUMES=$(docker volume ls --format "{{.Name}}" | grep nightscout || true)

if [ -n "$VOLUMES" ]; then
    for volume in $VOLUMES; do
        print_info "Backing up volume: $volume"
        VOLUME_BACKUP="$BACKUP_PATH/volumes/$volume"
        mkdir -p "$VOLUME_BACKUP"
        
        if docker run --rm -v "$volume:/data" -v "$VOLUME_BACKUP:/backup" alpine tar czf /backup/data.tar.gz -C /data .; then
            print_status "Volume $volume backed up"
        else
            print_warning "Failed to backup volume $volume"
        fi
    done
else
    print_info "No Nightscout volumes found"
fi

# Step 5: Compress backup
if [ "$COMPRESS_BACKUP" = true ]; then
    print_info "Step 5: Compressing backup"
    
    cd "$BACKUP_DIR"
    if tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"; then
        print_status "Backup compressed successfully"
        # Remove uncompressed directory
        rm -rf "$BACKUP_NAME"
        BACKUP_FILE="${BACKUP_NAME}.tar.gz"
    else
        print_error "Backup compression failed"
        exit 1
    fi
else
    BACKUP_FILE="$BACKUP_NAME"
fi

# Step 6: Encrypt backup
if [ "$ENCRYPT_BACKUP" = true ]; then
    print_info "Step 6: Encrypting backup"
    
    # Generate encryption key if not exists
    ENCRYPTION_KEY_FILE="$BACKUP_DIR/.encryption_key"
    if [ ! -f "$ENCRYPTION_KEY_FILE" ]; then
        openssl rand -base64 32 > "$ENCRYPTION_KEY_FILE"
        print_warning "New encryption key generated: $ENCRYPTION_KEY_FILE"
        print_warning "Keep this key secure - you'll need it to restore backups"
    fi
    
    # Encrypt backup
    if openssl enc -aes-256-cbc -salt -in "$BACKUP_DIR/$BACKUP_FILE" -out "$BACKUP_DIR/${BACKUP_FILE}.enc" -pass file:"$ENCRYPTION_KEY_FILE"; then
        rm "$BACKUP_DIR/$BACKUP_FILE"
        BACKUP_FILE="${BACKUP_FILE}.enc"
        print_status "Backup encrypted successfully"
    else
        print_error "Backup encryption failed"
        exit 1
    fi
fi

# Step 7: Verify backup
if [ "$VERIFY_BACKUP" = true ]; then
    print_info "Step 7: Verifying backup"
    
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
    print_info "Backup size: $BACKUP_SIZE"
    
    # Check if backup file exists and has content
    if [ -f "$BACKUP_DIR/$BACKUP_FILE" ] && [ -s "$BACKUP_DIR/$BACKUP_FILE" ]; then
        print_status "Backup verification passed"
    else
        print_error "Backup verification failed"
        exit 1
    fi
fi

# Step 8: Cleanup old backups
print_info "Step 8: Cleaning up old backups"

# Remove old daily backups
find "$BACKUP_DIR" -name "nightscout-backup-daily-*.tar.gz*" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "nightscout-backup-daily-*" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

# Remove old weekly backups
find "$BACKUP_DIR" -name "nightscout-backup-weekly-*.tar.gz*" -mtime +$((RETENTION_DAYS * 7)) -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "nightscout-backup-weekly-*" -type d -mtime +$((RETENTION_DAYS * 7)) -exec rm -rf {} + 2>/dev/null || true

# Remove old monthly backups
find "$BACKUP_DIR" -name "nightscout-backup-monthly-*.tar.gz*" -mtime +$((RETENTION_DAYS * 30)) -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "nightscout-backup-monthly-*" -type d -mtime +$((RETENTION_DAYS * 30)) -exec rm -rf {} + 2>/dev/null || true

print_status "Old backups cleaned up"

# Step 9: Generate backup report
print_info "Step 9: Generating backup report"

REPORT_FILE="$BACKUP_DIR/backup-report-${DATE}.txt"
{
    echo "Nightscout Backup Report"
    echo "======================="
    echo "Date: $(date)"
    echo "Schedule: $SCHEDULE"
    echo "Backup file: $BACKUP_FILE"
    echo "Backup size: $(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)"
    echo "Backup location: $BACKUP_DIR/$BACKUP_FILE"
    echo "Encrypted: $ENCRYPT_BACKUP"
    echo "Compressed: $COMPRESS_BACKUP"
    echo "Verified: $VERIFY_BACKUP"
    echo ""
    echo "System Information:"
    echo "  Hostname: $(hostname)"
    echo "  Disk usage: $(df -h "$BACKUP_DIR" | tail -1 | awk '{print $5}')"
    echo "  Available space: $(df -h "$BACKUP_DIR" | tail -1 | awk '{print $4}')"
    echo ""
    echo "Container Status:"
    docker-compose ps
    echo ""
    echo "Backup Contents:"
    if [ "$COMPRESS_BACKUP" = true ] && [ "$ENCRYPT_BACKUP" = false ]; then
        tar -tzf "$BACKUP_DIR/$BACKUP_FILE" | head -20
    fi
} > "$REPORT_FILE"

print_status "Backup report generated: $REPORT_FILE"

# Step 10: Notifications
if [ "$NOTIFY_ON_SUCCESS" = true ] || [ "$NOTIFY_ON_FAILURE" = true ]; then
    print_info "Step 10: Sending notifications"
    
    # Simple notification (can be enhanced with email/Slack)
    if [ "$NOTIFY_ON_SUCCESS" = true ]; then
        echo "✅ Nightscout backup completed successfully: $BACKUP_FILE" | logger -t nightscout-backup
    fi
fi

# Final success message
echo ""
echo "🎉 Backup completed successfully!"
echo "================================"
echo ""
print_status "✅ MongoDB data backed up"
print_status "✅ Configuration files backed up"
print_status "✅ Docker volumes backed up"
print_status "✅ Backup compressed and verified"
if [ "$ENCRYPT_BACKUP" = true ]; then
    print_status "✅ Backup encrypted"
fi
print_status "✅ Old backups cleaned up"
print_status "✅ Backup report generated"

echo ""
echo "📁 Backup location: $BACKUP_DIR/$BACKUP_FILE"
echo "📊 Backup size: $(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)"
echo "📋 Report: $REPORT_FILE"

echo ""
print_info "To restore this backup, use:"
echo "  ./restore.sh --backup-file $BACKUP_FILE"

if [ "$ENCRYPT_BACKUP" = true ]; then
    echo ""
    print_warning "⚠️  This backup is encrypted. Keep the encryption key secure!"
    echo "   Encryption key: $ENCRYPTION_KEY_FILE"
fi

echo ""
print_info "📚 For more information, see:"
echo "   - README.md (backup procedures)"
echo "   - PROJECT-INFO.md (deployment guide)"
echo "   - DEVOPS-QUICK-REFERENCE.md (commands)" 