#!/bin/bash

# Nightscout Setup Script
# This script helps configure Nightscout for deployment
# 
# Usage:
#   ./setup.sh                                    # Interactive mode
#   ./setup.sh --domain host.domain.org          # One-liner with domain
#   ./setup.sh --domain host.domain.org --setup-tunnel  # Full automated setup

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

# Parse command line arguments
DOMAIN=""
SETUP_TUNNEL=false
INTERACTIVE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            INTERACTIVE=false
            shift 2
            ;;
        --setup-tunnel)
            SETUP_TUNNEL=true
            shift
            ;;
        --help|-h)
            echo "Nightscout Setup Script"
            echo ""
            echo "Usage:"
            echo "  ./setup.sh                                    # Interactive mode"
            echo "  ./setup.sh --domain host.domain.org          # One-liner with domain"
            echo "  ./setup.sh --domain host.domain.org --setup-tunnel  # Full automated setup"
            echo ""
            echo "Options:"
            echo "  --domain DOMAIN        Set domain for Cloudflare tunnel"
            echo "  --setup-tunnel         Automatically setup Cloudflare tunnel after basic setup"
            echo "  --help, -h             Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Generate tunnel name from domain if provided
TUNNEL_NAME=""
if [ -n "$DOMAIN" ]; then
    # Extract hostname from domain (e.g., host.domain.org -> host)
    HOSTNAME=$(echo "$DOMAIN" | cut -d'.' -f1)
    TUNNEL_NAME="${HOSTNAME}-tunnel"
fi

echo "🔧 Nightscout Setup Script"
echo "=========================="

if [ "$INTERACTIVE" = false ]; then
    echo "🚀 One-liner setup mode"
    echo "Domain: $DOMAIN"
    echo "Tunnel name: $TUNNEL_NAME"
    echo ""
fi

# Check for required commands
REQUIRED_COMMANDS=("openssl" "sed" "curl" "docker" "docker-compose")
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
    print_info "Install them with:"
    echo "  sudo apt update && sudo apt install -y openssl sed curl docker.io docker-compose"
    exit 1
fi

# Check for helpful diagnostic utilities
DIAGNOSTIC_COMMANDS=("lsof" "netstat" "ss" "dig" "htop")
MISSING_DIAGNOSTIC=()

for cmd in "${DIAGNOSTIC_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_DIAGNOSTIC+=("$cmd")
    fi
done

if [ ${#MISSING_DIAGNOSTIC[@]} -ne 0 ]; then
    print_warning "Some helpful diagnostic utilities are missing:"
    for cmd in "${MISSING_DIAGNOSTIC[@]}"; do
        echo "  - $cmd"
    done
    echo
    print_info "Install them with:"
    echo "  sudo apt install -y lsof net-tools iproute2 dnsutils htop"
    echo
fi

# Check if .env file exists
if [ -f ".env" ]; then
    print_warning ".env file already exists. This will overwrite it."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 1
    fi
fi

# Create .env file with default values
print_info "Creating .env file with default values..."
cat > .env << 'EOF'
# Nightscout Environment Configuration

# =============================================================================
# REQUIRED SECURITY VARIABLES (CHANGE THESE!)
# =============================================================================

# API Secret - Used for API authentication (minimum 12 characters)
API_SECRET=change_this_to_a_long_random_string

# MongoDB Root Password (minimum 8 characters)
MONGO_INITDB_ROOT_PASSWORD=change_this_password

# MongoDB Connection String (auto-generated from password above)
MONGO_CONNECTION=mongodb://root:change_this_password@mongo:27017/nightscout?authSource=admin

# =============================================================================
# BASIC CONFIGURATION
# =============================================================================

# Timezone (e.g., America/New_York, Europe/London, Asia/Tokyo)
TZ=America/New_York

# Display Units (mg/dl or mmol/L)
DISPLAY_UNITS=mg/dl

# Custom Title for your Nightscout site
CUSTOM_TITLE=My Nightscout

# =============================================================================
# NIGHTSCOUT FEATURES
# =============================================================================

# Features to enable (space-separated list)
ENABLE=careportal basal dbsize rawbg iob maker cob bwp cage iage sage boluscalc pushover treatmentnotify loop pump profile food openaps bage alexa override cors

# Default features to show
DEFAULT_FEATURES=careportal boluscalc food rawbg iob

# =============================================================================
# ALARM SETTINGS
# =============================================================================

# High blood glucose alarm (mg/dl)
ALARM_HIGH=260

# Low blood glucose alarm (mg/dl)
ALARM_LOW=55

# Urgent high blood glucose alarm (mg/dl)
ALARM_URGENT_HIGH=370

# Urgent low blood glucose alarm (mg/dl)
ALARM_URGENT_LOW=40

# =============================================================================
# THEME AND LANGUAGE
# =============================================================================

# Theme (colors, colors-dark, default)
THEME=colors

# Language (en, de, fr, etc.)
LANGUAGE=en

# Authentication default roles
AUTH_DEFAULT_ROLES=readable

# =============================================================================
# CLOUDFLARE TUNNEL CONFIGURATION
# =============================================================================
# These will be automatically set by setup-cloudflare.sh
# You can also set them manually if needed

# Cloudflare Tunnel Domain (e.g., nightscout.yourdomain.com)
CLOUDFLARE_DOMAIN=

# Cloudflare Tunnel ID (auto-generated during tunnel creation)
CLOUDFLARE_TUNNEL_ID=

# =============================================================================
# ADVANCED SETTINGS (Optional)
# =============================================================================

# Node environment
NODE_ENV=production

# MongoDB collection name
MONGO_COLLECTION=entries

# Security headers for production
INSECURE_USE_HTTP=false
SECURE_HSTS_HEADER=true
SECURE_HSTS_HEADER_INCLUDESUBDOMAINS=true
SECURE_HSTS_HEADER_PRELOAD=true
EOF

print_status "Created .env file with default values"

# Generate secure secrets
print_info "Generating secure secrets..."

# Generate API_SECRET
API_SECRET=$(openssl rand -base64 32)
sed -i.bak "s|API_SECRET=.*|API_SECRET=$API_SECRET|" .env

# Generate MongoDB password
MONGO_PASSWORD=$(openssl rand -base64 24)
sed -i.bak "s|MONGO_INITDB_ROOT_PASSWORD=.*|MONGO_INITDB_ROOT_PASSWORD=$MONGO_PASSWORD|" .env

print_status "Generated secure API_SECRET and MongoDB password"

# Update MongoDB connection string
sed -i.bak "s|MONGO_CONNECTION=.*|MONGO_CONNECTION=mongodb://root:$MONGO_PASSWORD@mongo:27017/nightscout?authSource=admin|" .env

print_status "Updated MongoDB connection string"

# Configure timezone
print_info "Setting timezone..."
if [ "$INTERACTIVE" = true ]; then
    read -p "Enter your timezone (e.g., America/New_York, Europe/London): " TZ
    if [ ! -z "$TZ" ]; then
        sed -i.bak "s|TZ=.*|TZ=$TZ|" .env
        print_status "Set timezone to $TZ"
    fi
else
    # Use default timezone in non-interactive mode
    print_status "Using default timezone: America/New_York"
fi

# Configure display units
print_info "Setting display units..."
if [ "$INTERACTIVE" = true ]; then
    read -p "Enter display units (mg/dl or mmol/L): " DISPLAY_UNITS
    if [ "$DISPLAY_UNITS" = "mmol/L" ] || [ "$DISPLAY_UNITS" = "mmol/l" ]; then
        sed -i.bak "s|DISPLAY_UNITS=.*|DISPLAY_UNITS=mmol/L|" .env
        print_status "Set display units to mmol/L"
    elif [ "$DISPLAY_UNITS" = "mg/dl" ] || [ "$DISPLAY_UNITS" = "mg/dL" ]; then
        sed -i.bak "s|DISPLAY_UNITS=.*|DISPLAY_UNITS=mg/dl|" .env
        print_status "Set display units to mg/dl"
    else
        print_warning "Unrecognized input. Defaulting to mg/dl."
        sed -i.bak "s|DISPLAY_UNITS=.*|DISPLAY_UNITS=mg/dl|" .env
    fi
else
    # Use default display units in non-interactive mode
    print_status "Using default display units: mg/dl"
fi

# Configure custom title
print_info "Setting custom title..."
if [ "$INTERACTIVE" = true ]; then
    read -p "Enter custom title for your Nightscout site: " CUSTOM_TITLE
    if [ ! -z "$CUSTOM_TITLE" ]; then
        sed -i.bak "s|CUSTOM_TITLE=.*|CUSTOM_TITLE=$CUSTOM_TITLE|" .env
        print_status "Set custom title to '$CUSTOM_TITLE'"
    fi
else
    # Generate title from hostname if domain provided
    if [ -n "$DOMAIN" ]; then
        HOSTNAME=$(echo "$DOMAIN" | cut -d'.' -f1)
        CUSTOM_TITLE="${HOSTNAME^} Nightscout"  # Capitalize first letter
        sed -i.bak "s|CUSTOM_TITLE=.*|CUSTOM_TITLE=$CUSTOM_TITLE|" .env
        print_status "Set custom title to '$CUSTOM_TITLE'"
    else
        print_status "Using default custom title: Nightscout"
    fi
fi

# Set domain and tunnel name if provided
if [ -n "$DOMAIN" ]; then
    print_info "Configuring Cloudflare tunnel settings..."
    sed -i.bak "s|CLOUDFLARE_DOMAIN=.*|CLOUDFLARE_DOMAIN=$DOMAIN|" .env
    print_status "Set Cloudflare domain to $DOMAIN"
    
    # Store tunnel name for later use
    echo "TUNNEL_NAME=$TUNNEL_NAME" >> .env
    print_status "Set tunnel name to $TUNNEL_NAME"
fi

# Clean up backup files
rm -f .env.bak

# Validate configuration
print_info "Validating configuration..."

# Check if required variables are set
if grep -q "change_this" .env; then
    print_error "Some required variables still have default values!"
    echo "Please edit .env file and update the following:"
    grep "change_this" .env
    exit 1
fi

# Check API_SECRET length
API_SECRET_LENGTH=$(grep "API_SECRET=" .env | cut -d'=' -f2 | wc -c)
if [ $API_SECRET_LENGTH -lt 13 ]; then
    print_error "API_SECRET is too short (minimum 12 characters)"
    exit 1
fi

print_status "Configuration validation passed!"

# Automatic tunnel setup if requested
if [ "$SETUP_TUNNEL" = true ]; then
    echo
    print_info "🚀 Setting up complete deployment with Docker and Cloudflare tunnel..."
    
    if [ -z "$DOMAIN" ]; then
        print_error "Domain is required for tunnel setup. Use --domain flag."
        exit 1
    fi
    
    # Check if setup-cloudflare.sh exists
    if [ ! -f "./setup-cloudflare.sh" ]; then
        print_error "setup-cloudflare.sh not found in current directory"
        exit 1
    fi
    
    # Check if docker-compose.yml exists
    if [ ! -f "./docker-compose.yml" ]; then
        print_error "docker-compose.yml not found in current directory"
        exit 1
    fi
    
    # Step 1: Start Nightscout with Docker
    print_info "Step 1: Starting Nightscout with Docker Compose..."
    if docker-compose up -d; then
        print_status "Docker Compose started successfully"
    else
        print_error "Failed to start Docker Compose"
        print_info "Please check for port conflicts or configuration issues"
        print_info "Try: docker-compose logs"
        exit 1
    fi
    
    # Step 2: Wait for Nightscout to be fully ready
    print_info "Step 2: Waiting for Nightscout to be ready and accessible..."
    NIGHTSCOUT_READY=false
    
    for i in {1..24}; do
        sleep 5
        print_info "Checking Nightscout health... (attempt $i/24)"
        
        # Check if container is running
        if ! docker-compose ps nightscout | grep -q "Up"; then
            print_warning "Nightscout container is not running properly"
            print_info "Container status:"
            docker-compose ps nightscout
            continue
        fi
        
        # Check if port 8080 is accessible
        if curl -s -f "http://localhost:8080/api/v1/status" > /dev/null 2>&1; then
            print_status "Nightscout is now running and accessible on port 8080!"
            NIGHTSCOUT_READY=true
            break
        elif [ $i -eq 24 ]; then
            print_error "Nightscout failed to become ready after 2 minutes"
            print_info "Checking container logs:"
            docker-compose logs --tail=20 nightscout
            print_info "Checking container status:"
            docker-compose ps
            exit 1
        else
            print_info "Nightscout not ready yet, waiting... (${i}/24)"
        fi
    done
    
    if [ "$NIGHTSCOUT_READY" = true ]; then
        echo
        print_status "✅ Nightscout is fully operational!"
        print_info "🌐 Local access: http://localhost:8080"
        echo
        
        # Step 3: Setup Cloudflare tunnel
        print_info "Step 3: Setting up Cloudflare tunnel..."
        ./setup-cloudflare.sh --domain "$DOMAIN" --tunnel-name "$TUNNEL_NAME" --non-interactive
        
        if [ $? -eq 0 ]; then
            print_status "Cloudflare tunnel setup completed successfully!"
            echo
            echo "🎉 Full automated setup completed!"
            echo
            echo "🌐 Your Nightscout is now available at:"
            echo "   - Local: http://localhost:8080"
            echo "   - External: https://$DOMAIN"
        else
            print_error "Cloudflare tunnel setup failed"
            print_info "Nightscout is still running locally at: http://localhost:8080"
            print_info "You can setup the tunnel manually with: ./setup-cloudflare.sh"
        fi
    fi
else
    # Show next steps for manual setup
    echo
    echo "🎉 Setup completed successfully!"
    echo
    if [ -n "$DOMAIN" ]; then
        echo "🌐 Configured for domain: $DOMAIN"
        echo "🔧 Tunnel name: $TUNNEL_NAME"
        echo
        echo "Next steps:"
        echo "1. Set up Cloudflare tunnel: ./setup-cloudflare.sh --domain $DOMAIN --tunnel-name $TUNNEL_NAME"
        echo "2. Start Nightscout: docker-compose up -d"
        echo "3. Access at: https://$DOMAIN"
    else
        echo "Next steps:"
        echo "1. Review your .env file: cat .env"
        echo "2. Start Nightscout: docker-compose up -d"
        echo "3. Verify it's running: curl http://localhost:8080/api/v1/status"
        echo "4. For Cloudflare tunnel: ./setup-cloudflare.sh"
        echo "5. For Proxmox deployment: docker-compose -f docker-compose.proxmox.yml up -d"
        echo
        
        # Offer to start Nightscout and setup tunnel interactively
        if [ -n "$DOMAIN" ] && [ "$INTERACTIVE" = true ]; then
            echo "Would you like to start Nightscout now and setup the Cloudflare tunnel?"
            read -p "Start deployment? (Y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                echo
                print_info "🚀 Starting interactive deployment..."
                
                # Step 1: Start Docker
                print_info "Step 1: Starting Nightscout with Docker Compose..."
                if docker-compose up -d; then
                    print_status "Docker Compose started successfully"
                else
                    print_error "Failed to start Docker Compose"
                    print_info "Please check for port conflicts: docker-compose logs"
                    exit 1
                fi
                
                # Step 2: Wait and verify
                print_info "Step 2: Waiting for Nightscout to be ready..."
                NIGHTSCOUT_READY=false
                
                for i in {1..24}; do
                    sleep 5
                    print_info "Checking Nightscout health... (attempt $i/24)"
                    
                    if curl -s -f "http://localhost:8080/api/v1/status" > /dev/null 2>&1; then
                        print_status "✅ Nightscout is ready and accessible!"
                        NIGHTSCOUT_READY=true
                        break
                    elif [ $i -eq 24 ]; then
                        print_error "Nightscout failed to become ready after 2 minutes"
                        print_info "Check logs: docker-compose logs nightscout"
                        exit 1
                    fi
                done
                
                if [ "$NIGHTSCOUT_READY" = true ]; then
                    echo
                    print_status "🌐 Nightscout is running at: http://localhost:8080"
                    echo
                    read -p "Proceed with Cloudflare tunnel setup? (Y/n): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                        print_info "Step 3: Setting up Cloudflare tunnel..."
                        ./setup-cloudflare.sh --domain "$DOMAIN" --tunnel-name "$TUNNEL_NAME"
                    else
                        print_info "Cloudflare setup skipped. Run manually: ./setup-cloudflare.sh"
                    fi
                fi
            fi
        fi
    fi
    echo
    echo "⚠️  Security notes:"
    echo "- Keep your .env file secure and never commit it to version control"
    echo "- The generated secrets are secure but you can regenerate them if needed"
    echo "- Consider setting up a reverse proxy with SSL for production use"
    echo
    echo "📚 For more information, see README.md and DEPLOY.md"
fi 