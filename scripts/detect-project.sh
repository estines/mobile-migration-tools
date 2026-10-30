#!/usr/bin/env bash
set -euo pipefail

# mstack Project Detector
# Scans any mobile workspace to detect legacy languages, UI frameworks, build tools, and module structure.

ROOT_DIR="${1:-$(pwd)}"
cd "$ROOT_DIR"

echo "=== mstack Project Detection Report ==="
echo "workspace: $ROOT_DIR"

# 1. Detect Build Systems & Platforms
BUILD_SYSTEMS=()
[[ -f "settings.gradle.kts" || -f "settings.gradle" || -f "build.gradle.kts" || -f "build.gradle" ]] && BUILD_SYSTEMS+=("gradle")
compgen -G "*.xcodeproj" >/dev/null 2>&1 || compgen -G "*.xcworkspace" >/dev/null 2>&1 || [[ -f "Package.swift" ]] && BUILD_SYSTEMS+=("xcode/spm")
[[ -f "pubspec.yaml" ]] && BUILD_SYSTEMS+=("flutter")
[[ -f "package.json" ]] && BUILD_SYSTEMS+=("npm/react-native")

echo "build_systems: ${BUILD_SYSTEMS[*]:-unknown}"

# 2. Count Legacy & Modern Source Files (Fast find excluding build/node_modules/.git)
count_ext() {
  find . -maxdepth 12 \
    \( -name ".git" -o -name "build" -o -name ".gradle" -o -name "node_modules" -o -name "Pods" -o -name "DerivedData" \) -prune \
    -o -name "$1" -print 2>/dev/null | wc -l | tr -d ' '
}

JAVA_COUNT=$(count_ext "*.java")
KT_COUNT=$(count_ext "*.kt")
XML_LAYOUT_COUNT=$(find . -maxdepth 12 -path "*/res/layout/*.xml" 2>/dev/null | wc -l | tr -d ' ')
OBJC_COUNT=$(count_ext "*.m")
SWIFT_COUNT=$(count_ext "*.swift")
STORYBOARD_XIB_COUNT=$(( $(count_ext "*.storyboard") + $(count_ext "*.xib") ))
DART_COUNT=$(count_ext "*.dart")
TSX_COUNT=$(( $(count_ext "*.tsx") + $(count_ext "*.jsx") ))

echo "file_counts:"
echo "  java: $JAVA_COUNT"
echo "  kotlin: $KT_COUNT"
echo "  android_layout_xml: $XML_LAYOUT_COUNT"
echo "  objc: $OBJC_COUNT"
echo "  swift: $SWIFT_COUNT"
echo "  ios_storyboard_xib: $STORYBOARD_XIB_COUNT"
echo "  dart: $DART_COUNT"
echo "  tsx_jsx: $TSX_COUNT"

# 3. Check if KMP / CMP or Multi-Module is already partially present
if [[ -f "settings.gradle.kts" || -f "settings.gradle" ]]; then
  MODULE_COUNT=$(grep -E "include\(" settings.gradle* 2>/dev/null | wc -l | tr -d ' ')
  echo "gradle_modules_declared: $MODULE_COUNT"
fi

# 4. Check if .mstack/target-profile.json exists
if [[ -f ".mstack/target-profile.json" ]]; then
  echo "mstack_profile_status: CONFIGURED (.mstack/target-profile.json)"
else
  echo "mstack_profile_status: UNCONFIGURED (Run mstack-setup and ask user for target stack choices)"
fi
