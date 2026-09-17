#!/bin/sh
# One-command rebuild and reinstall onto your iPhone, for the weekly refresh.
#
#   sh Scripts/reinstall.sh "Eugene's iPhone"
#
# Requirements (all one-time, see README "First-time setup"):
#   - Xcode installed and signed in to your Apple ID
#   - Config/Local.xcconfig containing your DEVELOPMENT_TEAM
#   - The phone paired with this Mac once (cable, "Trust"), Developer Mode on
#
# The phone may be on a cable or on the same Wi-Fi (after enabling
# "Connect via network" once in Xcode > Window > Devices and Simulators).
set -e
cd "$(dirname "$0")/.."

DEVICE_NAME="$1"
if [ -z "$DEVICE_NAME" ]; then
  echo "Usage: sh Scripts/reinstall.sh \"<your iPhone's name>\""
  echo
  echo "Devices Xcode can see right now:"
  xcrun devicectl list devices 2>/dev/null || true
  exit 1
fi

if [ ! -f Config/Local.xcconfig ]; then
  echo "Config/Local.xcconfig is missing. Copy Config/Local.xcconfig.example to Config/Local.xcconfig"
  echo "and put your Team ID in it (README, 'First-time setup')."
  exit 1
fi

echo "Building…"
xcodebuild \
  -project MotoHazardAlert.xcodeproj \
  -scheme MotoHazardAlert \
  -configuration Debug \
  -destination "platform=iOS,name=$DEVICE_NAME" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -quiet \
  build

APP="$(find build/Build/Products -maxdepth 2 -name 'MotoHazardAlert.app' | head -n 1)"
if [ -z "$APP" ]; then
  echo "Build finished but MotoHazardAlert.app was not found under build/. Open the project in Xcode and press Run instead."
  exit 1
fi

echo "Installing on $DEVICE_NAME…"
xcrun devicectl device install app --device "$DEVICE_NAME" "$APP"

echo "Launching…"
xcrun devicectl device process launch --device "$DEVICE_NAME" at.picaro.hazardpoc || true

echo "Done. The app is good for 7 days with a free Personal Team; run this again next week."
