#!/usr/bin/env bash
#
# Builds Mebius.xcframework for distribution (device + simulator slices).
#
# Requirements:
#   - Xcode with command line tools (xcodebuild)
#   - A scheme named "Mebius" (SPM provides one automatically)
#
# NOTE: Producing a fully signed, distributable XCFramework typically requires
# a valid signing identity / provisioning when archiving an app-embedded
# framework. For a pure library this script archives without code signing
# (SKIP_INSTALL=NO, BUILD_LIBRARY_FOR_DISTRIBUTION=YES). If your CI requires
# signing, supply DEVELOPMENT_TEAM / CODE_SIGN_IDENTITY accordingly.
#
# Usage:
#   ./scripts/build-xcframework.sh
#
set -euo pipefail

SCHEME="Mebius"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/xcframework"
OUTPUT="${ROOT_DIR}/Mebius.xcframework"

rm -rf "${BUILD_DIR}" "${OUTPUT}"
mkdir -p "${BUILD_DIR}"

echo "==> Archiving for iOS device"
xcodebuild archive \
  -scheme "${SCHEME}" \
  -destination "generic/platform=iOS" \
  -archivePath "${BUILD_DIR}/ios.xcarchive" \
  -derivedDataPath "${BUILD_DIR}/dd-ios" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  CODE_SIGNING_ALLOWED=NO

echo "==> Archiving for iOS simulator"
xcodebuild archive \
  -scheme "${SCHEME}" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "${BUILD_DIR}/sim.xcarchive" \
  -derivedDataPath "${BUILD_DIR}/dd-sim" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  CODE_SIGNING_ALLOWED=NO

FRAMEWORK_PATH="Products/Library/Frameworks/Mebius.framework"

echo "==> Creating Mebius.xcframework"
xcodebuild -create-xcframework \
  -framework "${BUILD_DIR}/ios.xcarchive/${FRAMEWORK_PATH}" \
  -framework "${BUILD_DIR}/sim.xcarchive/${FRAMEWORK_PATH}" \
  -output "${OUTPUT}"

echo "==> Done: ${OUTPUT}"
