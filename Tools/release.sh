#!/bin/zsh
# Archives Lookout (iOS) and LookoutTV (tvOS) and uploads both to App Store Connect.
# Usage: ./Tools-release.sh            (run only when Stephen asks for an upload)
#
# Why it looks unusual: on this Mac xcodebuild cannot provision through Xcode's
# account ("No Accounts") nor through the API key ("Authentication failed"), so
# the archive is built unsigned, ad-hoc signed with the resolved Production
# entitlements, then exported with MANUAL signing using the App Store profiles
# created through the App Store Connect API (see README). The upload itself
# authenticates with the API key, which works.
set -euo pipefail
cd "$(dirname "$0")"
KEY=~/.appstoreconnect/private_keys/AuthKey_Z5YD293RLM.p8
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID Z5YD293RLM -authenticationKeyIssuerID 69a6de84-dcf8-47e3-e053-5b8c7c11a4d1)
mkdir -p build/archives build/sign
for pair in "Lookout:iOS:iphoneos" "LookoutTV:tvOS:appletvos"; do
  scheme=${pair%%:*}; rest=${pair#*:}; plat=${rest%%:*}
  sed -e 's/\$(LOOKOUT_CLOUDKIT_ENVIRONMENT)/Production/' -e 's#<string>development</string>#<string>production</string>#' \
    "$scheme/$scheme.entitlements" > "build/sign/$scheme.entitlements"
  echo "== archive $plat"
  rm -rf "build/archives/Lookout-$plat.xcarchive"
  xcodebuild -project Lookout.xcodeproj -scheme "$scheme" -configuration Release -destination "generic/platform=$plat" \
    -archivePath "build/archives/Lookout-$plat.xcarchive" -derivedDataPath "build/dd-archive-$plat" \
    CODE_SIGNING_ALLOWED=NO archive 2>&1 | grep -E "error:|ARCHIVE" | sort -u
  codesign --force -s - --entitlements "build/sign/$scheme.entitlements" "build/archives/Lookout-$plat.xcarchive/Products/Applications/$scheme.app"
  echo "== upload $plat"
  rm -rf "build/upload-$plat"
  xcodebuild -exportArchive -archivePath "build/archives/Lookout-$plat.xcarchive" -exportOptionsPlist "Config/ExportOptions-$plat.plist" \
    -exportPath "build/upload-$plat" "${AUTH[@]}" 2>&1 | grep -iE "error|EXPORT|Upload succeeded|failed|invalid" | sort -u
done
