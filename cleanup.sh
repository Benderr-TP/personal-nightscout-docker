#!/bin/bash

# Cleanup Script for Nightscout Docker Setup
# This script removes all containers, volumes, and configurations

set -e

echo "🧹 Nightscout Cleanup Script"
echo "============================"

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

# Confirm cleanup
print_warning "This will remove ALL Nightscout containers, volumes, and data!"
print_warning "This action cannot be undone!"
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 1
fi

# Stop and remove containers
print_info "Stopping and removing containers..."
if docker ps -a --format "table {{.Names}}" | grep -q "nightscout"; then
    docker-compose down -v
    print_status "Containers stopped and removed"
else
    print_info "No Nightscout containers found"
fi

# Remove volumes
print_info "Removing volumes..."
if docker volume ls --format "table {{.Name}}" | grep -q "nightscout"; then
    docker volume rm $(docker volume ls -q | grep nightscout) 2>/dev/null || true
    print_status "Volumes removed"
else
    print_info "No Nightscout volumes found"
fi

# Remove networks
print_info "Removing networks..."
if docker network ls --format "table {{.Name}}" | grep -q "nightscout"; then
    docker network rm $(docker network ls -q | grep nightscout) 2>/dev/null || true
    print_status "Networks removed"
else
    print_info "No Nightscout networks found"
fi

# Remove images
print_info "Removing images..."
if docker images --format "table {{.Repository}}" | grep -q "nightscout"; then
    docker rmi $(docker images -q | grep nightscout) 2>/dev/null || true
    print_status "Images removed"
else
    print_info "No Nightscout images found"
fi

# Clean up any dangling resources
print_info "Cleaning up dangling resources..."
docker system prune -f
print_status "Dangling resources cleaned"

# Remove configuration files
print_info "Removing configuration files..."
rm -f .env
rm -f docker-compose.cloudflare.yml
print_status "Configuration files removed"

# Remove management scripts
print_info "Removing management scripts..."
rm -f tunnel-status.sh tunnel-logs.sh tunnel-restart.sh
print_status "Management scripts removed"

# Remove Cloudflare tunnel configuration
print_info "Removing Cloudflare tunnel configuration..."
if [ -d "$HOME/.cloudflared" ]; then
    print_warning "Cloudflare tunnel configuration found at $HOME/.cloudflared"
    read -p "Do you want to remove Cloudflare tunnel configuration? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$HOME/.cloudflared"
        print_status "Cloudflare tunnel configuration removed"
    else
        print_info "Cloudflare tunnel configuration preserved"
    fi
fi

# Stop and disable cloudflared service
print_info "Stopping cloudflared service..."
if sudo systemctl is-active --quiet cloudflared 2>/dev/null; then
    sudo systemctl stop cloudflared
    sudo systemctl disable cloudflared
    print_status "cloudflared service stopped and disabled"
else
    print_info "cloudflared service not running"
fi

# Remove cloudflared service file
if [ -f "/etc/systemd/system/cloudflared.service" ]; then
    sudo rm /etc/systemd/system/cloudflared.service
    sudo systemctl daemon-reload
    print_status "cloudflared service file removed"
fi

# Remove cloudflared binary
if [ -f "/usr/local/bin/cloudflared" ]; then
    print_warning "cloudflared binary found at /usr/local/bin/cloudflared"
    read -p "Do you want to remove cloudflared binary? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo rm /usr/local/bin/cloudflared
        print_status "cloudflared binary removed"
    else
        print_info "cloudflared binary preserved"
    fi
fi

print_status "Cleanup completed successfully!"
echo
echo "🎉 Your system is now clean and ready for a fresh setup!"
echo
echo "Next steps:"
echo "1. Run ./setup.sh to configure Nightscout"
echo "2. Run ./setup-cloudflare.sh to set up Cloudflare Tunnel"
echo "3. Start services with: docker-compose up -d" 