#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
source_app="$repo_dir/build/Debug/DictateAgent.app"
install_root=${DICTATE_AGENT_INSTALL_ROOT:-/Applications}
installed_app="$install_root/DictateAgent.app"
expected_bundle_id='io.dictateagent.DictateAgent'

"$repo_dir/scripts/build.sh"

# Stop every development/test copy before replacing the stable installation.
# Otherwise LaunchServices may route `open` to an unsigned DerivedData process
# with the same historical identity, making TCC permissions appear to vanish.
pkill -x DictateAgent 2>/dev/null || true
for _ in {1..20}; do
  pgrep -x DictateAgent >/dev/null 2>&1 || break
  sleep 0.1
done
if pgrep -x DictateAgent >/dev/null 2>&1; then
  print -u2 "Could not stop an existing DictateAgent process."
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

  backup_root=$(mktemp -d "${TMPDIR:-/tmp}/dictate-agent-install.XXXXXX")
  previous_app="$backup_root/DictateAgent.app"
  mv "$installed_app" "$previous_app"
  print "Previous development app moved to $previous_app"
fi

ditto "$source_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
open -n "$installed_app"

launched_stable_copy=false
for _ in {1..30}; do
  for pid in $(pgrep -x DictateAgent 2>/dev/null); do
    command_path=$(ps -p "$pid" -o command= 2>/dev/null || true)
    if [[ "$command_path" == "$installed_app/Contents/MacOS/DictateAgent" ]]; then
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
print "Always launch this copy so macOS permissions stay associated with one app identity."
