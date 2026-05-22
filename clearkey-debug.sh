#!/bin/bash

# ClearKey DRM Debugging Script
# Usage: ./clearkey-debug.sh [action]
# Actions: logs, verify, test, clean

set -e

LOG_TAG="ClearKey Debug"
PACKAGE="com.ayubu.supasoka"

print_header() {
    echo ""
    echo "=================================="
    echo "$1"
    echo "=================================="
    echo ""
}

print_success() {
    echo "✅ $1"
}

print_error() {
    echo "❌ $1"
}

print_info() {
    echo "ℹ️  $1"
}

action_logs() {
    print_header "ClearKey DRM Logs"
    print_info "Capturing logs with ExoPlayerEngine and DRM tags..."
    echo "Press Ctrl+C to stop"
    sleep 1
    adb logcat -v time ExoPlayerEngine:D ExoPlayerImplInternal:D RobustClearKeyCallback:D ManifestInterceptor:D MediaDrm:E MediaCodec:E AndroidRuntime:E *:S
}

action_verify() {
    print_header "Device Capability Verification"
    
    print_info "Checking MediaCodec support..."
    adb shell dumpsys media_codec 2>/dev/null | grep -E "clearkey|ClearKey" && print_success "ClearKey support found" || print_error "ClearKey not found in MediaCodec list"
    
    print_info "Checking MediaDrm providers..."
    adb shell dumpsys media.metrics 2>/dev/null | grep -i "drm" || print_info "DRM metrics not available (normal on older devices)"
    
    print_success "Device verification complete"
}

action_test() {
    print_header "ClearKey Stream Test"
    
    if [ -z "$1" ]; then
        print_error "Stream URL required: $0 test <mpd_url>"
        exit 1
    fi
    
    MPD_URL="$1"
    print_info "Testing stream: $MPD_URL"
    
    # Test network connectivity
    print_info "Testing network connectivity..."
    curl -I -s -m 5 "$MPD_URL" > /tmp/curl_test.txt 2>&1
    HTTP_CODE=$(head -1 /tmp/curl_test.txt | awk '{print $2}')
    
    case $HTTP_CODE in
        200)
            print_success "Manifest accessible (HTTP 200)"
            ;;
        404)
            print_error "Manifest not found (HTTP 404) - Check URL"
            ;;
        403)
            print_error "Access forbidden (HTTP 403) - May need authentication headers"
            ;;
        *)
            print_error "Unexpected HTTP code: $HTTP_CODE"
            ;;
    esac
    
    # Try to download manifest for analysis
    print_info "Downloading manifest for analysis..."
    curl -s "$MPD_URL" > /tmp/manifest.mpd 2>/dev/null || print_error "Failed to download manifest"
    
    if [ -f /tmp/manifest.mpd ]; then
        SIZE=$(wc -c < /tmp/manifest.mpd)
        print_info "Manifest size: $SIZE bytes"
        
        # Check if it looks like XML
        if head -c 100 /tmp/manifest.mpd | grep -q "<?xml\|<MPD"; then
            print_success "Manifest appears to be valid XML"
            print_info "First few lines:"
            head -5 /tmp/manifest.mpd | sed 's/^/  /'
        else
            print_error "Manifest doesn't look like XML - may be encrypted"
        fi
    fi
}

action_clean() {
    print_header "Cleaning ClearKey Data"
    
    print_info "Clearing app cache and data..."
    adb shell pm clear "$PACKAGE" 2>/dev/null || print_error "Failed to clear app data"
    print_success "App cache cleared"
    
    print_info "Clearing MediaDrm data..."
    adb shell rm -rf /data/misc/mediadrm 2>/dev/null || print_info "MediaDrm folder not accessible or doesn't exist"
    print_success "MediaDrm data cleared"
    
    print_success "Clean complete - app will re-initialize on next launch"
}

action_help() {
    print_header "ClearKey Debug Tool - Help"
    cat << 'EOF'
Commands:
  logs      - Show live ClearKey/DRM logs
  verify    - Check device ClearKey capabilities
  test URL  - Test manifest URL connectivity
  clean     - Clear app cache and MediaDrm data
  help      - Show this help message

Examples:
  ./clearkey-debug.sh logs
  ./clearkey-debug.sh verify
  ./clearkey-debug.sh test "https://example.com/stream.mpd"
  ./clearkey-debug.sh clean

What to look for in logs:
  SUCCESS:
    ✅ "🔐 Pre-loading ClearKey DRM session..."
    ✅ "🔑 Building ClearKey JSON with X key(s)"
    ✅ "✅ ClearKey DRM session pre-loaded"
    ✅ No "Crypto key not available" errors
  
  ERRORS:
    ❌ "HTTP 404" - Wrong URL
    ❌ "HTTP 403" - Auth issue
    ❌ "Crypto key not available" - Bad kid/k values
    ❌ "Invalid ClearKey #0" - Malformed keys

Key Validation:
  - kid and k must be base64url-encoded (no padding)
  - Both must be 16 bytes after decoding (128-bit)
  - No "=" padding characters allowed
  - Valid chars: [a-z][A-Z][0-9]-_

Common Issues:
  1. HTTP 404: Verify stream URL is correct
  2. HTTP 403: Check if auth headers are needed
  3. Crypto key not available: Verify kid/k format
  4. Media won't play: Try clearing app data first
EOF
}

# Main
case "${1:-help}" in
    logs)
        action_logs
        ;;
    verify)
        action_verify
        ;;
    test)
        action_test "$2"
        ;;
    clean)
        action_clean
        ;;
    help)
        action_help
        ;;
    *)
        print_error "Unknown command: $1"
        action_help
        exit 1
        ;;
esac
