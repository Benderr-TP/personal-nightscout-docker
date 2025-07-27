#!/bin/bash

# Nightscout Setup Script
# This script helps configure Nightscout for deployment

set -e

echo "🔧 Nightscout Setup Script"
echo "=========================="

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

# Check for required commands
if ! command -v openssl >/dev/null 2>&1; then
    print_error "openssl is required but not installed. Please install openssl and rerun the script."
    exit 1
fi
if ! command -v sed >/dev/null 2>&1; then
    print_error "sed is required but not installed. Please install sed and rerun the script."
    exit 1
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

# Ask for timezone
print_info "Setting timezone..."
read -p "Enter your timezone (e.g., America/New_York, Europe/London): " TZ
if [ ! -z "$TZ" ]; then
    sed -i.bak "s|TZ=.*|TZ=$TZ|" .env
    print_status "Set timezone to $TZ"
fi

# Ask for display units
print_info "Setting display units..."
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

# Ask for custom title
print_info "Setting custom title..."
read -p "Enter custom title for your Nightscout site: " CUSTOM_TITLE
if [ ! -z "$CUSTOM_TITLE" ]; then
    sed -i.bak "s|CUSTOM_TITLE=.*|CUSTOM_TITLE=$CUSTOM_TITLE|" .env
    print_status "Set custom title to '$CUSTOM_TITLE'"
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

# Show next steps
echo
echo "🎉 Setup completed successfully!"
echo
echo "Next steps:"
echo "1. Review your .env file: cat .env"
echo "2. For local development: docker-compose up -d"
echo "3. For Proxmox deployment: docker-compose -f docker-compose.proxmox.yml up -d"
echo
echo "⚠️  Security notes:"
echo "- Keep your .env file secure and never commit it to version control"
echo "- The generated secrets are secure but you can regenerate them if needed"
echo "- Consider setting up a reverse proxy with SSL for production use"
echo
echo "📚 For more information, see README.md and DEPLOY.md" 