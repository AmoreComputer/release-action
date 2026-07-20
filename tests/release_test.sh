#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/amore-action-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/runner"
cat > "$test_root/bin/amore" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
  echo CALL
  printf 'ARG=%s\n' "$@"
} >> "$AMORE_TEST_LOG"

output=""
extension="dmg"
for arg in "$@"; do
  [ "$arg" = "--no-dmg" ] && extension="zip"
done
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output" ]; then
    output="$2"
    shift 2
  else
    shift
  fi
done

if [ -n "$output" ]; then
  mkdir -p "$output"
  printf 'artifact' > "$output/Generated.$extension"
fi

printf '%s\n' '{"release":{"bundleVersionString":"1.2.3","bundleVersion":"42","downloadURL":"https://example.com/download"},"app":{"bundleIdentifier":"com.example.app"},"latestDownloadURL":"https://example.com/latest"}'
EOF
chmod +x "$test_root/bin/amore"

run_release() {
  (
    cd "$test_root"
    env \
      PATH="$test_root/bin:$PATH" \
      AMORE_TEST_LOG="$test_root/amore.log" \
      GITHUB_OUTPUT="$test_root/github-output" \
      RUNNER_TEMP="$test_root/runner" \
      IN_SCHEME="Example" \
      IN_PATH="Example.xcodeproj" \
      IN_CODESIGN_IDENTITY="Developer ID" \
      IN_RELEASE_NOTES="Fixed things" \
      IN_CHANNEL="beta" \
      IN_CRITICAL="false" \
      IN_DRAFT="false" \
      IN_PHASED_ROLLOUT="false" \
      IN_WATERMARK="false" \
      IN_NO_DMG="${2:-false}" \
      IN_BUILD_NUMBER="auto" \
      IN_MARKETING_VERSION="1.2.3" \
      IN_BUNDLE_ID="com.example.app" \
      IN_ARTIFACT_NAME="$1" \
      bash "$repo_root/scripts/release.sh"
  )
}

run_release "Example-1.2.3.dmg" >/dev/null

[ "$(grep -c '^CALL$' "$test_root/amore.log")" -eq 2 ]
[ "$(grep -c '^ARG=--build-number$' "$test_root/amore.log")" -eq 1 ]
[ "$(grep -c '^ARG=--release-notes$' "$test_root/amore.log")" -eq 1 ]
[ "$(grep -c '^ARG=--codesign-identity$' "$test_root/amore.log")" -eq 2 ]
grep -q '^ARG=--output$' "$test_root/amore.log"
grep -q '/Example-1.2.3.dmg$' "$test_root/amore.log"
grep -q '^version=1.2.3$' "$test_root/github-output"
grep -q '^build-number=42$' "$test_root/github-output"

: > "$test_root/amore.log"
: > "$test_root/github-output"
run_release "" >/dev/null

[ "$(grep -c '^CALL$' "$test_root/amore.log")" -eq 1 ]
[ "$(grep -c '^ARG=--build-number$' "$test_root/amore.log")" -eq 1 ]
[ "$(grep -c '^ARG=--release-notes$' "$test_root/amore.log")" -eq 1 ]
[ "$(grep -c '^ARG=--codesign-identity$' "$test_root/amore.log")" -eq 1 ]
! grep -q '^ARG=--output$' "$test_root/amore.log"

: > "$test_root/amore.log"
: > "$test_root/github-output"
run_release "Example-1.2.3.zip" "true" >/dev/null

[ "$(grep -c '^CALL$' "$test_root/amore.log")" -eq 2 ]
[ "$(grep -c '^ARG=--no-dmg$' "$test_root/amore.log")" -eq 1 ]
grep -q '/Example-1.2.3.zip$' "$test_root/amore.log"

if run_release "nested/Example.dmg" >/dev/null 2>&1; then
  echo "Expected a nested artifact-name to fail" >&2
  exit 1
fi

echo "release tests passed"
