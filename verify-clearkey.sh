#!/bin/bash

# ClearKey kid/k Format Validator
# Verifies if kid and k are properly formatted base64url-encoded values

print_header() {
    echo ""
    echo "======================================"
    echo "$1"
    echo "======================================"
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

validate_base64url() {
    local value="$1"
    local name="$2"
    
    # Check for padding (not allowed in base64url)
    if [[ "$value" == *"="* ]]; then
        print_error "$name contains padding (=) - must be removed"
        return 1
    fi
    
    # Check for invalid base64url characters
    if [[ "$value" =~ [^a-zA-Z0-9_-] ]]; then
        print_error "$name contains invalid characters - base64url only allows [a-zA-Z0-9_-]"
        echo "  Value: $value"
        return 1
    fi
    
    # Verify it can be decoded
    local decoded=$(echo "$value" | tr '_-' '/+' | base64 -d 2>/dev/null) || {
        print_error "$name cannot be decoded as base64"
        return 1
    }
    
    local decoded_len=${#decoded}
    if [ "$decoded_len" -ne 16 ]; then
        print_error "$name decodes to $decoded_len bytes, must be exactly 16 bytes (128-bit)"
        return 1
    fi
    
    print_success "$name is valid base64url (decodes to $decoded_len bytes)"
    return 0
}

validate_hex_to_base64url() {
    local hex="$1"
    local name="$2"
    
    print_info "Converting $name from hex to base64url..."
    
    # Remove hyphens from hex
    hex="${hex//-/}"
    
    # Check hex format
    if [[ ! "$hex" =~ ^[0-9a-fA-F]+$ ]]; then
        print_error "$name is not valid hex format"
        return 1
    fi
    
    if [ $((${#hex} % 2)) -ne 0 ]; then
        print_error "$name hex has odd number of characters"
        return 1
    fi
    
    # Convert hex to base64url
    local base64url=$(echo -n "$hex" | xxd -r -p | base64 | tr '+/' '_-' | tr -d '=')
    
    local decoded_len=$((${#hex} / 2))
    if [ "$decoded_len" -ne 16 ]; then
        print_error "$name hex decodes to $decoded_len bytes, must be exactly 16 bytes"
        return 1
    fi
    
    print_success "$name hex converted to base64url:"
    echo "  Hex input: $hex"
    echo "  Base64url: $base64url"
    return 0
}

print_examples() {
    print_header "Example kid/k Format"
    
    cat << 'EOF'
Valid ClearKey Configuration:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Format 1: Hex (32 chars for 16 bytes)
{
  "kid": "0102030405060708090a0b0c0d0e0f10",
  "k": "000102030405060708090a0b0c0d0e0f"
}

Format 2: Base64url (no padding)
{
  "kid": "AQIDBAUGBwgJCgsMDQ4PEA",
  "k": "AAABAgMEBQYHCAkKCwwNDg8"
}

Format 3: Mixed (with separator)
kid:k = "0102030405060708090a0b0c0d0e0f10:000102030405060708090a0b0c0d0e0f"
or
kid,k = "0102030405060708090a0b0c0d0e0f10,000102030405060708090a0b0c0d0e0f"

Invalid Formats:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ Hex with odd characters (31 instead of 32):
   "010203040506070809A0B0C0D0E0F"

❌ Base64url with padding:
   "AQIDBAUGBwgJCgsMDQ4PEA=="

❌ Base64 standard (+ and / invalid):
   "AQIDBAUGBwgJCgsMDQ4PEA+/"

❌ Mixed valid/invalid bases (32-char hex vs 16-byte decoded):
   32 chars hex = 16 bytes ✅
   24 chars base64url = 18 bytes ❌

Decimal Key IDs:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Supasoka also supports decimal format:
  kid:k = "12345:67890"

This is converted to:
  Hex(12345) = 3039 → Base64url = MDM5
  Hex(67890) = 010932 → Base64url = ARky

Debug Tips:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Count characters:
   - Hex format: Must be 32 chars (16 bytes × 2)
   - Base64url: Must be 22-24 chars (18-24 chars rounds to 16 bytes)

2. Valid base64url characters: a-z A-Z 0-9 - _
   (no + / = padding allowed)

3. Tools for conversion:
   - Hex to Base64url: echo -n "HEXHERE" | xxd -r -p | base64 | tr '+/' '_-' | tr -d '='
   - Base64url to Hex: echo "BASE64URLHERE" | tr '_-' '/+' | base64 -d | xxd -p

4. Validation sites:
   - https://www.base64url.com (remove padding before decoding)
   - Linux command: echo "BASE64URLHERE=" | base64 -d | xxd -p
EOF
}

# Main
print_header "ClearKey kid/k Format Validator"

case "${1:-help}" in
    validate)
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 validate <base64url_kid> <base64url_k>"
            exit 1
        fi
        validate_base64url "$2" "kid"
        validate_base64url "$3" "k"
        ;;
    hex)
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 hex <hex_kid> <hex_k>"
            exit 1
        fi
        validate_hex_to_base64url "$2" "kid"
        validate_hex_to_base64url "$3" "k"
        ;;
    examples)
        print_examples
        ;;
    *)
        print_examples
        cat << 'EOF'

Usage:
  $0 validate <base64url_kid> <base64url_k>
    Validate base64url-encoded kid and k values

  $0 hex <hex_kid> <hex_k>
    Convert hex format to base64url and validate

  $0 examples
    Show example formats and invalid cases

Examples:
  ./verify-clearkey.sh validate "AQIDBAUGBwgJCgsMDQ4PEA" "AAABAgMEBQYHCAkKCwwNDg8"
  ./verify-clearkey.sh hex "0102030405060708090a0b0c0d0e0f10" "000102030405060708090a0b0c0d0e0f"
  ./verify-clearkey.sh examples

EOF
        ;;
esac
