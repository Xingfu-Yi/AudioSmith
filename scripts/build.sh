#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
cd "$repo_dir"

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

signing_identity=${DICTATE_AGENT_CODE_SIGN_IDENTITY:-}
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
    DictateAgent/Resources/DictateAgent.entitlements 2>/dev/null || true
)
if [[ "$audio_input_entitlement" != "true" ]]; then
  print -u2 "Missing com.apple.security.device.audio-input entitlement."
  exit 1
fi

clear_generated_skill_resources "$repo_dir/build/DerivedData/Build/Products/Debug/DictateAgent.app"

xcodebuild \
  -project AudioSmith.xcodeproj \
  -scheme AudioSmith \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -skipPackagePluginValidation \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p build/Debug
clear_generated_skill_resources "$repo_dir/build/Debug/DictateAgent.app"
ditto build/DerivedData/Build/Products/Debug/DictateAgent.app build/Debug/DictateAgent.app
if [[ -n "$signing_identity" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements DictateAgent/Resources/DictateAgent.entitlements \
    --sign "$signing_identity" \
    --identifier io.dictateagent.DictateAgent \
    build/Debug/DictateAgent.app
  print "Signed with the available Apple Development identity."
else
  codesign \
    --force \
    --deep \
    --sign - \
    --identifier io.dictateagent.DictateAgent \
    build/Debug/DictateAgent.app
  print -u2 "No Apple Development identity found; using ad-hoc signing."
  print -u2 "macOS may require permissions again after each rebuild."
fi
codesign --verify --deep --strict build/Debug/DictateAgent.app
signed_entitlements=$(codesign -d --entitlements :- build/Debug/DictateAgent.app 2>&1)
if [[ "$signed_entitlements" != *"com.apple.security.device.audio-input"* ]]; then
  print -u2 "Signed app is missing the audio-input entitlement."
  exit 1
fi
print "Built $repo_dir/build/Debug/DictateAgent.app"
