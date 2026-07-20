#!/usr/bin/env bash

set -euo pipefail

add_source_args() {
  [ -n "$IN_PATH" ] && args+=("$IN_PATH")
  [ -n "$IN_SCHEME" ] && args+=(--scheme "$IN_SCHEME")
  [ -n "$IN_CODESIGN_IDENTITY" ] && args+=(--codesign-identity "$IN_CODESIGN_IDENTITY")
  [ -n "$IN_BUILD_NUMBER" ] && args+=(--build-number "$IN_BUILD_NUMBER")
  [ -n "$IN_MARKETING_VERSION" ] && args+=(--marketing-version "$IN_MARKETING_VERSION")
  [ -n "$IN_BUNDLE_ID" ] && args+=(--bundle-id "$IN_BUNDLE_ID")
  [ "$IN_WATERMARK" = "true" ] && args+=(--watermark)
  [ "$IN_NO_DMG" = "true" ] && args+=(--no-dmg)
  return 0
}

add_publish_args() {
  [ -n "$IN_RELEASE_NOTES" ] && args+=(--release-notes "$IN_RELEASE_NOTES")
  [ -n "$IN_CHANNEL" ] && args+=(--channel "$IN_CHANNEL")
  [ "$IN_CRITICAL" = "true" ] && args+=(--critical)
  [ "$IN_DRAFT" = "true" ] && args+=(--draft)
  [ "$IN_PHASED_ROLLOUT" = "true" ] && args+=(--phased-rollout)
  return 0
}

publish_named_artifact() {
  case "$IN_ARTIFACT_NAME" in
    */*|*\\*|.|..)
      echo "artifact-name must be a filename without directory components" >&2
      exit 1
      ;;
  esac

  local extension="dmg"
  [ "$IN_NO_DMG" = "true" ] && extension="zip"
  case "$IN_ARTIFACT_NAME" in
    *."$extension") ;;
    *)
      echo "artifact-name must end in .$extension" >&2
      exit 1
      ;;
  esac

  local temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  local artifact_dir
  artifact_dir=$(mktemp -d "$temp_root/amore-release.XXXXXX")
  cleanup_artifact_dir="$artifact_dir"
  trap 'rm -rf "$cleanup_artifact_dir"' EXIT

  args=(release)
  add_source_args
  args+=(--output "$artifact_dir")
  amore "${args[@]}" --format json > "$artifact_dir/build.json"

  local artifact_path
  artifact_path=$(find "$artifact_dir" -maxdepth 1 -type f -name "*.$extension" -print -quit)
  if [ -z "$artifact_path" ]; then
    echo "Amore did not produce a .$extension artifact in $artifact_dir" >&2
    exit 1
  fi
  if [ "$(find "$artifact_dir" -maxdepth 1 -type f -name "*.$extension" | wc -l | tr -d ' ')" -ne 1 ]; then
    echo "Amore produced more than one .$extension artifact in $artifact_dir" >&2
    exit 1
  fi

  local named_artifact="$artifact_dir/$IN_ARTIFACT_NAME"
  if [ "$artifact_path" != "$named_artifact" ]; then
    mv "$artifact_path" "$named_artifact"
  fi

  args=(release "$named_artifact")
  [ -n "$IN_CODESIGN_IDENTITY" ] && args+=(--codesign-identity "$IN_CODESIGN_IDENTITY")
  add_publish_args
  amore "${args[@]}" --format json | tee release.json
}

[ "$IN_CHANNEL" = "stable" ] && IN_CHANNEL=""

if [ -n "$IN_ARTIFACT_NAME" ]; then
  publish_named_artifact
else
  args=(release)
  add_source_args
  add_publish_args
  amore "${args[@]}" --format json | tee release.json
fi

{
  echo "version=$(jq -r '.release.bundleVersionString // ""' release.json)"
  echo "build-number=$(jq -r '.release.bundleVersion // ""' release.json)"
  echo "bundle-id=$(jq -r '.app.bundleIdentifier // ""' release.json)"
  echo "download-url=$(jq -r '.release.downloadURL // ""' release.json)"
  echo "latest-url=$(jq -r '.latestDownloadURL // ""' release.json)"
} >> "$GITHUB_OUTPUT"
