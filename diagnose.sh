#!/bin/bash

# Nightscout Diagnostic Script
# This script helps diagnose issues with Nightscout deployment

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

print_header() {
    echo
    echo "===================="
    echo "$1"
    echo "===================="
}

echo "🔍 Nightscout Deployment Diagnostics"
echo "===================================="

# System Information
print_header "SYSTEM INFORMATION"

echo "Operating System: $(uname -s)"
echo "Architecture: $(uname -m)"
echo "Hostname: $(hostname)"
echo "Date: $(date)"

if command -v lsb_release >/dev/null 2>&1; then
    echo "Distribution: $(lsb_release -d | cut -f2-)"
fi

# Check available utilities
print_header "AVAILABLE UTILITIES"

UTILITIES=("curl" "docker" "docker-compose" "lsof" "netstat" "ss" "dig" "nslookup" "htop" "systemctl" "journalctl")

for util in "${UTILITIES[@]}"; do
    if command -v "$util" >/dev/null 2>&1; then
        print_status "$util is available"
    else
        print_warning "$util is not installed"
    fi
done

# Docker Status
print_header "DOCKER STATUS"

if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        print_status "Docker daemon is running"
        echo "Docker version: $(docker --version)"
        
        if command -v docker-compose >/dev/null 2>&1; then
            echo "Docker Compose version: $(docker-compose --version)"
        fi
    else
        print_error "Docker daemon is not running"
        print_info "Start with: sudo systemctl start docker"
    fi
else
    print_error "Docker is not installed"
fi

# Check running containers
print_header "RUNNING CONTAINERS"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    CONTAINERS=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")
    if [ "$(docker ps -q | wc -l)" -gt 0 ]; then
        echo "$CONTAINERS"
    else
        print_warning "No containers are currently running"
    fi
    
    echo
    echo "All containers (including stopped):"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
else
    print_warning "Cannot check containers - Docker not available"
fi

# Port Usage
print_header "PORT USAGE"

PORTS_TO_CHECK=(8080 8081 1337 27017 80 443)

for port in "${PORTS_TO_CHECK[@]}"; do
    echo "Checking port $port:"
    
    # Using lsof if available
    if command -v lsof >/dev/null 2>&1; then
        LSOF_OUTPUT=$(lsof -i :$port 2>/dev/null || true)
        if [ -n "$LSOF_OUTPUT" ]; then
            print_warning "Port $port is in use:"
            echo "$LSOF_OUTPUT" | sed 's/^/  /'
        else
            print_status "Port $port is available"
        fi
    # Fallback to netstat
    elif command -v netstat >/dev/null 2>&1; then
        NETSTAT_OUTPUT=$(netstat -tlnp 2>/dev/null | grep ":$port " || true)
        if [ -n "$NETSTAT_OUTPUT" ]; then
            print_warning "Port $port is in use:"
            echo "$NETSTAT_OUTPUT" | sed 's/^/  /'
        else
            print_status "Port $port is available"
        fi
    # Fallback to ss
    elif command -v ss >/dev/null 2>&1; then
        SS_OUTPUT=$(ss -tlnp 2>/dev/null | grep ":$port " || true)
        if [ -n "$SS_OUTPUT" ]; then
            print_warning "Port $port is in use:"
            echo "$SS_OUTPUT" | sed 's/^/  /'
        else
            print_status "Port $port is available"
        fi
    else
        print_warning "No port checking utility available"
        break
    fi
    echo
done

# Nightscout specific checks
print_header "NIGHTSCOUT HEALTH CHECKS"

# Check if .env file exists
if [ -f ".env" ]; then
    print_status ".env file exists"
    
    # Check for required variables
    REQUIRED_VARS=("API_SECRET" "MONGO_CONNECTION" "MONGO_INITDB_ROOT_PASSWORD")
    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^$var=" .env; then
            VALUE=$(grep "^$var=" .env | cut -d'=' -f2-)
            if [ -n "$VALUE" ] && [[ "$VALUE" != *"change_this"* ]]; then
                print_status "$var is configured"
            else
                print_error "$var is not properly configured"
            fi
        else
            print_error "$var is missing from .env"
        fi
    done
else
    print_error ".env file not found - run ./setup.sh first"
fi

# Check if docker-compose.yml exists
if [ -f "docker-compose.yml" ]; then
    print_status "docker-compose.yml exists"
else
    print_error "docker-compose.yml not found"
fi

# Test HTTP connectivity to Nightscout
echo
print_info "Testing Nightscout connectivity..."

if command -v curl >/dev/null 2>&1; then
    HTTP_RESPONSE=$(curl -s -w "%{http_code}" http://localhost:8080/api/v1/status 2>/dev/null || echo "000")
    
    if [ "$HTTP_RESPONSE" = "200" ]; then
        print_status "Nightscout is responding on port 8080"
        
        # Get detailed status
        STATUS_JSON=$(curl -s http://localhost:8080/api/v1/status 2>/dev/null || echo "{}")
        if echo "$STATUS_JSON" | grep -q "status"; then
            echo "Status response: $STATUS_JSON"
        fi
    elif [ "$HTTP_RESPONSE" = "000" ]; then
        print_error "Cannot connect to Nightscout on port 8080"
        print_info "Make sure Nightscout is running: docker-compose up -d"
    else
        print_warning "Nightscout returned HTTP $HTTP_RESPONSE"
    fi
else
    print_warning "curl not available - cannot test HTTP connectivity"
fi

# Cloudflare Tunnel Status
print_header "CLOUDFLARE TUNNEL STATUS"

if [ -f "$HOME/.cloudflared/config.yml" ]; then
    print_status "Cloudflare tunnel configuration found"
    
    if command -v cloudflared >/dev/null 2>&1; then
        print_status "cloudflared is installed"
        echo "Version: $(cloudflared version)"
        
        # Check if tunnel service is running
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet cloudflared 2>/dev/null; then
                print_status "Cloudflare tunnel service is running"
            else
                print_warning "Cloudflare tunnel service is not running"
                print_info "Start with: sudo systemctl start cloudflared"
            fi
        fi
        
        # List tunnels
        echo
        print_info "Available tunnels:"
        cloudflared tunnel list 2>/dev/null || print_warning "Cannot list tunnels"
    else
        print_warning "cloudflared is not installed"
    fi
else
    print_warning "No Cloudflare tunnel configuration found"
    print_info "Run ./setup-cloudflare.sh to set up tunnel"
fi

# DNS Checks
print_header "DNS CHECKS"

if [ -f ".env" ] && grep -q "CLOUDFLARE_DOMAIN=" .env; then
    DOMAIN=$(grep "CLOUDFLARE_DOMAIN=" .env | cut -d'=' -f2-)
    
    if [ -n "$DOMAIN" ]; then
        print_info "Checking DNS for domain: $DOMAIN"
        
        if command -v dig >/dev/null 2>&1; then
            DIG_OUTPUT=$(dig +short "$DOMAIN" 2>/dev/null || true)
            if [ -n "$DIG_OUTPUT" ]; then
                print_status "DNS resolves to: $DIG_OUTPUT"
            else
                print_warning "DNS does not resolve for $DOMAIN"
            fi
        elif command -v nslookup >/dev/null 2>&1; then
            NSLOOKUP_OUTPUT=$(nslookup "$DOMAIN" 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}' || true)
            if [ -n "$NSLOOKUP_OUTPUT" ]; then
                print_status "DNS resolves to: $NSLOOKUP_OUTPUT"
            else
                print_warning "DNS does not resolve for $DOMAIN"
            fi
        else
            print_warning "No DNS lookup utility available"
        fi
    fi
fi

# System Resources
print_header "SYSTEM RESOURCES"

echo "Memory usage:"
if command -v free >/dev/null 2>&1; then
    free -h
else
    print_warning "free command not available"
fi

echo
echo "Disk usage:"
if command -v df >/dev/null 2>&1; then
    df -h | grep -E "(/|/var|/home)"
else
    print_warning "df command not available"
fi

echo
echo "Load average:"
if [ -f "/proc/loadavg" ]; then
    cat /proc/loadavg
else
    print_warning "Load average not available"
fi

# Log Analysis
print_header "LOG ANALYSIS"

print_info "Recent Docker logs for Nightscout:"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker ps --format "{{.Names}}" | grep -q "nightscout"; then
        docker logs --tail=10 nightscout 2>/dev/null || print_warning "Cannot get Nightscout logs"
    else
        print_warning "Nightscout container not found"
    fi
    
    echo
    print_info "Recent Docker logs for MongoDB:"
    if docker ps --format "{{.Names}}" | grep -q "mongo"; then
        docker logs --tail=5 nightscout_mongo 2>/dev/null || print_warning "Cannot get MongoDB logs"
    else
        print_warning "MongoDB container not found"
    fi
else
    print_warning "Cannot check Docker logs - Docker not available"
fi

echo
print_info "Recent Cloudflare tunnel logs:"
if command -v journalctl >/dev/null 2>&1; then
    sudo journalctl -u cloudflared --no-pager -n 5 2>/dev/null || print_warning "Cannot get Cloudflare tunnel logs"
else
    print_warning "journalctl not available"
fi

# Final recommendations
print_header "RECOMMENDATIONS"

echo "Based on the diagnostics above:"
echo
echo "1. If containers aren't running: docker-compose up -d"
echo "2. If ports are in use: Check what's using them with lsof -i :PORT"
echo "3. If Nightscout isn't responding: Check logs with docker-compose logs nightscout"
echo "4. If tunnel isn't working: Check sudo journalctl -u cloudflared -f"
echo "5. For real-time monitoring: Use docker stats or htop"
echo
echo "🔧 Useful commands:"
echo "  - Check all services: ./diagnose.sh"
echo "  - Monitor containers: docker stats"
echo "  - View logs: docker-compose logs -f"
echo "  - Restart services: docker-compose restart"
echo "  - Tunnel status: ./tunnel-status.sh"