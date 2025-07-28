#!/bin/bash

# Database Validation Script
# This script checks for common database naming and connection issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo "🔍 Database Validation Script"
echo "============================"
echo ""

# Check if .env file exists
if [ ! -f ".env" ]; then
    print_error ".env file not found"
    exit 1
fi

# Get current connection string
CONNECTION_STRING=$(grep "MONGO_CONNECTION=" .env | cut -d'=' -f2-)
if [ -z "$CONNECTION_STRING" ]; then
    print_error "MONGO_CONNECTION not found in .env file"
    exit 1
fi

print_info "Current connection string: $CONNECTION_STRING"

# Extract database name from connection string
DB_NAME=$(echo "$CONNECTION_STRING" | sed -n 's/.*\/\([^?]*\).*/\1/p')
if [ -z "$DB_NAME" ]; then
    print_error "Could not extract database name from connection string"
    exit 1
fi

print_info "Database name: $DB_NAME"

# Check if containers are running
if ! docker-compose ps | grep -q "nightscout_mongo.*Up"; then
    print_error "MongoDB container is not running"
    print_info "Start containers with: docker-compose up -d"
    exit 1
fi

print_status "MongoDB container is running"

# Get MongoDB password
MONGO_PASSWORD=$(grep "MONGO_INITDB_ROOT_PASSWORD=" .env | cut -d'=' -f2)
if [ -z "$MONGO_PASSWORD" ]; then
    print_error "MongoDB password not found in .env file"
    exit 1
fi

# Test database connectivity
print_info "Testing database connectivity..."
if docker-compose exec -T mongo mongo --username root --password "$MONGO_PASSWORD" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
    print_status "Database connectivity verified"
else
    print_error "Database connectivity test failed"
    exit 1
fi

# Check if the target database exists
print_info "Checking if database '$DB_NAME' exists..."
DB_STATS=$(docker-compose exec -T mongo mongo --username root --password "$MONGO_PASSWORD" --authenticationDatabase admin --quiet --eval "db.stats()" "$DB_NAME" 2>/dev/null)

if [ $? -eq 0 ]; then
    print_status "Database '$DB_NAME' exists"
    
    # Check if database has data
    OBJECTS_COUNT=$(echo "$DB_STATS" | grep -o '"objects" : [0-9]*' | grep -o '[0-9]*')
    if [ "$OBJECTS_COUNT" -gt 0 ]; then
        print_status "Database contains $OBJECTS_COUNT objects"
    else
        print_warning "Database exists but contains no data"
    fi
    
    # List collections
    COLLECTIONS=$(docker-compose exec -T mongo mongo --username root --password "$MONGO_PASSWORD" --authenticationDatabase admin --quiet --eval "db.getCollectionNames()" "$DB_NAME" 2>/dev/null)
    if [ -n "$COLLECTIONS" ]; then
        print_info "Collections found:"
        echo "$COLLECTIONS" | tr ',' '\n' | sed 's/\[//;s/\]//' | grep -v '^$' | while read -r collection; do
            if [ -n "$collection" ]; then
                echo "  - $collection"
            fi
        done
    else
        print_warning "No collections found in database"
    fi
else
    print_error "Database '$DB_NAME' does not exist"
    print_info "Available databases:"
    docker-compose exec -T mongo mongo --username root --password "$MONGO_PASSWORD" --authenticationDatabase admin --quiet --eval "show dbs" 2>/dev/null | grep -v "admin\|local" || true
fi

# Check Nightscout connection
print_info "Checking Nightscout connection..."
if curl -s -f "http://localhost:8080/api/v1/status" >/dev/null 2>&1; then
    print_status "Nightscout is accessible"
    
    # Check if Nightscout can see data
    ENTRIES_RESPONSE=$(curl -s "http://localhost:8080/api/v1/entries.json?count=1" 2>/dev/null)
    if echo "$ENTRIES_RESPONSE" | grep -q "\["; then
        ENTRIES_COUNT=$(echo "$ENTRIES_RESPONSE" | jq 'length' 2>/dev/null || echo "0")
        if [ "$ENTRIES_COUNT" -gt 0 ]; then
            print_status "Nightscout can see $ENTRIES_COUNT entries"
        else
            print_warning "Nightscout is running but shows no entries"
        fi
    else
        print_warning "Nightscout API response is not valid JSON"
    fi
else
    print_warning "Nightscout is not accessible (may be starting up)"
fi

echo ""
echo "📋 Summary:"
echo "==========="
echo "Connection string: $CONNECTION_STRING"
echo "Database name: $DB_NAME"
echo "MongoDB container: $(docker-compose ps | grep nightscout_mongo | awk '{print $6}')"
echo "Nightscout container: $(docker-compose ps | grep nightscout | awk '{print $6}')"

echo ""
print_info "If you see database naming issues:"
echo "1. Check that the database name in the connection string matches your imported data"
echo "2. Verify the data was imported to the correct database"
echo "3. Update the connection string if needed:"
echo "   sed -i.bak 's|MONGO_CONNECTION=.*|MONGO_CONNECTION=mongodb://root:PASSWORD@mongo:27017/CORRECT_DB_NAME?authSource=admin|' .env"
echo "4. Restart Nightscout: docker-compose restart nightscout" 