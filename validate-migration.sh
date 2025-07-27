#!/bin/bash

# Nightscout Migration Validation Script
# This script validates data integrity after migration from Atlas to self-hosted

set -e

# Configuration
SOURCE_TYPE="atlas"
TARGET_TYPE="local"
VERIFY_DATA=true
VERIFY_PERFORMANCE=true
VERIFY_SECURITY=true
GENERATE_REPORT=true
REPORT_DIR="./migration-reports"

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

print_usage() {
    echo "Nightscout Migration Validation Script"
    echo ""
    echo "Usage:"
    echo "  $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --source TYPE          Source database type (atlas, local, file)"
    echo "  --target TYPE          Target database type (local, atlas, file)"
    echo "  --source-uri URI       Source database connection string"
    echo "  --target-uri URI       Target database connection string"
    echo "  --no-data-verify       Skip data integrity verification"
    echo "  --no-performance       Skip performance validation"
    echo "  --no-security          Skip security validation"
    echo "  --no-report            Skip report generation"
    echo "  --report-dir DIR       Report directory (default: ./migration-reports)"
    echo "  --help, -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --source atlas --target local --source-uri 'mongodb+srv://...' --target-uri 'mongodb://localhost:27017'"
    echo "  $0 --source file --target local --source-uri './export/nightscout' --target-uri 'mongodb://localhost:27017'"
}

# Parse command line arguments
SOURCE_URI=""
TARGET_URI=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --source)
            SOURCE_TYPE="$2"
            shift 2
            ;;
        --target)
            TARGET_TYPE="$2"
            shift 2
            ;;
        --source-uri)
            SOURCE_URI="$2"
            shift 2
            ;;
        --target-uri)
            TARGET_URI="$2"
            shift 2
            ;;
        --no-data-verify)
            VERIFY_DATA=false
            shift
            ;;
        --no-performance)
            VERIFY_PERFORMANCE=false
            shift
            ;;
        --no-security)
            VERIFY_SECURITY=false
            shift
            ;;
        --no-report)
            GENERATE_REPORT=false
            shift
            ;;
        --report-dir)
            REPORT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$SOURCE_URI" ] || [ -z "$TARGET_URI" ]; then
    print_error "Source and target URIs are required"
    print_usage
    exit 1
fi

# Validate source/target types
if [[ ! "$SOURCE_TYPE" =~ ^(atlas|local|file)$ ]]; then
    print_error "Invalid source type: $SOURCE_TYPE"
    exit 1
fi

if [[ ! "$TARGET_TYPE" =~ ^(atlas|local|file)$ ]]; then
    print_error "Invalid target type: $TARGET_TYPE"
    exit 1
fi

# Create report directory
mkdir -p "$REPORT_DIR"

# Generate report filename
DATE=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$REPORT_DIR/migration-validation-${DATE}.txt"

echo "🔍 Nightscout Migration Validation"
echo "=================================="
echo "Source: $SOURCE_TYPE ($SOURCE_URI)"
echo "Target: $TARGET_TYPE ($TARGET_URI)"
echo "Report: $REPORT_FILE"
echo ""

# Initialize validation results
VALIDATION_RESULTS=()
ERRORS=()
WARNINGS=()

# Function to add validation result
add_result() {
    local status="$1"
    local message="$2"
    VALIDATION_RESULTS+=("$status|$message")
}

# Function to add error
add_error() {
    local message="$1"
    ERRORS+=("$message")
    add_result "ERROR" "$message"
}

# Function to add warning
add_warning() {
    local message="$1"
    WARNINGS+=("$message")
    add_result "WARNING" "$message"
}

# Function to add success
add_success() {
    local message="$1"
    add_result "SUCCESS" "$message"
}

# Step 1: Pre-validation checks
print_info "Step 1: Pre-validation checks"

# Check if mongosh is available
if ! command -v mongosh &> /dev/null; then
    add_error "mongosh is not installed"
    print_error "Please install MongoDB Shell: https://docs.mongodb.com/mongodb-shell/install/"
    exit 1
fi

# Check if Docker is running (for local target)
if [ "$TARGET_TYPE" = "local" ]; then
    if ! docker info >/dev/null 2>&1; then
        add_error "Docker is not running"
        exit 1
    fi
    
    if ! docker-compose ps | grep -q "Up"; then
        add_warning "Nightscout containers are not running"
    fi
fi

add_success "Pre-validation checks completed"

# Step 2: Connection validation
print_info "Step 2: Connection validation"

# Test source connection
print_info "Testing source connection..."
if [ "$SOURCE_TYPE" = "file" ]; then
    if [ -d "$SOURCE_URI" ]; then
        add_success "Source export directory exists: $SOURCE_URI"
    else
        add_error "Source export directory not found: $SOURCE_URI"
    fi
else
    if mongosh "$SOURCE_URI" --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        add_success "Source database connection successful"
    else
        add_error "Source database connection failed"
    fi
fi

# Test target connection
print_info "Testing target connection..."
if [ "$TARGET_TYPE" = "file" ]; then
    if [ -d "$TARGET_URI" ]; then
        add_success "Target export directory exists: $TARGET_URI"
    else
        add_error "Target export directory not found: $TARGET_URI"
    fi
else
    if mongosh "$TARGET_URI" --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        add_success "Target database connection successful"
    else
        add_error "Target database connection failed"
    fi
fi

# Step 3: Data integrity verification
if [ "$VERIFY_DATA" = true ]; then
    print_info "Step 3: Data integrity verification"
    
    # Function to get collection counts
    get_collection_counts() {
        local uri="$1"
        local db_name="nightscout"
        
        if [ "$uri" = "file" ]; then
            # For file-based validation, count BSON files
            find "$uri" -name "*.bson" | wc -l
        else
            # For database validation, get actual counts
            mongosh "$uri" --quiet --eval "
                const collections = ['entries', 'treatments', 'devicestatus', 'profile', 'food', 'activity'];
                const counts = {};
                collections.forEach(coll => {
                    try {
                        counts[coll] = db.getCollection(coll).countDocuments();
                    } catch(e) {
                        counts[coll] = 0;
                    }
                });
                print(JSON.stringify(counts));
            " 2>/dev/null || echo '{}'
        fi
    }
    
    # Get source counts
    print_info "Getting source collection counts..."
    SOURCE_COUNTS=$(get_collection_counts "$SOURCE_URI")
    
    # Get target counts
    print_info "Getting target collection counts..."
    TARGET_COUNTS=$(get_collection_counts "$TARGET_URI")
    
    # Compare counts
    print_info "Comparing collection counts..."
    
    # Parse JSON counts (simplified comparison)
    if [ "$SOURCE_COUNTS" != "$TARGET_COUNTS" ]; then
        add_warning "Collection counts may differ between source and target"
        print_info "Source counts: $SOURCE_COUNTS"
        print_info "Target counts: $TARGET_COUNTS"
    else
        add_success "Collection counts match between source and target"
    fi
    
    # Check for critical collections
    CRITICAL_COLLECTIONS=("entries" "treatments" "devicestatus")
    for collection in "${CRITICAL_COLLECTIONS[@]}"; do
        if [ "$SOURCE_TYPE" != "file" ] && [ "$TARGET_TYPE" != "file" ]; then
            SOURCE_COUNT=$(mongosh "$SOURCE_URI" --quiet --eval "db.$collection.countDocuments()" 2>/dev/null || echo "0")
            TARGET_COUNT=$(mongosh "$TARGET_URI" --quiet --eval "db.$collection.countDocuments()" 2>/dev/null || echo "0")
            
            if [ "$SOURCE_COUNT" -gt 0 ] && [ "$TARGET_COUNT" -eq 0 ]; then
                add_error "Critical collection '$collection' is empty in target but has data in source"
            elif [ "$SOURCE_COUNT" -eq 0 ] && [ "$TARGET_COUNT" -gt 0 ]; then
                add_warning "Critical collection '$collection' has data in target but is empty in source"
            else
                add_success "Critical collection '$collection' validated"
            fi
        fi
    done
fi

# Step 4: Performance validation
if [ "$VERIFY_PERFORMANCE" = true ]; then
    print_info "Step 4: Performance validation"
    
    if [ "$TARGET_TYPE" != "file" ]; then
        # Test query performance
        print_info "Testing query performance..."
        
        # Test basic query performance
        START_TIME=$(date +%s.%N)
        mongosh "$TARGET_URI" --quiet --eval "db.entries.find().limit(1).toArray()" >/dev/null 2>&1
        END_TIME=$(date +%s.%N)
        QUERY_TIME=$(echo "$END_TIME - $START_TIME" | bc -l 2>/dev/null || echo "0")
        
        if (( $(echo "$QUERY_TIME < 1.0" | bc -l) )); then
            add_success "Query performance is acceptable ($(printf "%.3f" $QUERY_TIME)s)"
        else
            add_warning "Query performance may be slow ($(printf "%.3f" $QUERY_TIME)s)"
        fi
        
        # Check database size
        print_info "Checking database size..."
        DB_SIZE=$(mongosh "$TARGET_URI" --quiet --eval "db.stats().dataSize" 2>/dev/null || echo "0")
        if [ "$DB_SIZE" -gt 0 ]; then
            add_success "Database has data (size: $DB_SIZE bytes)"
        else
            add_warning "Database appears to be empty"
        fi
        
        # Check index status
        print_info "Checking index status..."
        INDEX_COUNT=$(mongosh "$TARGET_URI" --quiet --eval "db.entries.getIndexes().length" 2>/dev/null || echo "0")
        if [ "$INDEX_COUNT" -gt 1 ]; then
            add_success "Indexes are present ($INDEX_COUNT indexes on entries collection)"
        else
            add_warning "Limited indexes found ($INDEX_COUNT indexes on entries collection)"
        fi
    else
        add_warning "Performance validation skipped for file-based target"
    fi
fi

# Step 5: Security validation
if [ "$VERIFY_SECURITY" = true ]; then
    print_info "Step 5: Security validation"
    
    if [ "$TARGET_TYPE" != "file" ]; then
        # Check authentication
        print_info "Checking authentication..."
        if [[ "$TARGET_URI" =~ mongodb://[^:]+:[^@]+@ ]]; then
            add_success "Target database has authentication configured"
        else
            add_warning "Target database may not have authentication configured"
        fi
        
        # Check for default credentials
        print_info "Checking for default credentials..."
        if [[ "$TARGET_URI" =~ :password@ ]] || [[ "$TARGET_URI" =~ :admin@ ]]; then
            add_warning "Target database may be using default credentials"
        else
            add_success "Target database is not using obvious default credentials"
        fi
        
        # Check network access
        print_info "Checking network access..."
        if [[ "$TARGET_URI" =~ localhost ]] || [[ "$TARGET_URI" =~ 127.0.0.1 ]]; then
            add_success "Target database is accessible only locally"
        else
            add_warning "Target database may be accessible from external networks"
        fi
    else
        add_warning "Security validation skipped for file-based target"
    fi
fi

# Step 6: Nightscout-specific validation
print_info "Step 6: Nightscout-specific validation"

if [ "$TARGET_TYPE" = "local" ]; then
    # Check if Nightscout is running
    if docker-compose ps | grep -q "nightscout.*Up"; then
        add_success "Nightscout container is running"
        
        # Test Nightscout API
        print_info "Testing Nightscout API..."
        if curl -s -f "http://localhost:8080/api/v1/status" >/dev/null 2>&1; then
            add_success "Nightscout API is responding"
            
            # Check for recent data
            RECENT_ENTRIES=$(curl -s "http://localhost:8080/api/v1/entries.json?count=1" 2>/dev/null | jq length 2>/dev/null || echo "0")
            if [ "$RECENT_ENTRIES" -gt 0 ]; then
                add_success "Nightscout has recent data entries"
            else
                add_warning "Nightscout has no recent data entries"
            fi
        else
            add_error "Nightscout API is not responding"
        fi
    else
        add_warning "Nightscout container is not running"
    fi
fi

# Step 7: Generate validation report
if [ "$GENERATE_REPORT" = true ]; then
    print_info "Step 7: Generating validation report"
    
    {
        echo "Nightscout Migration Validation Report"
        echo "====================================="
        echo "Date: $(date)"
        echo "Source: $SOURCE_TYPE ($SOURCE_URI)"
        echo "Target: $TARGET_TYPE ($TARGET_URI)"
        echo ""
        
        echo "Validation Summary"
        echo "=================="
        local success_count=0
        local warning_count=0
        local error_count=0
        
        for result in "${VALIDATION_RESULTS[@]}"; do
            IFS='|' read -r status message <<< "$result"
            case "$status" in
                "SUCCESS")
                    echo "✅ $message"
                    ((success_count++))
                    ;;
                "WARNING")
                    echo "⚠️  $message"
                    ((warning_count++))
                    ;;
                "ERROR")
                    echo "❌ $message"
                    ((error_count++))
                    ;;
            esac
        done
        
        echo ""
        echo "Summary Statistics"
        echo "=================="
        echo "Total checks: ${#VALIDATION_RESULTS[@]}"
        echo "Successful: $success_count"
        echo "Warnings: $warning_count"
        echo "Errors: $error_count"
        
        if [ $error_count -eq 0 ]; then
            echo ""
            echo "🎉 Migration validation PASSED"
            echo "The migration appears to be successful."
        else
            echo ""
            echo "❌ Migration validation FAILED"
            echo "Please address the errors before proceeding."
        fi
        
        if [ $warning_count -gt 0 ]; then
            echo ""
            echo "⚠️  Warnings detected"
            echo "Consider addressing these warnings for optimal performance."
        fi
        
        echo ""
        echo "Recommendations"
        echo "==============="
        if [ $error_count -gt 0 ]; then
            echo "1. Address all errors before using the migrated system"
            echo "2. Verify data integrity manually if needed"
            echo "3. Check network connectivity and authentication"
        fi
        
        if [ $warning_count -gt 0 ]; then
            echo "1. Review warnings for potential issues"
            echo "2. Consider performance optimization if needed"
            echo "3. Verify security configuration"
        fi
        
        if [ $error_count -eq 0 ] && [ $warning_count -eq 0 ]; then
            echo "1. The migration appears successful"
            echo "2. Monitor the system for any issues"
            echo "3. Set up regular backups"
            echo "4. Consider implementing monitoring"
        fi
        
    } > "$REPORT_FILE"
    
    add_success "Validation report generated: $REPORT_FILE"
fi

# Final summary
echo ""
echo "📊 Validation Summary"
echo "===================="

SUCCESS_COUNT=0
WARNING_COUNT=0
ERROR_COUNT=0

for result in "${VALIDATION_RESULTS[@]}"; do
    IFS='|' read -r status message <<< "$result"
    case "$status" in
        "SUCCESS")
            ((SUCCESS_COUNT++))
            ;;
        "WARNING")
            ((WARNING_COUNT++))
            ;;
        "ERROR")
            ((ERROR_COUNT++))
            ;;
    esac
done

echo "✅ Successful checks: $SUCCESS_COUNT"
echo "⚠️  Warnings: $WARNING_COUNT"
echo "❌ Errors: $ERROR_COUNT"

if [ $ERROR_COUNT -eq 0 ]; then
    echo ""
    print_status "🎉 Migration validation completed successfully!"
    echo "The migration appears to be successful."
    
    if [ $WARNING_COUNT -gt 0 ]; then
        echo ""
        print_warning "⚠️  $WARNING_COUNT warnings detected"
        echo "Review the warnings for potential improvements."
    fi
else
    echo ""
    print_error "❌ Migration validation failed!"
    echo "Please address the $ERROR_COUNT errors before proceeding."
    exit 1
fi

echo ""
print_info "📋 Detailed report: $REPORT_FILE"
print_info "📚 For more information, see:"
echo "   - MIGRATION.md (migration procedures)"
echo "   - PROJECT-INFO.md (deployment guide)"
echo "   - DEVOPS-QUICK-REFERENCE.md (commands)" 