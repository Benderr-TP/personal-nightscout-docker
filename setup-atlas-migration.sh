#!/bin/bash

# Nightscout Atlas Migration Setup Script
# This script handles the complete migration from MongoDB Atlas to self-hosted setup
# 
# Usage:
#   ./setup-atlas-migration.sh                           # Interactive mode
#   ./setup-atlas-migration.sh --domain host.domain.org  # With domain pre-configured

set -e

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

print_step() {
    echo -e "${BLUE}🔄 Step $1:${NC} $2"
}

# Parse command line arguments
DOMAIN=""
INTERACTIVE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            INTERACTIVE=false
            shift 2
            ;;
        --help|-h)
            echo "Nightscout Atlas Migration Setup Script"
            echo ""
            echo "This script handles complete migration from MongoDB Atlas to self-hosted Nightscout:"
            echo "1. Prompts for Atlas connection details"
            echo "2. Exports data from Atlas"
            echo "3. Sets up Nightscout with local MongoDB"
            echo "4. Imports the data"
            echo "5. Optionally configures Cloudflare tunnel"
            echo ""
            echo "Usage:"
            echo "  ./setup-atlas-migration.sh                           # Interactive mode"
            echo "  ./setup-atlas-migration.sh --domain host.domain.org  # With domain"
            echo ""
            echo "Options:"
            echo "  --domain DOMAIN        Set domain for Cloudflare tunnel"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Prerequisites:"
            echo "  - MongoDB Database Tools (mongodump/mongorestore)"
            echo "  - Docker and Docker Compose"
            echo "  - Atlas connection string with read access"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🚀 Nightscout Atlas Migration Setup"
echo "===================================="
echo ""
echo "This script will:"
echo "1. Export your data from MongoDB Atlas"
echo "2. Set up a new Nightscout instance with local MongoDB"
echo "3. Import your Atlas data"
echo "4. Configure your new Nightscout deployment"
if [ -n "$DOMAIN" ]; then
    echo "5. Set up Cloudflare tunnel for domain: $DOMAIN"
fi
echo ""

# Check for required commands
REQUIRED_COMMANDS=("mongodump" "mongorestore" "docker" "docker-compose" "openssl" "curl")
MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [ ${#MISSING_COMMANDS[@]} -ne 0 ]; then
    print_error "The following required commands are missing:"
    for cmd in "${MISSING_COMMANDS[@]}"; do
        echo "  - $cmd"
    done
    echo
    print_info "Install missing tools:"
    echo "  # MongoDB Database Tools"
    echo "  curl -O https://fastdl.mongodb.org/tools/db/mongodb-database-tools-ubuntu2004-x86_64-100.9.4.deb"
    echo "  sudo dpkg -i mongodb-database-tools-*.deb"
    echo ""
    echo "  # Docker"
    echo "  sudo apt update && sudo apt install -y docker.io docker-compose openssl curl"
    exit 1
fi

print_status "All required tools are available"
echo ""

# Step 1: Collect Atlas connection information
print_step "1" "Collecting Atlas connection information"

if [ "$INTERACTIVE" = true ]; then
    echo ""
    print_info "Enter your MongoDB Atlas connection details"
    echo "You can find this in your Atlas dashboard under 'Connect' -> 'Connect your application'"
    echo ""
    
    read -p "Atlas connection string (mongodb+srv://...): " ATLAS_CONNECTION_STRING
    
    # Validate connection string format
    if [[ ! "$ATLAS_CONNECTION_STRING" =~ mongodb\+srv:// ]]; then
        print_error "Invalid connection string format. Expected mongodb+srv://..."
        print_info "Example: mongodb+srv://username:password@cluster0.xxxxx.mongodb.net/"
        exit 1
    fi
    
    # Check if password is included in connection string
    if [[ ! "$ATLAS_CONNECTION_STRING" =~ :[^@]*@ ]]; then
        print_warning "Connection string appears to be missing password"
        read -s -p "Enter Atlas password: " ATLAS_PASSWORD
        echo ""
        
        # Insert password into connection string
        ATLAS_CONNECTION_STRING=$(echo "$ATLAS_CONNECTION_STRING" | sed "s|://\([^@]*\)@|://\1:$ATLAS_PASSWORD@|")
    fi
    
    read -p "Database name (default: nightscout): " DATABASE_NAME
    DATABASE_NAME=${DATABASE_NAME:-nightscout}
    
    echo ""
    read -p "Use oplog for consistent export? (recommended) (Y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        USE_OPLOG=true
    else
        USE_OPLOG=false
    fi
else
    print_error "Interactive mode required for Atlas connection details"
    print_info "Run without --domain flag for interactive Atlas setup"
    exit 1
fi

print_status "Atlas connection information collected"

# Step 2: Export from Atlas
print_step "2" "Exporting data from MongoDB Atlas"

EXPORT_DIR="./nightscout-export-$(date +%Y%m%d-%H%M%S)"
EXPORT_CMD="./export-atlas-db.sh -c \"$ATLAS_CONNECTION_STRING\" -d \"$DATABASE_NAME\" -o \"$EXPORT_DIR\""

if [ "$USE_OPLOG" = true ]; then
    EXPORT_CMD="$EXPORT_CMD --oplog"
fi

print_info "Starting Atlas export..."
print_info "Export directory: $EXPORT_DIR"

if eval $EXPORT_CMD; then
    print_status "Atlas export completed successfully"
    
    # Verify export
    if [ -d "$EXPORT_DIR/$DATABASE_NAME" ]; then
        COLLECTION_COUNT=$(find "$EXPORT_DIR/$DATABASE_NAME" -name "*.bson" | wc -l)
        EXPORT_SIZE=$(du -sh "$EXPORT_DIR" | cut -f1)
        print_info "Exported $COLLECTION_COUNT collections, total size: $EXPORT_SIZE"
    fi
else
    print_error "Atlas export failed!"
    print_info "Please check your connection string and Atlas access permissions"
    exit 1
fi

# Step 3: Set up new Nightscout instance
print_step "3" "Setting up new Nightscout instance"

print_info "Running Nightscout setup script..."

# Run setup script
if [ -n "$DOMAIN" ]; then
    SETUP_CMD="./setup.sh --domain \"$DOMAIN\""
else
    SETUP_CMD="./setup.sh"
fi

if eval $SETUP_CMD; then
    print_status "Nightscout setup completed"
else
    print_error "Nightscout setup failed!"
    exit 1
fi

# Step 4: Start MongoDB for import
print_step "4" "Starting MongoDB container for data import"

print_info "Starting MongoDB container..."
if docker-compose up -d mongo; then
    print_status "MongoDB container started"
else
    print_error "Failed to start MongoDB container"
    exit 1
fi

# Wait for MongoDB to be ready
print_info "Waiting for MongoDB to be ready..."
MONGO_READY=false

for i in {1..30}; do
    sleep 2
    print_info "Checking MongoDB... (attempt $i/30)"
    
    if docker-compose exec -T mongo mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        print_status "MongoDB is ready"
        MONGO_READY=true
        break
    elif [ $i -eq 30 ]; then
        print_error "MongoDB failed to start after 60 seconds"
        print_info "Check logs: docker-compose logs mongo"
        exit 1
    fi
done

# Step 5: Import data to new MongoDB
print_step "5" "Importing Atlas data to new MongoDB instance"

# Get MongoDB connection details from .env
MONGO_PASSWORD=$(grep "MONGO_INITDB_ROOT_PASSWORD=" .env | cut -d'=' -f2)
if [ -z "$MONGO_PASSWORD" ]; then
    print_error "MongoDB password not found in .env file"
    exit 1
fi

print_info "Starting MongoDB container for import..."

# Start MongoDB container without port mapping
if docker-compose up -d mongo; then
    print_status "MongoDB container started"
else
    print_error "Failed to start MongoDB container"
    exit 1
fi

# Wait for MongoDB to be ready
print_info "Waiting for MongoDB to be ready..."
MONGO_READY=false

for i in {1..30}; do
    sleep 2
    print_info "Checking MongoDB... (attempt $i/30)"
    
    if docker-compose exec -T mongo mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        print_status "MongoDB is ready"
        MONGO_READY=true
        break
    elif [ $i -eq 30 ]; then
        print_error "MongoDB failed to start after 60 seconds"
        print_info "Check logs: docker-compose logs mongo"
        exit 1
    fi
done

# Import data directly to the container
print_info "Starting data import to MongoDB container..."

# Check if export directory exists and contains data
if [ ! -d "$EXPORT_DIR/$DATABASE_NAME" ]; then
    print_error "Export directory not found: $EXPORT_DIR/$DATABASE_NAME"
    exit 1
fi

# Copy export data to container
print_info "Copying export data to MongoDB container..."
if docker cp "$EXPORT_DIR/$DATABASE_NAME" "nightscout_mongo:/tmp/import_data"; then
    print_status "Export data copied to container"
else
    print_error "Failed to copy export data to container"
    exit 1
fi

# Import data using mongorestore inside the container
print_info "Importing data using mongorestore..."
IMPORT_CMD="mongorestore --db $DATABASE_NAME --drop /tmp/import_data"

if [ "$USE_OPLOG" = true ]; then
    IMPORT_CMD="$IMPORT_CMD --oplogReplay"
fi

if docker-compose exec -T mongo $IMPORT_CMD; then
    print_status "Data import completed successfully"
else
    print_error "Data import failed!"
    print_info "Check MongoDB logs: docker-compose logs mongo"
    exit 1
fi

# Clean up import data from container
docker-compose exec -T mongo rm -rf /tmp/import_data

print_status "MongoDB data import completed"

# Step 6: Start full Nightscout application
print_step "6" "Starting complete Nightscout application"

print_info "Starting all services..."
if docker-compose up -d; then
    print_status "Nightscout application started"
else
    print_error "Failed to start Nightscout application"
    exit 1
fi

# Wait for Nightscout to be ready
print_info "Waiting for Nightscout to be ready..."
NIGHTSCOUT_READY=false

for i in {1..30}; do
    sleep 5
    print_info "Checking Nightscout health... (attempt $i/30)"
    
    if curl -s -f "http://localhost:8080/api/v1/status" > /dev/null 2>&1; then
        print_status "Nightscout is ready and accessible!"
        NIGHTSCOUT_READY=true
        break
    elif [ $i -eq 30 ]; then
        print_error "Nightscout failed to become ready after 2.5 minutes"
        print_info "Check logs: docker-compose logs nightscout"
        exit 1
    fi
done

# Step 7: Optional Cloudflare tunnel setup
if [ -n "$DOMAIN" ] && [ "$NIGHTSCOUT_READY" = true ]; then
    print_step "7" "Setting up Cloudflare tunnel"
    
    HOSTNAME=$(echo "$DOMAIN" | cut -d'.' -f1)
    TUNNEL_NAME="${HOSTNAME}-tunnel"
    
    print_info "Setting up tunnel for domain: $DOMAIN"
    
    if ./setup-cloudflare.sh --domain "$DOMAIN" --tunnel-name "$TUNNEL_NAME" --non-interactive; then
        print_status "Cloudflare tunnel setup completed"
        TUNNEL_CONFIGURED=true
    else
        print_warning "Cloudflare tunnel setup failed, but Nightscout is running locally"
        TUNNEL_CONFIGURED=false
    fi
fi

# Step 8: Verification and cleanup
print_step "8" "Verification and cleanup"

print_info "Verifying data migration..."

# Test database connectivity
if docker-compose exec -T mongo mongosh nightscout --eval "db.stats()" >/dev/null 2>&1; then
    # Get collection counts
    ENTRIES_COUNT=$(docker-compose exec -T mongo mongosh nightscout --quiet --eval "db.entries.countDocuments()")
    TREATMENTS_COUNT=$(docker-compose exec -T mongo mongosh nightscout --quiet --eval "db.treatments.countDocuments()")
    
    print_status "Database verification:"
    print_info "  - Entries: $ENTRIES_COUNT"
    print_info "  - Treatments: $TREATMENTS_COUNT"
else
    print_warning "Could not verify database contents"
fi

# Cleanup export directory
if [ "$INTERACTIVE" = true ]; then
    echo ""
    read -p "Delete export files to save disk space? (Y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        rm -rf "$EXPORT_DIR"
        print_status "Export files cleaned up"
    else
        print_info "Export files kept at: $EXPORT_DIR"
    fi
else
    print_info "Export files kept at: $EXPORT_DIR"
fi

# Final success message
echo ""
echo "🎉 Migration completed successfully!"
echo "=================================="
echo ""
print_status "✅ Atlas data exported and imported"
print_status "✅ Nightscout configured and running"
print_status "✅ Local MongoDB instance operational"

echo ""
echo "🌐 Access your Nightscout:"
echo "   - Local: http://localhost:8080"

if [ -n "$DOMAIN" ] && [ "$TUNNEL_CONFIGURED" = true ]; then
    echo "   - External: https://$DOMAIN"
fi

echo ""
echo "🔧 Configuration details:"
echo "   - Database: $DATABASE_NAME"
echo "   - Collections migrated from Atlas"
echo "   - Local MongoDB with authentication"

if [ -n "$DOMAIN" ]; then
    echo "   - Domain: $DOMAIN"
fi

echo ""
echo "📋 Next steps:"
echo "1. Test your Nightscout instance thoroughly"
echo "2. Verify all historical data is visible"
echo "3. Test uploading new data"
echo "4. Update your devices/uploaders to new instance"
echo "5. Consider backing up your .env file securely"

echo ""
print_warning "⚠️  Important security notes:"
echo "- Your .env file contains sensitive credentials"
echo "- Keep Atlas credentials secure until migration is verified"
echo "- Test all functionality before decommissioning Atlas"
echo "- Set up regular backups of your new MongoDB instance"

echo ""
print_info "📚 For troubleshooting, see MIGRATION.md"