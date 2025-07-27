#!/bin/bash

# Cleanup Unused Cloudflare Tunnels
# This script helps delete unused tunnels

set -e

echo "🧹 Cloudflare Tunnel Cleanup"
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

# List existing tunnels
print_info "Current tunnels:"
cloudflared tunnel list

echo
print_warning "⚠️  WARNING: This will permanently delete tunnels!"
echo "Make sure you know which tunnels you want to keep."
echo

# Ask which tunnels to delete
read -p "Enter tunnel names to delete (space-separated, or 'all' for all except nightscout-ben): " TUNNELS_TO_DELETE

if [ "$TUNNELS_TO_DELETE" = "all" ]; then
    print_info "Deleting all tunnels except 'ns-tunnel-ben'..."
    
    # Get list of tunnels to delete (all except ns-tunnel-ben)
    TUNNELS_TO_DELETE=$(cloudflared tunnel list -o json | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    names = [tunnel['name'] for tunnel in data if tunnel.get('name') != 'ns-tunnel-ben']
    print(' '.join(names))
except:
    sys.exit(1)
" 2>/dev/null)
    
    if [ -z "$TUNNELS_TO_DELETE" ]; then
        print_info "No tunnels to delete (only ns-tunnel-ben exists)"
        exit 0
    fi
fi

# Confirm deletion
echo
print_warning "The following tunnels will be deleted:"
for tunnel in $TUNNELS_TO_DELETE; do
    echo "  - $tunnel"
done

echo
read -p "Are you sure you want to delete these tunnels? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Delete tunnels
    for tunnel in $TUNNELS_TO_DELETE; do
        print_info "Deleting tunnel: $tunnel"
        cloudflared tunnel delete "$tunnel"
        print_status "Deleted tunnel: $tunnel"
    done
    
    echo
    print_status "Cleanup completed!"
    echo
    print_info "Remaining tunnels:"
    cloudflared tunnel list
else
    print_info "Cleanup cancelled."
fi 