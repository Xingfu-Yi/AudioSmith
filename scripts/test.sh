#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
cd "$repo_dir"

command -v xcodegen >/dev/null || {
  print -u2 "xcodegen is required: brew install xcodegen"
  exit 1
}

xcodegen generate
xcodebuild \
  -resolvePackageDependencies \
  -project AudioSmith.xcodeproj \
  -scheme AudioSmith \
  -derivedDataPath build/DerivedData \
  -skipPackagePluginValidation
xcodebuild \
  -project AudioSmith.xcodeproj \
  -scheme AudioSmith \
  -configuration Test \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -skipPackagePluginValidation \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  test

test_host_info="$repo_dir/build/DerivedData/Build/Products/Test/Audio Smith.app/Contents/Info.plist"
test_host_bundle_id=$(plutil -extract CFBundleIdentifier raw "$test_host_info" 2>/dev/null || true)
if [[ "$test_host_bundle_id" != "com.xingfuyi.AudioSmith.TestHost" ]]; then
  print -u2 "Test host must use the isolated .TestHost bundle identifier."
  exit 1
fi
