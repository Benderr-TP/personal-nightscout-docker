#!/bin/bash

# Comprehensive Cloudflare Tunnel Debug Script
# This script provides detailed diagnostics for tunnel issues

set -e

echo "🔍 Cloudflare Tunnel Debug & Diagnostic Tool"
echo "============================================"

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

print_section() {
    echo
    echo "═══════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════"
}

# Get domain from .env if available
DOMAIN=""
if [ -f ".env" ]; then
    DOMAIN=$(grep "^CLOUDFLARE_DOMAIN=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
fi

if [ -z "$DOMAIN" ]; then
    read -p "Enter your domain (e.g., nightscout.yourdomain.com): " DOMAIN
fi

print_info "Debugging domain: $DOMAIN"

# Section 1: System Prerequisites
print_section "1. SYSTEM PREREQUISITES"

# Check cloudflared installation
if command -v cloudflared >/dev/null 2>&1; then
    CLOUDFLARED_VERSION=$(cloudflared version 2>/dev/null || echo "unknown")
    print_status "cloudflared installed: $CLOUDFLARED_VERSION"
else
    print_error "cloudflared not installed"
fi

# Check Docker
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    print_status "Docker is running"
else
    print_error "Docker is not running or not installed"
fi

# Check curl
if command -v curl >/dev/null 2>&1; then
    print_status "curl is available"
else
    print_error "curl is not installed"
fi

# Section 2: Cloudflare Authentication
print_section "2. CLOUDFLARE AUTHENTICATION"

TUNNEL_DIR="$HOME/.cloudflared"
if [ -f "$TUNNEL_DIR/cert.pem" ]; then
    print_status "Certificate authentication file found"
    CERT_INFO=$(openssl x509 -in "$TUNNEL_DIR/cert.pem" -text -noout 2>/dev/null | grep "Subject:" || echo "Unable to read certificate")
    print_info "Certificate: $CERT_INFO"
else
    print_warning "No certificate file found at $TUNNEL_DIR/cert.pem"
fi

print_info "Using certificate-based authentication"

# Section 3: Tunnel Configuration
print_section "3. TUNNEL CONFIGURATION"

if [ -f "$TUNNEL_DIR/config.yml" ]; then
    print_status "Tunnel configuration file exists"
    print_info "Configuration contents:"
    cat "$TUNNEL_DIR/config.yml"
    echo
else
    print_error "Tunnel configuration file not found at $TUNNEL_DIR/config.yml"
fi

# List available tunnels
print_info "Available tunnels:"
if cloudflared tunnel list 2>/dev/null; then
    echo
else
    print_error "Failed to list tunnels - check authentication"
fi

# Section 4: Service Status
print_section "4. CLOUDFLARED SERVICE STATUS"

if systemctl is-enabled cloudflared >/dev/null 2>&1; then
    print_status "cloudflared service is enabled"
else
    print_warning "cloudflared service is not enabled"
fi

if systemctl is-active --quiet cloudflared 2>/dev/null; then
    print_status "cloudflared service is running"
    
    print_info "Service details:"
    systemctl status cloudflared --no-pager -l 2>/dev/null || echo "Unable to get service status"
    
    print_info "Recent service logs (last 10 lines):"
    journalctl -u cloudflared --no-pager -n 10 2>/dev/null || echo "Unable to get service logs"
else
    print_error "cloudflared service is not running"
    
    print_info "Service status details:"
    systemctl status cloudflared --no-pager -l 2>/dev/null || echo "Service not found"
fi

# Section 5: Network Connectivity
print_section "5. NETWORK CONNECTIVITY"

# Test local Nightscout
print_info "Testing local Nightscout on port 8080..."
if curl -s -f "http://localhost:8080/api/v1/status" >/dev/null 2>&1; then
    print_status "Nightscout is running locally"
    LOCAL_STATUS=$(curl -s "http://localhost:8080/api/v1/status" 2>/dev/null)
    print_info "Local status: $LOCAL_STATUS"
else
    print_warning "Nightscout is not responding on localhost:8080"
    print_info "Check if containers are running: docker ps"
fi

# Test external connectivity
print_info "Testing external connectivity to $DOMAIN..."
CURL_RESULT=$(curl -s -w "HTTP_CODE:%{http_code}|TIME:%{time_total}|SIZE:%{size_download}" "https://$DOMAIN/api/v1/status" 2>&1 || echo "CURL_FAILED")

if echo "$CURL_RESULT" | grep -q "HTTP_CODE:200"; then
    print_status "External tunnel connectivity successful"
    HTTP_CODE=$(echo "$CURL_RESULT" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    TIME_TOTAL=$(echo "$CURL_RESULT" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    print_info "Response: HTTP $HTTP_CODE in ${TIME_TOTAL}s"
else
    print_error "External tunnel connectivity failed"
    print_info "curl result: $CURL_RESULT"
fi

# Section 6: DNS Diagnostics
print_section "6. DNS DIAGNOSTICS"

print_info "DNS lookup for $DOMAIN:"
if command -v nslookup >/dev/null 2>&1; then
    nslookup "$DOMAIN" 2>/dev/null || echo "DNS lookup failed"
else
    print_warning "nslookup not available"
fi

print_info "Checking if domain points to Cloudflare:"
if command -v dig >/dev/null 2>&1; then
    dig +short "$DOMAIN" 2>/dev/null | head -5
elif command -v host >/dev/null 2>&1; then
    host "$DOMAIN" 2>/dev/null | head -5
else
    print_warning "dig/host commands not available for detailed DNS check"
fi

# Section 7: Container Status
print_section "7. DOCKER CONTAINER STATUS"

print_info "Nightscout-related containers:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(nightscout|mongo)" 2>/dev/null || echo "No Nightscout containers found"

print_info "Network status:"
docker network ls | grep nightscout 2>/dev/null || echo "No Nightscout networks found"

# Section 8: Recommendations
print_section "8. TROUBLESHOOTING RECOMMENDATIONS"

if systemctl is-active --quiet cloudflared 2>/dev/null; then
    if curl -s -f "https://$DOMAIN/api/v1/status" >/dev/null 2>&1; then
        print_status "✅ Everything appears to be working correctly!"
    else
        print_warning "Service is running but external access failed"
        echo "Recommended actions:"
        echo "1. Wait 5-10 minutes for DNS propagation"
        echo "2. Check domain configuration in Cloudflare dashboard"
        echo "3. Verify domain is managed by Cloudflare"
        echo "4. Check tunnel logs: sudo journalctl -u cloudflared -f"
    fi
else
    print_error "Service is not running"
    echo "Recommended actions:"
    echo "1. Restart the service: sudo systemctl restart cloudflared"
    echo "2. Check configuration: cat ~/.cloudflared/config.yml"
    echo "3. Verify authentication: cloudflared tunnel list"
    echo "4. Re-run setup: ./setup-cloudflare.sh"
fi

if ! curl -s -f "http://localhost:8080/api/v1/status" >/dev/null 2>&1; then
    print_warning "Nightscout is not running locally"
    echo "Start Nightscout first:"
    echo "1. docker-compose up -d"
    echo "2. Check container logs: docker-compose logs -f"
fi

echo
print_info "Debug completed. If issues persist, please check the logs and try the recommended actions."
print_info "For more help, see: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/troubleshooting/"