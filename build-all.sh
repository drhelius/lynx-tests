#!/bin/bash

# Build all tests script
# Usage: ./build-all.sh [clean|rebuild]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test directories
TESTS=(
    "audio"
    "audio2"
    "cpu"
    "math"
    "memio"
    "timers"
    "uart"
    "uart2"
)

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Parse command line arguments
ACTION="${1:-build}"

build_test() {
    local test_dir=$1
    echo -e "${YELLOW}Building ${test_dir}...${NC}"
    
    if [ ! -d "$SCRIPT_DIR/$test_dir" ]; then
        echo -e "${RED}Error: Directory $test_dir not found${NC}"
        return 1
    fi
    
    if [ ! -f "$SCRIPT_DIR/$test_dir/Makefile" ]; then
        echo -e "${RED}Error: Makefile not found in $test_dir${NC}"
        return 1
    fi
    
    cd "$SCRIPT_DIR/$test_dir"
    make -f "$SCRIPT_DIR/$test_dir/Makefile"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ ${test_dir} built successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ ${test_dir} build failed${NC}"
        return 1
    fi
}

clean_test() {
    local test_dir=$1
    echo -e "${YELLOW}Cleaning ${test_dir}...${NC}"
    
    if [ ! -d "$SCRIPT_DIR/$test_dir" ]; then
        echo -e "${RED}Error: Directory $test_dir not found${NC}"
        return 1
    fi
    
    if [ ! -f "$SCRIPT_DIR/$test_dir/Makefile" ]; then
        echo -e "${RED}Error: Makefile not found in $test_dir${NC}"
        return 1
    fi
    
    cd "$SCRIPT_DIR/$test_dir"
    make -f "$SCRIPT_DIR/$test_dir/Makefile" clean
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ ${test_dir} cleaned successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ ${test_dir} clean failed${NC}"
        return 1
    fi
}

# Main execution
echo "=========================================="
echo "Building all Lynx tests"
echo "=========================================="
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_TESTS=()

if [ "$ACTION" == "clean" ]; then
    # Clean all tests
    for test in "${TESTS[@]}"; do
        if clean_test "$test"; then
            ((SUCCESS_COUNT++))
        else
            ((FAIL_COUNT++))
            FAILED_TESTS+=("$test")
        fi
        echo ""
    done
elif [ "$ACTION" == "rebuild" ]; then
    # Clean and build all tests
    for test in "${TESTS[@]}"; do
        if clean_test "$test" && build_test "$test"; then
            ((SUCCESS_COUNT++))
        else
            ((FAIL_COUNT++))
            FAILED_TESTS+=("$test")
        fi
        echo ""
    done
else
    # Just build all tests
    for test in "${TESTS[@]}"; do
        if build_test "$test"; then
            ((SUCCESS_COUNT++))
        else
            ((FAIL_COUNT++))
            FAILED_TESTS+=("$test")
        fi
        echo ""
    done
fi

# Summary
echo "=========================================="
echo "Build Summary"
echo "=========================================="
echo -e "${GREEN}Successful: ${SUCCESS_COUNT}${NC}"
echo -e "${RED}Failed: ${FAIL_COUNT}${NC}"

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    for test in "${FAILED_TESTS[@]}"; do
        echo -e "  ${RED}✗ ${test}${NC}"
    done
    exit 1
else
    echo -e "\n${GREEN}All tests built successfully!${NC}"
    exit 0
fi
