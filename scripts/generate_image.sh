#!/bin/bash

set -e

API_KEY="${GLM_API_KEY}"
API_URL="https://api.z.ai/api/paas/v4/images/generations"
MODEL="cogView-4-250304"
SIZE="1024x1024"

show_usage() {
    echo "Usage: $0 [OPTIONS] \"your text prompt\""
    echo ""
    echo "Options:"
    echo "  -s, --size SIZE    Image size (default: 1024x1024)"
    echo "  -m, --model MODEL  Model to use (default: cogView-4-250304)"
    echo "  -o, --output FILE  Output filename (default: generated_image.png)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 \"A cute cat sitting on a windowsill\""
    echo "  $0 -s 512x512 -o my_image.png \"Sunset over mountains\""
    echo ""
}

show_error() {
    echo "Error: $1" >&2
    exit 1
}

check_dependencies() {
    if ! command -v curl >/dev/null 2>&1; then
        show_error "curl is required but not installed"
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        show_error "jq is required but not installed"
    fi
}

validate_size() {
    local size="$1"
    case "$size" in
        1024x1024|1024x768|768x1024|512x512|768x768|768x512|512x768)
            return 0
            ;;
        *)
            show_error "Invalid size. Supported sizes: 1024x1024, 1024x768, 768x1024, 512x512, 768x768, 768x512, 512x768"
            ;;
    esac
}

OUTPUT_FILE="generated_image.png"

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--size)
            SIZE="$2"
            validate_size "$SIZE"
            shift 2
            ;;
        -m|--model)
            MODEL="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            show_error "Unknown option: $1"
            ;;
        *)
            PROMPT="$1"
            shift
            ;;
    esac
done

if [[ -z "$PROMPT" ]]; then
    show_error "Text prompt is required"
fi

if [[ -z "$API_KEY" ]]; then
    show_error "GLM_API_KEY environment variable is not set"
fi

echo "Generating image with prompt: \"$PROMPT\""
echo "Model: $MODEL"
echo "Size: $SIZE"
echo "Output: $OUTPUT_FILE"
echo ""

response=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "{
        \"model\": \"$MODEL\",
        \"prompt\": \"$PROMPT\",
        \"size\": \"$SIZE\"
    }")

if echo "$response" | jq -e '.error' >/dev/null; then
    error_msg=$(echo "$response" | jq -r '.error.message // .error')
    show_error "API error: $error_msg"
fi

image_url=$(echo "$response" | jq -r '.data[0].url // empty')

if [[ -z "$image_url" || "$image_url" == "null" ]]; then
    show_error "No image URL found in response"
fi

echo "Downloading image from: $image_url"

if curl -s -L -o "$OUTPUT_FILE" "$image_url"; then
    echo "Image saved successfully to: $OUTPUT_FILE"
    
    if [[ $(command -v file >/dev/null 2>&1) ]]; then
        file_type=$(file -b --mime-type "$OUTPUT_FILE")
        file_size=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
        echo "File type: $file_type"
        echo "File size: $file_size bytes"
    fi
else
    show_error "Failed to download image"
fi