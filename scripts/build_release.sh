#!/bin/bash

# LlamaTerminal Build & Distribution Script
# This script builds, packages, signs, and notarizes LlamaTerminal for distribution
# Requirements: Xcode, create-dmg, xcbeautify (optional)

set -e  # Exit on any error

# ===== Configuration =====
APP_NAME="LlamaTerminal"
SCHEME_NAME="LlamaTerminal"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
DMG_DIR="${BUILD_DIR}/dmg"
DMG_NAME="${APP_NAME}-1.0.dmg"
DMG_PATH="${DMG_DIR}/${DMG_NAME}"
EXPORT_OPTIONS_PLIST="${PROJECT_DIR}/scripts/ExportOptions.plist"
TEAM_ID="" # Your Developer Team ID goes here
DEVELOPER_ID="" # Your Developer ID Application certificate name

# Log formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===== Helper Functions =====

log_section() {
    echo -e "\n${BLUE}===== $1 =====${NC}"
}

log_info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

check_tool() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is required but not installed. Please install it and try again."
        if [ -n "$2" ]; then
            echo "  $2"
        fi
        exit 1
    fi
}

# ===== Pre-flight Checks =====
log_section "Pre-flight Checks"

# Check for required tools
check_tool "xcodebuild" "Install Xcode from the App Store"
check_tool "xcpretty" "Install with: gem install xcpretty"
check_tool "create-dmg" "Install with: brew install create-dmg"

# Check for team ID
if [ -z "$TEAM_ID" ]; then
    log_warning "TEAM_ID is not set. Code signing will be skipped."
    SKIP_SIGNING=true
fi

# Check for developer ID
if [ -z "$DEVELOPER_ID" ]; then
    log_warning "DEVELOPER_ID is not set. Code signing will be skipped."
    SKIP_SIGNING=true
fi

# ===== Clean Build Directory =====
log_section "Cleaning Build Directory"

if [ -d "$BUILD_DIR" ]; then
    log_info "Removing previous build artifacts..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
mkdir -p "$DMG_DIR"

# ===== Create Export Options Plist =====
log_section "Creating Export Options"

if [ "$SKIP_SIGNING" != true ]; then
    cat > "$EXPORT_OPTIONS_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>developer-id</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>developmentTeam</key>
    <string>${TEAM_ID}</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
</dict>
</plist>
EOF
else
    log_info "Skipping export options creation for unsigned build"
fi

# ===== Build App =====
log_section "Building App"

log_info "Building ${APP_NAME}..."

BUILD_FLAGS=(
    "-project" "${PROJECT_DIR}/${APP_NAME}.xcodeproj" 
    "-scheme" "${SCHEME_NAME}" 
    "-configuration" "Release" 
    "-derivedDataPath" "${DERIVED_DATA_PATH}" 
    "DEVELOPMENT_TEAM=${TEAM_ID}"
    "CODE_SIGN_IDENTITY=${DEVELOPER_ID}"
)

xcodebuild clean "${BUILD_FLAGS[@]}" | xcpretty

if [ "$SKIP_SIGNING" != true ]; then
    # Build and archive for distribution
    log_info "Creating signed archive..."
    xcodebuild archive "${BUILD_FLAGS[@]}" \
        -archivePath "${ARCHIVE_PATH}" | xcpretty
    
    # Export archive to app
    log_info "Exporting signed app..."
    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
        -exportPath "${BUILD_DIR}" | xcpretty
else
    # Build for testing only (no signing)
    log_info "Building unsigned app (for testing only)..."
    xcodebuild build "${BUILD_FLAGS[@]}" \
        -destination "platform=macOS" \
        CONFIGURATION_BUILD_DIR="${BUILD_DIR}" | xcpretty
    
    # Copy the app to the expected location
    mkdir -p "${BUILD_DIR}/Products"
    cp -R "${BUILD_DIR}/${APP_NAME}.app" "${BUILD_DIR}/Products/"
fi

# Verify the app exists
if [ ! -d "${BUILD_DIR}/Products/${APP_NAME}.app" ]; then
    log_error "Build failed: App not found at ${BUILD_DIR}/Products/${APP_NAME}.app"
    exit 1
fi

log_info "Build successful: ${BUILD_DIR}/Products/${APP_NAME}.app"

# ===== Create DMG =====
log_section "Creating DMG Installer"

APP_PATH="${BUILD_DIR}/Products/${APP_NAME}.app"

log_info "Creating DMG..."
create-dmg \
    --volname "${APP_NAME}" \
    --volicon "${PROJECT_DIR}/${APP_NAME}/Assets.xcassets/AppIcon.appiconset/app_icon_512.png" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 200 190 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 600 185 \
    "${DMG_PATH}" \
    "${APP_PATH}" || {
        log_error "Failed to create DMG"
        exit 1
    }

log_info "DMG created at: ${DMG_PATH}"

# ===== Notarize App =====
if [ "$SKIP_SIGNING" != true ]; then
    log_section "Notarizing App"
    
    log_info "Submitting app for notarization..."
    
    # Check for Apple ID and password in environment
    if [ -z "$APPLE_ID" ] || [ -z "$APPLE_ID_PASSWORD" ]; then
        log_warning "APPLE_ID or APPLE_ID_PASSWORD not set. Notarization will be skipped."
        log_warning "Set these environment variables to enable notarization:"
        log_warning "export APPLE_ID=your.apple.id@example.com"
        log_warning "export APPLE_ID_PASSWORD=app-specific-password"
    else
        # Submit for notarization
        xcrun notarytool submit "${DMG_PATH}" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_ID_PASSWORD" \
            --team-id "$TEAM_ID" \
            --wait
        
        # Staple the notarization ticket
        xcrun stapler staple "${DMG_PATH}"
        
        log_info "Notarization complete and stapled to DMG"
    fi
fi

# ===== Final Summary =====
log_section "Build Summary"

log_info "Build completed successfully!"
log_info "App: ${APP_PATH}"
log_info "DMG: ${DMG_PATH}"

if [ "$SKIP_SIGNING" == true ]; then
    log_warning "This build is unsigned and intended for testing only."
    log_warning "To create a signed, distributable build, set TEAM_ID and DEVELOPER_ID variables."
else
    if [ -z "$APPLE_ID" ] || [ -z "$APPLE_ID_PASSWORD" ]; then
        log_warning "The app was signed but not notarized. It may trigger security warnings on macOS."
    else
        log_info "The app is signed and notarized, ready for distribution."
    fi
fi

log_info "Done!"
exit 0

