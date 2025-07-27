#!/bin/bash

# Nightscout Configuration Validation Script
# This script validates the environment and Docker setup

set -e

echo "🔍 Nightscout Configuration Validation"
echo "====================================="

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

# Check if .env file exists
if [ ! -f ".env" ]; then
    print_error ".env file not found!"
    echo "Run ./setup.sh to create and configure your environment file."
    exit 1
fi

print_status ".env file found"

# Check for required environment variables
print_info "Checking required environment variables..."

REQUIRED_VARS=("API_SECRET" "MONGO_INITDB_ROOT_PASSWORD" "MONGO_CONNECTION" "TZ" "DISPLAY_UNITS")

for var in "${REQUIRED_VARS[@]}"; do
    if grep -q "^${var}=" .env; then
        value=$(grep "^${var}=" .env | cut -d'=' -f2)
        if [[ "$value" == *"change_this"* ]]; then
            print_error "$var still has default value"
        else
            print_status "$var is configured"
        fi
    else
        print_error "$var is missing"
    fi
done

# Check API_SECRET length
API_SECRET=$(grep "^API_SECRET=" .env | cut -d'=' -f2)
if [ ${#API_SECRET} -lt 12 ]; then
    print_error "API_SECRET is too short (minimum 12 characters, current: ${#API_SECRET})"
else
    print_status "API_SECRET length is adequate (${#API_SECRET} characters)"
fi

# Check MongoDB password
MONGO_PASSWORD=$(grep "^MONGO_INITDB_ROOT_PASSWORD=" .env | cut -d'=' -f2)
if [ ${#MONGO_PASSWORD} -lt 8 ]; then
    print_error "MONGO_INITDB_ROOT_PASSWORD is too short (minimum 8 characters, current: ${#MONGO_PASSWORD})"
else
    print_status "MONGO_INITDB_ROOT_PASSWORD length is adequate (${#MONGO_PASSWORD} characters)"
fi

# Check Docker installation
print_info "Checking Docker installation..."

if command -v docker &> /dev/null; then
    print_status "Docker is installed"
    
    # Check Docker daemon
    if docker info &> /dev/null; then
        print_status "Docker daemon is running"
    else
        print_error "Docker daemon is not running"
        echo "Start Docker and try again."
        exit 1
    fi
else
    print_error "Docker is not installed"
    echo "Install Docker and try again."
    exit 1
fi

# Check Docker Compose
if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
    print_status "Docker Compose is available"
else
    print_error "Docker Compose is not available"
    echo "Install Docker Compose and try again."
    exit 1
fi

# Check if containers are running
print_info "Checking container status..."

if docker ps --format "table {{.Names}}" | grep -q "nightscout"; then
    print_status "Nightscout container is running"
else
    print_warning "Nightscout container is not running"
    echo "Start containers with: docker-compose up -d"
fi

if docker ps --format "table {{.Names}}" | grep -q "nightscout_mongo"; then
    print_status "MongoDB container is running"
else
    print_warning "MongoDB container is not running"
    echo "Start containers with: docker-compose up -d"
fi

# Check port availability
print_info "Checking port availability..."

if netstat -an 2>/dev/null | grep -q ":1337 "; then
    print_warning "Port 1337 is already in use"
    echo "Make sure no other service is using port 1337"
else
    print_status "Port 1337 is available"
fi

# Check disk space
print_info "Checking disk space..."

DISK_USAGE=$(df . | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    print_error "Disk usage is high (${DISK_USAGE}%)"
elif [ "$DISK_USAGE" -gt 80 ]; then
    print_warning "Disk usage is moderate (${DISK_USAGE}%)"
else
    print_status "Disk usage is acceptable (${DISK_USAGE}%)"
fi

# Check Docker images
print_info "Checking Docker images..."

if docker images | grep -q "nightscout/cgm-remote-monitor"; then
    print_status "Nightscout Docker image is available"
else
    print_warning "Nightscout Docker image not found"
    echo "Images will be pulled when starting containers"
fi

if docker images | grep -q "mongo:4.4"; then
    print_status "MongoDB Docker image is available"
else
    print_warning "MongoDB Docker image not found"
    echo "Images will be pulled when starting containers"
fi

# Summary
echo
echo "📊 Validation Summary"
echo "===================="

if [ $? -eq 0 ]; then
    print_status "Configuration validation completed"
    echo
    echo "🎉 Your Nightscout setup appears to be ready!"
    echo
    echo "Next steps:"
    echo "1. Start containers: docker-compose up -d"
    echo "2. Check logs: docker-compose logs -f"
    echo "3. Access Nightscout: http://localhost:1337"
    echo
    echo "For Proxmox deployment:"
    echo "1. Start containers: docker-compose -f docker-compose.proxmox.yml up -d"
    echo "2. Check logs: docker-compose -f docker-compose.proxmox.yml logs -f"
else
    print_error "Configuration validation failed"
    echo "Please fix the issues above and run validation again."
    exit 1
fi 