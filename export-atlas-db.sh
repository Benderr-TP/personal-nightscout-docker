#!/bin/bash

# MongoDB Atlas Export Script for Nightscout Migration
# This script exports your Nightscout database from MongoDB Atlas

set -e

# Configuration
ATLAS_CONNECTION_STRING=""
DATABASE_NAME="nightscout"
EXPORT_DIR="./nightscout-export-$(date +%Y%m%d-%H%M%S)"
OPLOG_ENABLED=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --connection-string  MongoDB Atlas connection string"
    echo "  -d, --database           Database name (default: nightscout)"
    echo "  -o, --output-dir         Output directory for export"
    echo "  --oplog                  Include oplog for point-in-time consistency"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -c 'mongodb+srv://username:password@cluster.mongodb.net/' -d nightscout"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--connection-string)
            ATLAS_CONNECTION_STRING="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE_NAME="$2"
            shift 2
            ;;
        -o|--output-dir)
            EXPORT_DIR="$2"
            shift 2
            ;;
        --oplog)
            OPLOG_ENABLED=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$ATLAS_CONNECTION_STRING" ]; then
    echo -e "${RED}Error: Atlas connection string is required${NC}"
    echo "Please provide it with -c option or set ATLAS_CONNECTION_STRING environment variable"
    echo "Example: mongodb+srv://username:password@cluster0.xxxxx.mongodb.net/"
    exit 1
fi

# Validate connection string format for Atlas
if [[ ! "$ATLAS_CONNECTION_STRING" =~ mongodb\+srv:// ]]; then
    echo -e "${YELLOW}Warning: Connection string should use mongodb+srv:// for Atlas${NC}"
fi

# Check if mongodump is installed
if ! command -v mongodump &> /dev/null; then
    echo -e "${RED}Error: mongodump is not installed${NC}"
    echo "Please install MongoDB Database Tools: https://docs.mongodb.com/database-tools/installation/"
    exit 1
fi

echo -e "${GREEN}Starting MongoDB Atlas export...${NC}"
echo "Database: $DATABASE_NAME"
echo "Export directory: $EXPORT_DIR"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Export the database
echo -e "${YELLOW}Exporting database from Atlas...${NC}"
if [ "$OPLOG_ENABLED" = true ]; then
    echo "Using oplog for point-in-time consistency..."
    mongodump --uri="$ATLAS_CONNECTION_STRING" --db="$DATABASE_NAME" --oplog --out="$EXPORT_DIR"
else
    mongodump --uri="$ATLAS_CONNECTION_STRING" --db="$DATABASE_NAME" --out="$EXPORT_DIR"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Export completed successfully!${NC}"
    echo "Export location: $EXPORT_DIR"
    
    # Display export statistics
    if [ -d "$EXPORT_DIR/$DATABASE_NAME" ]; then
        echo "Collections exported:"
        ls -la "$EXPORT_DIR/$DATABASE_NAME" | grep -E '\.bson$' | wc -l | xargs echo "  Count:"
        du -sh "$EXPORT_DIR" | cut -f1 | xargs echo "  Total size:"
    fi
    
    echo ""
    echo "To import this data to your new Nightscout instance, use:"
    if [ "$OPLOG_ENABLED" = true ]; then
        echo "  ./import-to-vm.sh -d $EXPORT_DIR/$DATABASE_NAME -t mongodb://localhost:27017 --oplog"
    else
        echo "  ./import-to-vm.sh -d $EXPORT_DIR/$DATABASE_NAME -t mongodb://localhost:27017"
    fi
    
    echo ""
    echo -e "${YELLOW}Important: Nightscout connection string format:${NC}"
    echo "  MONGODB_URI=mongodb://username:password@your-server:27017/nightscout"
else
    echo -e "${RED}Export failed!${NC}"
    exit 1
fi