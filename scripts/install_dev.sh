#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
configuration=${1:-Release}
if [[ "$configuration" != Debug && "$configuration" != Release ]]; then
  print -u2 "Usage: $0 [Debug|Release]"
  exit 2
fi
source_app="$repo_dir/build/$configuration/Audio Smith.app"
install_root=${AUDIO_SMITH_INSTALL_ROOT:-/Applications}
installed_app="$install_root/Audio Smith.app"
expected_bundle_id='com.xingfuyi.AudioSmith'

"$repo_dir/scripts/build.sh" "$configuration"

# Stop every development/test copy before replacing the stable installation.
# Otherwise LaunchServices may route `open` to an unsigned DerivedData process
# with the same identity, making TCC permissions appear to vanish.
pkill -x AudioSmith 2>/dev/null || true
for _ in {1..20}; do
  pgrep -x AudioSmith >/dev/null 2>&1 || break
  sleep 0.1
done
if pgrep -x AudioSmith >/dev/null 2>&1; then
  print -u2 "Could not stop an existing AudioSmith process."
  exit 1
fi

if [[ -e "$installed_app" ]]; then
  existing_bundle_id=$(
    plutil -extract CFBundleIdentifier raw "$installed_app/Contents/Info.plist" 2>/dev/null || true
  )
  if [[ "$existing_bundle_id" != "$expected_bundle_id" ]]; then
    print -u2 "Refusing to replace an unrelated app at $installed_app"
    exit 1
  fi

  backup_root=$(mktemp -d "${TMPDIR:-/tmp}/audio-smith-install.XXXXXX")
  previous_app="$backup_root/Audio Smith.app"
  mv "$installed_app" "$previous_app"
  print "Previous development app moved to $previous_app"
fi

ditto "$source_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
open -n "$installed_app"

launched_stable_copy=false
for _ in {1..30}; do
  for pid in $(pgrep -x AudioSmith 2>/dev/null); do
    command_path=$(ps -p "$pid" -o command= 2>/dev/null || true)
    if [[ "$command_path" == "$installed_app/Contents/MacOS/AudioSmith" ]]; then
      launched_stable_copy=true
      break 2
    fi
  done
  sleep 0.1
done
if [[ "$launched_stable_copy" != "true" ]]; then
  print -u2 "The stable /Applications copy did not launch."
  exit 1
fi

print "Installed and launched $installed_app"
print "Configuration: $configuration"
print "Always launch this copy so macOS permissions stay associated with one app identity."
