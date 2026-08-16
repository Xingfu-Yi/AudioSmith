#!/bin/zsh
set -euo pipefail

release_tag="${1:-${GITHUB_REF_NAME:-}}"
if [[ -z "$release_tag" ]]; then
  print -u2 "usage: $0 v<marketing-version>[-prerelease]"
  exit 2
fi

marketing_version=$(awk '$1 == "MARKETING_VERSION:" { print $2; exit }' project.yml)
build_number=$(awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2; exit }' project.yml)

if [[ -z "$marketing_version" || -z "$build_number" ]]; then
  print -u2 "Could not read MARKETING_VERSION or CURRENT_PROJECT_VERSION from project.yml"
  exit 1
fi
if [[ ! "$build_number" =~ '^[0-9]+$' ]]; then
  print -u2 "CURRENT_PROJECT_VERSION must be an integer: $build_number"
  exit 1
fi
if [[ "$release_tag" != "v$marketing_version" && "$release_tag" != "v$marketing_version-"* ]]; then
  print -u2 "Tag $release_tag does not match MARKETING_VERSION $marketing_version"
  exit 1
fi

print "release version valid: $release_tag (build $build_number)"
