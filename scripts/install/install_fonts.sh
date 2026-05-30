#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ENV_DIR="$(dirname "$SCRIPT_DIR")"
source "$ENV_DIR/functions/common_funcs"

command -v fc-cache >/dev/null 2>&1 || error "fc-cache is required but not installed"

# Ensure fonts directory exists
FONT_DIR="${HOME:-$(cd ~ && pwd)}/.local/share/fonts"
mkdir -p "$FONT_DIR" || error "Failed to create $FONT_DIR"

# Count for installed, skipped and failed fonts
INSTALLED=0
SKIPPED=0
FAILED=0

info "Installing fonts..."

# Source fonts directory
FONTS_SRC="${ENV_DIR}/local/share/fonts"

# Check if fonts directory exists and is not empty
if [ ! -d "$FONTS_SRC" ]; then
    info "No fonts directory at $FONTS_SRC, skipping font installation"
    exit 0
fi

# Check if any .ttf files exist using find
if ! find "$FONTS_SRC" -maxdepth 1 -name "*.ttf" -print -quit | grep -q .; then
    info "No .ttf files found in $FONTS_SRC, skipping font installation"
    exit 0
fi

# Process each .ttf file using find and while read
find "$FONTS_SRC" -maxdepth 1 -name "*.ttf" -print0 | while read -r -d $'\0' font; do
    basename=$(basename "$font")
    if [ -f "$FONT_DIR/$basename" ]; then
        info "Skipping $basename (already installed)"
        SKIPPED=$((SKIPPED + 1))
    else
        if cp "$font" "$FONT_DIR/" 2>/dev/null; then
            success "Installed $basename"
            INSTALLED=$((INSTALLED + 1))
        else
            warning "Failed to install $basename"
            FAILED=$((FAILED + 1))
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
echo -e "${GREEN}Successfully installed: $INSTALLED${NC}"
echo -e "${YELLOW}Already present: $SKIPPED${NC}"
echo -e "${RED}Failed to install: $FAILED${NC}"
echo "-------------------"
echo "Total processed: $((INSTALLED + SKIPPED + FAILED))"
echo
