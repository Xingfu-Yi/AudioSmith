#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
cd "$repo_dir"

configuration=${1:-Debug}
if [[ "$configuration" != Debug && "$configuration" != Release ]]; then
  print -u2 "Usage: $0 [Debug|Release]"
  exit 2
fi
product_app="$repo_dir/build/DerivedData/Build/Products/$configuration/Audio Smith.app"
staged_app="$repo_dir/build/$configuration/Audio Smith.app"

# Xcode's incremental resource copy can leave files that were removed from a
# folder resource in an existing .app. Clear only this generated Skills folder
# so the next build and staging copy exactly match the repository.
clear_generated_skill_resources() {
  local app_path=$1
  local skills_path="$app_path/Contents/Resources/Skills"
  if [[ -d "$skills_path" ]]; then
    find "$skills_path" -depth -delete
  fi
}

command -v xcodegen >/dev/null || {
  print -u2 "xcodegen is required: brew install xcodegen"
  exit 1
}

signing_identity=${AUDIO_SMITH_CODE_SIGN_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
  signing_identity=$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk '/"Apple Development:/ { print $2; exit }'
  )
fi

xcodegen generate

xcodebuild \
  -resolvePackageDependencies \
  -project AudioSmith.xcodeproj \
  -scheme AudioSmith \
  -derivedDataPath build/DerivedData \
  -skipPackagePluginValidation
audio_input_entitlement=$(
  /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.security.device.audio-input' \
    AudioSmith/Resources/AudioSmith.entitlements 2>/dev/null || true
)
if [[ "$audio_input_entitlement" != "true" ]]; then
  print -u2 "Missing com.apple.security.device.audio-input entitlement."
  exit 1
fi

clear_generated_skill_resources "$product_app"

xcodebuild \
  -project AudioSmith.xcodeproj \
  -scheme AudioSmith \
  -configuration "$configuration" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -skipPackagePluginValidation \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p "$repo_dir/build/$configuration"
clear_generated_skill_resources "$staged_app"
ditto "$product_app" "$staged_app"
if [[ -n "$signing_identity" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements AudioSmith/Resources/AudioSmith.entitlements \
    --sign "$signing_identity" \
    --identifier com.xingfuyi.AudioSmith \
    "$staged_app"
  print "Signed with the available Apple Development identity."
else
  codesign \
    --force \
    --deep \
    --sign - \
    --identifier com.xingfuyi.AudioSmith \
    "$staged_app"
  print -u2 "No Apple Development identity found; using ad-hoc signing."
  print -u2 "macOS may require permissions again after each rebuild."
fi
codesign --verify --deep --strict "$staged_app"
signed_entitlements=$(codesign -d --entitlements :- "$staged_app" 2>&1)
if [[ "$signed_entitlements" != *"com.apple.security.device.audio-input"* ]]; then
  print -u2 "Signed app is missing the audio-input entitlement."
  exit 1
fi
print "Built $staged_app"
