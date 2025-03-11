#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

set -euo pipefail

# Print error message
error() {
    local fatal=${2:-0}
    echo -e "${RED}Error: $1${NC}" >&2
    if [ "$fatal" -eq 1 ]; then
        exit 1
    fi
    return 1
}

# Print success message
success() {
    echo -e "${GREEN}$1${NC}"
}

# Print info message
info() {
    echo -e "${YELLOW}$1${NC}"
}

# Check if required commands exist
command -v fc-cache >/dev/null 2>&1 || error "fc-cache is required but not installed"

# Ensure fonts directory exists
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR" || error "Failed to create $FONT_DIR"

# Count for installed, skipped and failed fonts
installed=0
skipped=0
failed=0

info "Installing fonts..."

# Check if fonts directory exists and is not empty
if [ ! -d "./fonts" ]; then
    error "The ./fonts directory does not exist" 1
fi

# Check if any .ttf files exist using find
if ! find "./fonts" -maxdepth 1 -name "*.ttf" -print -quit | grep -q .; then
    error "No .ttf files found in ./fonts directory" 1
fi

# Process each .ttf file using find and while read
find "./fonts" -maxdepth 1 -name "*.ttf" -print0 | while read -r -d $'\0' font; do
    basename=$(basename "$font")
    if [ -f "$FONT_DIR/$basename" ]; then
        info "Skipping $basename (already installed)"
        ((skipped++)) || true
    else
        if cp "$font" "$FONT_DIR/" 2>/dev/null; then
            success "Installed $basename"
            ((installed++)) || true
        else
            error "Failed to install $basename" 0
            ((failed++)) || true
        fi
    fi
done

# Update font cache
info "Updating font cache..."
if fc-cache -f -v; then
    success "Font cache updated successfully"
else
    error "Failed to update font cache"
fi

# Print final summary
echo
echo "Installation Summary:"
echo "-------------------"
echo -e "${GREEN}Successfully installed: $installed${NC}"
echo -e "${YELLOW}Already present: $skipped${NC}"
echo -e "${RED}Failed to install: $failed${NC}"
echo "-------------------"
echo "Total processed: $((installed + skipped + failed))"
echo
