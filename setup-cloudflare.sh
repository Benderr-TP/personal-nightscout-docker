#!/bin/bash

# Cloudflare Tunnel Setup Script for Nightscout
# This script sets up Cloudflare Tunnel to securely expose Nightscout

set -e

echo "☁️  Cloudflare Tunnel Setup for Nightscout"
echo "=========================================="

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
    read -p "Do you want to reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removing existing cloudflared installation..."
        sudo rm -f /usr/local/bin/cloudflared
    else
        print_info "Using existing cloudflared installation"
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
    read -p "Do you want to re-authenticate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Re-authenticating with Cloudflare..."
        cloudflared tunnel login
    fi
else
    print_info "Setting up Cloudflare authentication..."
    print_info "Choose authentication method:"
    echo "1. Browser authentication (opens browser) - Recommended"
    echo "2. API token authentication (headless servers)"
    echo "3. Use existing certificate from another machine"
    read -p "Enter choice (1, 2, or 3): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[3]$ ]]; then
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
        
    elif [[ $REPLY =~ ^[2]$ ]]; then
        print_warning "API token authentication may not work for tunnel creation."
        print_info "It's recommended to use browser authentication for tunnel setup."
        read -p "Continue with API token anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Switching to browser authentication..."
            cloudflared tunnel login
        else
            print_info "Using API token authentication..."
            read -p "Enter your Cloudflare API token: " API_TOKEN
            if [ -z "$API_TOKEN" ]; then
                print_error "API token is required"
                exit 1
            fi
            
            # Create config with API token
            mkdir -p "$TUNNEL_DIR"
            cat > "$TUNNEL_DIR/config.yml" << EOF
# Cloudflare API Token Configuration
# This file will be used for API token authentication
api_token: $API_TOKEN
EOF
            
            print_status "API token configured"
            print_info "Note: API token authentication will be used for tunnel operations"
        fi
    else
        print_info "Using browser authentication..."
        print_info "This will open your browser to authenticate with Cloudflare"
        cloudflared tunnel login
    fi
fi

# Get tunnel name from user
print_info "Creating tunnel..."
read -p "Enter a name for your tunnel (e.g., ns-tunnel-ben): " TUNNEL_NAME
if [ -z "$TUNNEL_NAME" ]; then
    TUNNEL_NAME="ns-tunnel-ben"
fi

# Create tunnel
print_info "Creating tunnel: $TUNNEL_NAME"
# Note: Tunnel creation requires certificate authentication, even with API tokens
# The API token will be used for subsequent operations
cloudflared tunnel create "$TUNNEL_NAME"

# Get tunnel ID
TUNNEL_ID=$(cloudflared tunnel list --name "$TUNNEL_NAME" --format json | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
print_status "Tunnel created with ID: $TUNNEL_ID"

# Get domain from user
print_info "Setting up custom domain..."
read -p "Enter your domain (e.g., nightscout.yourdomain.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    print_error "Domain is required"
    exit 1
fi

# Create tunnel configuration file
print_info "Creating tunnel configuration..."
if [ -f "$TUNNEL_DIR/config.yml" ] && grep -q "api_token" "$TUNNEL_DIR/config.yml"; then
    # API token configuration
    cat > "$TUNNEL_DIR/config.yml" << EOF
# Cloudflare API Token Configuration
api_token: $(grep "api_token:" "$TUNNEL_DIR/config.yml" | sed 's/api_token: //')

# Tunnel Configuration
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_DIR/$TUNNEL_ID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:8080
  - service: http_status:404
EOF
else
    # Certificate configuration
    cat > "$TUNNEL_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_DIR/$TUNNEL_ID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:8080
  - service: http_status:404
EOF
fi

print_status "Tunnel configuration created"

# Route traffic to the tunnel
print_info "Routing traffic to tunnel..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"

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

# Add environment variables for API token if using API token authentication
if [ -f "$TUNNEL_DIR/config.yml" ] && grep -q "api_token" "$TUNNEL_DIR/config.yml"; then
    API_TOKEN=$(grep "api_token:" "$TUNNEL_DIR/config.yml" | sed 's/api_token: //')
    sudo tee -a /etc/systemd/system/cloudflared.service > /dev/null << EOF
Environment="CLOUDFLARE_API_TOKEN=$API_TOKEN"
Environment="TUNNEL_ORIGIN_CERT=$TUNNEL_DIR/cert.pem"
EOF
fi

sudo tee -a /etc/systemd/system/cloudflared.service > /dev/null << EOF
ExecStart=/usr/local/bin/cloudflared tunnel --config $TUNNEL_DIR/config.yml run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
print_info "Enabling and starting cloudflared service..."
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl start cloudflared

# Check service status
if sudo systemctl is-active --quiet cloudflared; then
    print_status "cloudflared service is running"
else
    print_error "cloudflared service failed to start"
    print_info "Check logs with: sudo journalctl -u cloudflared -f"
    exit 1
fi

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

# Check DNS records
echo ""
echo "DNS records:"
cloudflared tunnel route ip show
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

# Test tunnel connection
print_info "Testing tunnel connection..."
sleep 5  # Give the tunnel a moment to start
if curl -s -f "https://$DOMAIN" > /dev/null 2>&1; then
    print_status "Tunnel connection test successful!"
else
    print_warning "Tunnel connection test failed. This is normal if DNS hasn't propagated yet."
    print_info "DNS propagation can take a few minutes. You can test again later with:"
    echo "  curl -I https://$DOMAIN"
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