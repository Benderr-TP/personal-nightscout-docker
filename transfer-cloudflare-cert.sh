#!/bin/bash

# Cloudflare Certificate Transfer Script
# This script helps transfer Cloudflare certificates from your laptop to a remote Linux system

set -e

echo "🔐 Cloudflare Certificate Transfer"
echo "=================================="

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

# Check if certificate file exists locally
LOCAL_CERT_DIR="$HOME/.cloudflared"
if [ ! -f "$LOCAL_CERT_DIR/cert.pem" ]; then
    print_error "Cloudflare certificate file not found on your laptop!"
    print_info "Please authenticate with Cloudflare first:"
    echo "  cloudflared tunnel login"
    exit 1
fi

print_status "Certificate file found on your laptop"

# Get remote system details
print_info "Enter remote system details:"
read -p "Remote username: " REMOTE_USER
read -p "Remote hostname/IP: " REMOTE_HOST
read -p "Remote port (default 22): " REMOTE_PORT
REMOTE_PORT=${REMOTE_PORT:-22}

# Test SSH connection
print_info "Testing SSH connection..."
if ! ssh -p "$REMOTE_PORT" -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
    print_error "SSH connection failed!"
    print_info "Please check your SSH configuration and try again."
    exit 1
fi

print_status "SSH connection successful"

# Create remote directory
print_info "Creating remote directory..."
ssh -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" "mkdir -p ~/.cloudflared"

# Transfer certificate file
print_info "Transferring certificate file..."
scp -P "$REMOTE_PORT" "$LOCAL_CERT_DIR/cert.pem" "$REMOTE_USER@$REMOTE_HOST:~/.cloudflared/"

# Set proper permissions
print_info "Setting file permissions..."
ssh -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" "chmod 600 ~/.cloudflared/cert.pem"

print_status "Certificate transfer completed successfully!"
echo
echo "📋 Next steps:"
echo "1. SSH to your remote system: ssh $REMOTE_USER@$REMOTE_HOST"
echo "2. Navigate to your Nightscout directory"
echo "3. Run: ./setup-cloudflare.sh"
echo "4. Choose option 3 (Use existing certificate from another machine)"
echo
echo "⚠️  Security notes:"
echo "- Certificate file is sensitive and should be kept secure"
echo "- The file is now on your remote system with proper permissions"
echo "- You can delete the local certificate file if desired" 