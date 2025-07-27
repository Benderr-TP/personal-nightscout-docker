#!/bin/bash

# Cloudflare Tunnel Setup Script for Nightscout
# This script sets up Cloudflare Tunnel to securely expose Nightscout
#
# Usage:
#   ./setup-cloudflare.sh                                           # Interactive mode
#   ./setup-cloudflare.sh --domain host.domain.org                 # With domain
#   ./setup-cloudflare.sh --domain host.domain.org --tunnel-name my-tunnel  # Full specification
#   ./setup-cloudflare.sh --domain host.domain.org --non-interactive       # Automated mode

set -e

# Parse command line arguments
DOMAIN=""
TUNNEL_NAME=""
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --tunnel-name)
            TUNNEL_NAME="$2"
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --help|-h)
            echo "Cloudflare Tunnel Setup Script"
            echo ""
            echo "Usage:"
            echo "  ./setup-cloudflare.sh                                           # Interactive mode"
            echo "  ./setup-cloudflare.sh --domain host.domain.org                 # With domain"
            echo "  ./setup-cloudflare.sh --domain host.domain.org --tunnel-name my-tunnel  # Full specification"
            echo "  ./setup-cloudflare.sh --domain host.domain.org --non-interactive       # Automated mode"
            echo ""
            echo "Options:"
            echo "  --domain DOMAIN        Domain for tunnel routing"
            echo "  --tunnel-name NAME     Custom tunnel name (default: derived from domain)"
            echo "  --non-interactive      Skip interactive prompts, use defaults"
            echo "  --help, -h             Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Generate tunnel name from domain if not provided
if [ -n "$DOMAIN" ] && [ -z "$TUNNEL_NAME" ]; then
    HOSTNAME=$(echo "$DOMAIN" | cut -d'.' -f1)
    TUNNEL_NAME="${HOSTNAME}-tunnel"
fi

echo "☁️  Cloudflare Tunnel Setup for Nightscout"
echo "=========================================="

if [ "$NON_INTERACTIVE" = true ]; then
    echo "🤖 Non-interactive mode"
    [ -n "$DOMAIN" ] && echo "Domain: $DOMAIN"
    [ -n "$TUNNEL_NAME" ] && echo "Tunnel name: $TUNNEL_NAME"
    echo ""
fi

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

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please run this script as a regular user, not as root"
    exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

print_status "Docker is running"

# Check if cloudflared is already installed
if command -v cloudflared >/dev/null 2>&1; then
    print_warning "cloudflared is already installed"
    if [ "$NON_INTERACTIVE" = true ]; then
        print_info "Using existing cloudflared installation"
    else
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Removing existing cloudflared installation..."
            sudo rm -f /usr/local/bin/cloudflared
        else
            print_info "Using existing cloudflared installation"
        fi
    fi
fi

# Install cloudflared if not already installed
if ! command -v cloudflared >/dev/null 2>&1; then
    print_info "Installing cloudflared..."
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    # Download and install cloudflared
    VERSION=$(curl -s https://api.github.com/repos/cloudflare/cloudflared/releases/latest | grep 'tag_name' | cut -d\" -f4)
    DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/download/${VERSION}/cloudflared-linux-${ARCH}"
    
    print_info "Downloading cloudflared version $VERSION..."
    curl -L -o cloudflared "$DOWNLOAD_URL"
    chmod +x cloudflared
    sudo mv cloudflared /usr/local/bin/
    
    print_status "cloudflared installed successfully"
fi

# Check cloudflared version
CLOUDFLARED_VERSION=$(cloudflared version)
print_status "cloudflared version: $CLOUDFLARED_VERSION"

# Create tunnel configuration directory
TUNNEL_DIR="$HOME/.cloudflared"
mkdir -p "$TUNNEL_DIR"

print_info "Setting up Cloudflare Tunnel..."

# Check if user is already authenticated
if [ -f "$TUNNEL_DIR/cert.pem" ]; then
    print_warning "You appear to be already authenticated with Cloudflare"
    if [ "$NON_INTERACTIVE" = true ]; then
        print_info "Using existing authentication"
    else
        read -p "Do you want to re-authenticate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Re-authenticating with Cloudflare..."
            cloudflared tunnel login
        fi
    fi
else
    print_info "Setting up Cloudflare authentication..."
    if [ "$NON_INTERACTIVE" = true ]; then
        print_info "Using browser authentication (non-interactive mode requires existing auth)"
        cloudflared tunnel login
    else
        print_info "Choose authentication method:"
        echo "1. Browser authentication (opens browser) - Recommended"
        echo "2. Use existing certificate from another machine"
        read -p "Enter choice (1 or 2): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[2]$ ]]; then
            print_info "Using existing certificate from another machine..."
            print_info "Please ensure you have copied the certificate file to this system."
            print_info "Required file: ~/.cloudflared/cert.pem"
            
            if [ ! -f "$TUNNEL_DIR/cert.pem" ]; then
                print_error "Certificate file not found!"
                print_info "Please copy the certificate file from your laptop:"
                echo "  scp ~/.cloudflared/cert.pem user@linux-system:~/.cloudflared/"
                exit 1
            fi
            
            print_status "Certificate files found and ready to use"
        else
            print_info "Using browser authentication..."
            print_info "This will open your browser to authenticate with Cloudflare"
            cloudflared tunnel login
        fi
    fi
fi

# Get tunnel name from user or use provided value
print_info "Creating tunnel..."
if [ -z "$TUNNEL_NAME" ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        TUNNEL_NAME="ns-tunnel-ben"
        print_info "Using default tunnel name: $TUNNEL_NAME"
    else
        read -p "Enter a name for your tunnel (e.g., ns-tunnel-ben): " TUNNEL_NAME
        if [ -z "$TUNNEL_NAME" ]; then
            TUNNEL_NAME="ns-tunnel-ben"
        fi
    fi
else
    print_info "Using tunnel name: $TUNNEL_NAME"
fi

# Create tunnel
print_info "Creating tunnel: $TUNNEL_NAME"
cloudflared tunnel create "$TUNNEL_NAME"

# Get tunnel ID with error handling
print_info "Getting tunnel ID..."
TUNNEL_LIST_OUTPUT=$(cloudflared tunnel list -o json 2>&1)
if [ $? -ne 0 ]; then
    print_error "Failed to list tunnels: $TUNNEL_LIST_OUTPUT"
    exit 1
fi

# More robust JSON parsing with validation
TUNNEL_ID=$(echo "$TUNNEL_LIST_OUTPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for tunnel in data:
        if tunnel.get('name') == '$TUNNEL_NAME':
            print(tunnel.get('id', ''))
            break
except (json.JSONDecodeError, KeyError, TypeError) as e:
    print('', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

if [ -z "$TUNNEL_ID" ]; then
    print_error "Failed to extract tunnel ID for tunnel: $TUNNEL_NAME"
    print_info "Available tunnels:"
    echo "$TUNNEL_LIST_OUTPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for tunnel in data:
        print(f\"  - {tunnel.get('name', 'N/A')} (ID: {tunnel.get('id', 'N/A')})\")
except:
    print('Unable to parse tunnel list')
" 2>/dev/null || echo "$TUNNEL_LIST_OUTPUT"
    exit 1
fi

print_status "Tunnel created with ID: $TUNNEL_ID"

# Get domain from user or use provided value
print_info "Setting up custom domain..."
if [ -z "$DOMAIN" ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        print_error "Domain is required in non-interactive mode. Use --domain flag."
        exit 1
    else
        read -p "Enter your domain (e.g., nightscout.yourdomain.com): " DOMAIN
        if [ -z "$DOMAIN" ]; then
            print_error "Domain is required"
            exit 1
        fi
    fi
else
    print_info "Using domain: $DOMAIN"
fi

# Create tunnel configuration file
print_info "Creating tunnel configuration..."
cat > "$TUNNEL_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_DIR/$TUNNEL_ID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:8080
  - service: http_status:404
EOF

print_status "Tunnel configuration created"

# Route traffic to the tunnel with error handling
print_info "Routing traffic to tunnel..."
DNS_ROUTE_OUTPUT=$(cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>&1)
if [ $? -ne 0 ]; then
    print_error "Failed to route DNS to tunnel: $DNS_ROUTE_OUTPUT"
    print_info "This could be due to:"
    print_info "1. Domain not managed by Cloudflare"
    print_info "2. Insufficient permissions on Cloudflare account" 
    print_info "3. Authentication certificate expired or invalid"
    exit 1
fi

print_status "DNS routing configured successfully"
print_info "DNS Output: $DNS_ROUTE_OUTPUT"

# Create systemd service for cloudflared
print_info "Creating systemd service for cloudflared..."

sudo tee /etc/systemd/system/cloudflared.service > /dev/null << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=$USER
EOF

sudo tee -a /etc/systemd/system/cloudflared.service > /dev/null << EOF
ExecStart=/usr/local/bin/cloudflared tunnel --config $TUNNEL_DIR/config.yml run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service with detailed error handling
print_info "Enabling and starting cloudflared service..."
sudo systemctl daemon-reload

# Enable service
if ! sudo systemctl enable cloudflared 2>&1; then
    print_error "Failed to enable cloudflared service"
    exit 1
fi

# Start service with timeout
print_info "Starting cloudflared service..."
if ! sudo systemctl start cloudflared; then
    print_error "Failed to start cloudflared service"
    print_info "Service status:"
    sudo systemctl status cloudflared --no-pager -l
    print_info "Recent logs:"
    sudo journalctl -u cloudflared --no-pager -n 20
    exit 1
fi

# Wait and check service status with retries
print_info "Waiting for service to stabilize..."
for i in {1..10}; do
    sleep 2
    if sudo systemctl is-active --quiet cloudflared; then
        print_status "cloudflared service is running"
        break
    elif [ $i -eq 10 ]; then
        print_error "cloudflared service failed to start properly"
        print_info "Service status:"
        sudo systemctl status cloudflared --no-pager -l
        print_info "Recent logs:"
        sudo journalctl -u cloudflared --no-pager -n 20
        exit 1
    else
        print_info "Waiting for service... (attempt $i/10)"
    fi
done

# Create Docker Compose override for cloudflared
print_info "Creating Docker Compose override for cloudflared..."

cat > docker-compose.cloudflare.yml << EOF
version: '3.8'

services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: nightscout_cloudflared
    restart: unless-stopped
    command: tunnel run --config /etc/cloudflared/config.yml
    volumes:
      - $TUNNEL_DIR:/etc/cloudflared
    networks:
      - nightscout_network
    depends_on:
      - nightscout

networks:
  nightscout_network:
    external: true
EOF

print_status "Docker Compose override created"

# Create management scripts
print_info "Creating management scripts..."

cat > tunnel-status.sh << 'EOF'
#!/bin/bash
echo "🔍 Cloudflare Tunnel Status"
echo "==========================="

# Check if tunnel is running
if sudo systemctl is-active --quiet cloudflared; then
    echo "✓ Tunnel service is running"
else
    echo "✗ Tunnel service is not running"
fi

# Check tunnel connections
echo ""
echo "Tunnel connections:"
cloudflared tunnel list

# Check tunnel information
echo ""
echo "Tunnel information:"
cloudflared tunnel info "$TUNNEL_NAME" 2>/dev/null || echo "Tunnel info not available (requires newer cloudflared version)"
EOF

chmod +x tunnel-status.sh

cat > tunnel-logs.sh << 'EOF'
#!/bin/bash
echo "📋 Cloudflare Tunnel Logs"
echo "========================"
sudo journalctl -u cloudflared -f
EOF

chmod +x tunnel-logs.sh

cat > tunnel-restart.sh << 'EOF'
#!/bin/bash
echo "🔄 Restarting Cloudflare Tunnel"
echo "=============================="
sudo systemctl restart cloudflared
echo "✓ Tunnel restarted"
EOF

chmod +x tunnel-restart.sh

print_status "Management scripts created"

# Test tunnel connection with comprehensive diagnostics
print_info "Testing tunnel connectivity..."

# First check if Nightscout is running locally
print_info "Checking if Nightscout is running on port 8080..."
if ! curl -s -f "http://localhost:8080/api/v1/status" > /dev/null 2>&1; then
    print_warning "Nightscout is not running locally on port 8080"
    print_info "Start Nightscout first with: docker-compose up -d"
    print_info "Skipping tunnel connectivity test for now"
else
    print_status "Nightscout is running locally"
fi

# Test tunnel with retries and better diagnostics
print_info "Testing tunnel connection (this may take a few minutes for DNS propagation)..."
TUNNEL_TEST_SUCCESS=false

for i in {1..3}; do
    print_info "Connection test attempt $i/3..."
    
    # Test with verbose output for debugging
    CURL_OUTPUT=$(curl -s -w "%{http_code}|%{time_total}|%{url_effective}" "https://$DOMAIN/api/v1/status" 2>&1)
    HTTP_CODE=$(echo "$CURL_OUTPUT" | cut -d'|' -f1)
    TIME_TOTAL=$(echo "$CURL_OUTPUT" | cut -d'|' -f2)
    FINAL_URL=$(echo "$CURL_OUTPUT" | cut -d'|' -f3)
    
    if [ "$HTTP_CODE" = "200" ]; then
        print_status "Tunnel connection test successful! (${TIME_TOTAL}s)"
        print_info "Final URL: $FINAL_URL"
        TUNNEL_TEST_SUCCESS=true
        break
    else
        print_warning "Test $i failed - HTTP Code: $HTTP_CODE"
        if [ $i -lt 3 ]; then
            print_info "Waiting 30 seconds before retry..."
            sleep 30
        fi
    fi
done

if [ "$TUNNEL_TEST_SUCCESS" = false ]; then
    print_warning "Tunnel connection test failed after 3 attempts"
    print_info "This is often normal due to DNS propagation delays"
    print_info "Manual tests you can run:"
    echo "  1. Check tunnel status: sudo systemctl status cloudflared"
    echo "  2. Check tunnel logs: sudo journalctl -u cloudflared -f"
    echo "  3. Test connectivity: curl -I https://$DOMAIN"
    echo "  4. Check DNS: nslookup $DOMAIN"
    echo "  5. Verify Nightscout: curl http://localhost:8080/api/v1/status"
fi

# Update .env file to include tunnel information
if [ -f ".env" ]; then
    print_info "Updating .env file with tunnel information..."
    
    # Update or add CLOUDFLARE_DOMAIN
    if grep -q "^CLOUDFLARE_DOMAIN=" .env; then
        sed -i.bak "s|^CLOUDFLARE_DOMAIN=.*|CLOUDFLARE_DOMAIN=$DOMAIN|" .env
    else
        echo "CLOUDFLARE_DOMAIN=$DOMAIN" >> .env
    fi
    
    # Update or add CLOUDFLARE_TUNNEL_ID
    if grep -q "^CLOUDFLARE_TUNNEL_ID=" .env; then
        sed -i.bak "s|^CLOUDFLARE_TUNNEL_ID=.*|CLOUDFLARE_TUNNEL_ID=$TUNNEL_ID|" .env
    else
        echo "CLOUDFLARE_TUNNEL_ID=$TUNNEL_ID" >> .env
    fi
    
    # Clean up backup files
    rm -f .env.bak
    
    print_status "Updated .env file with Cloudflare tunnel information"
else
    print_warning ".env file not found. Please run ./setup.sh first."
fi

# Show next steps
echo
echo "🎉 Cloudflare Tunnel setup completed!"
echo
echo "📋 Summary:"
echo "- Tunnel Name: $TUNNEL_NAME"
echo "- Domain: $DOMAIN"
echo "- Tunnel ID: $TUNNEL_ID"
echo
echo "🔧 Management Commands:"
echo "- Check status: ./tunnel-status.sh"
echo "- View logs: ./tunnel-logs.sh"
echo "- Restart tunnel: ./tunnel-restart.sh"
echo
echo "🌐 Access your Nightscout instance at:"
echo "   https://$DOMAIN"
echo
echo "⚠️  Important Notes:"
echo "- DNS propagation may take a few minutes"
echo "- The tunnel will automatically restart if it goes down"
echo "- Check tunnel status with: ./tunnel-status.sh"
echo
echo "📚 For more information, see:"
echo "- https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/"
echo "- https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/"
echo
echo "🚀 Ready to start Nightscout!"
echo "Run: docker-compose up -d"
echo
echo "🌐 Your Nightscout will be available at:"
echo "   https://$DOMAIN" 