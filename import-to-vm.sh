#!/bin/bash

# MongoDB Import Script for Nightscout Migration
# This script imports your Nightscout database to a new MongoDB instance

set -e

# Configuration
TARGET_CONNECTION_STRING=""
DATABASE_NAME="nightscout"
IMPORT_DIR=""
DROP_EXISTING=false
OPLOG_REPLAY=false
NUM_PARALLEL_COLLECTIONS=4
NUM_INSERTION_WORKERS=4

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --data-dir           Directory containing exported MongoDB data"
    echo "  -t, --target             Target MongoDB connection string"
    echo "  -n, --database           Database name (default: nightscout)"
    echo "  --drop                   Drop existing database before import"
    echo "  --oplog                  Replay oplog for point-in-time consistency"
    echo "  --parallel NUM           Number of parallel collections (default: 4)"
    echo "  --workers NUM            Number of insertion workers per collection (default: 4)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Import to local MongoDB"
    echo "  $0 -d ./nightscout-export-20240127/nightscout -t mongodb://localhost:27017"
    echo ""
    echo "  # Import to MongoDB with authentication"
    echo "  $0 -d ./export/nightscout -t mongodb://user:pass@localhost:27017/nightscout"
    echo ""
    echo "  # Drop existing database before import"
    echo "  $0 -d ./export/nightscout -t mongodb://localhost:27017 --drop"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--data-dir)
            IMPORT_DIR="$2"
            shift 2
            ;;
        -t|--target)
            TARGET_CONNECTION_STRING="$2"
            shift 2
            ;;
        -n|--database)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --drop)
            DROP_EXISTING=true
            shift
            ;;
        --oplog)
            OPLOG_REPLAY=true
            shift
            ;;
        --parallel)
            NUM_PARALLEL_COLLECTIONS="$2"
            shift 2
            ;;
        --workers)
            NUM_INSERTION_WORKERS="$2"
            shift 2
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
if [ -z "$IMPORT_DIR" ]; then
    echo -e "${RED}Error: Import directory is required${NC}"
    print_usage
    exit 1
fi

if [ -z "$TARGET_CONNECTION_STRING" ]; then
    echo -e "${RED}Error: Target connection string is required${NC}"
    print_usage
    exit 1
fi

# Check if import directory exists
if [ ! -d "$IMPORT_DIR" ]; then
    echo -e "${RED}Error: Import directory does not exist: $IMPORT_DIR${NC}"
    exit 1
fi

# Validate connection string format
if [[ "$TARGET_CONNECTION_STRING" =~ mongodb\+srv:// ]]; then
    echo -e "${YELLOW}Note: Using mongodb+srv:// format (Atlas or cloud)${NC}"
elif [[ "$TARGET_CONNECTION_STRING" =~ mongodb:// ]]; then
    echo -e "${GREEN}Using standard mongodb:// format (self-hosted)${NC}"
else
    echo -e "${RED}Error: Invalid connection string format${NC}"
    echo "Use: mongodb://username:password@host:port/database or mongodb+srv://..."
    exit 1
fi

# Check for oplog directory if oplog replay is requested
if [ "$OPLOG_REPLAY" = true ]; then
    OPLOG_DIR="$(dirname "$IMPORT_DIR")/oplog.bson"
    if [ ! -f "$OPLOG_DIR" ]; then
        echo -e "${RED}Error: Oplog file not found: $OPLOG_DIR${NC}"
        echo "Oplog replay requires export with --oplog option"
        exit 1
    fi
fi

# Check if mongorestore is installed
if ! command -v mongorestore &> /dev/null; then
    echo -e "${RED}Error: mongorestore is not installed${NC}"
    echo "Please install MongoDB Database Tools: https://docs.mongodb.com/database-tools/installation/"
    exit 1
fi

echo -e "${GREEN}Starting MongoDB import...${NC}"
echo "Import directory: $IMPORT_DIR"
echo "Target database: $DATABASE_NAME"
echo "Target connection: $TARGET_CONNECTION_STRING"
echo "Parallel collections: $NUM_PARALLEL_COLLECTIONS"
echo "Insertion workers: $NUM_INSERTION_WORKERS"
if [ "$OPLOG_REPLAY" = true ]; then
    echo "Oplog replay: enabled"
fi

# Build mongorestore command with performance optimizations
RESTORE_CMD="mongorestore --uri=\"$TARGET_CONNECTION_STRING\" --db=\"$DATABASE_NAME\""
RESTORE_CMD="$RESTORE_CMD --numParallelCollections=$NUM_PARALLEL_COLLECTIONS"
RESTORE_CMD="$RESTORE_CMD --numInsertionWorkersPerCollection=$NUM_INSERTION_WORKERS"

if [ "$DROP_EXISTING" = true ]; then
    echo -e "${YELLOW}Dropping existing database and importing...${NC}"
    RESTORE_CMD="$RESTORE_CMD --drop"
else
    echo -e "${YELLOW}Importing database (existing data will be preserved)...${NC}"
fi

if [ "$OPLOG_REPLAY" = true ]; then
    echo "Applying oplog for point-in-time consistency..."
    RESTORE_CMD="$RESTORE_CMD --oplogReplay"
fi

RESTORE_CMD="$RESTORE_CMD --dir=\"$IMPORT_DIR\""

# Execute the restore command
eval $RESTORE_CMD

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Import completed successfully!${NC}"
    
    # Display import statistics
    echo ""
    echo -e "${GREEN}Import Summary:${NC}"
    echo "Database: $DATABASE_NAME"
    
    echo ""
    echo -e "${YELLOW}Next steps for Nightscout configuration:${NC}"
    echo "1. Update your Nightscout environment variables:"
    
    # Extract components for proper MONGODB_URI format
    if [[ "$TARGET_CONNECTION_STRING" =~ mongodb://([^@]+@)?([^/]+)(/.*)? ]]; then
        HOST_PART="${BASH_REMATCH[2]}"
        AUTH_PART="${BASH_REMATCH[1]}"
        if [ -n "$AUTH_PART" ]; then
            echo "   MONGODB_URI=mongodb://${AUTH_PART}${HOST_PART}/$DATABASE_NAME"
        else
            echo "   MONGODB_URI=mongodb://${HOST_PART}/$DATABASE_NAME"
        fi
    else
        echo "   MONGODB_URI=$TARGET_CONNECTION_STRING/$DATABASE_NAME"
    fi
    
    echo "2. Restart your Nightscout application"
    echo "3. Test database connectivity and verify historical data"
    echo "4. Check Nightscout logs for any connection issues"
    
    echo ""
    echo -e "${YELLOW}Nightscout-specific notes:${NC}"
    echo "- Ensure API_SECRET is properly configured"
    echo "- Add 'dbsize' to ENABLE variable to monitor database size"
    echo "- Free MongoDB instances have 512MB limits"
    
else
    echo -e "${RED}Import failed!${NC}"
    echo "Check MongoDB logs and connection string format"
    exit 1
fi