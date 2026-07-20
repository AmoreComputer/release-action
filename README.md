# Amore Release Action

Build, sign, notarize, and publish a macOS app release via the [Amore](https://amore.computer) CLI, in one GitHub Actions step.

The action installs the Amore CLI on the runner, imports your Developer ID certificate, then runs `amore release`: archive, code sign, DMG, notarize, Sparkle sign, and upload.

## Quick start

Copy this into `.github/workflows/release.yml` and fill in your scheme, runner, and Xcode. Pushing a `v*` tag ships a stable release; use a manual run to publish to a channel like `beta`.

```yaml
name: Release
run-name: Release ${{ github.event.repository.name }}${{ inputs.channel && format(' ({0})', inputs.channel) || '' }}

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      channel:
        type: choice
        default: alpha
        options:
          - alpha
          - beta
          - stable
        description: Channel for manual runs (stable = no channel)
      build-number:
        type: string
        default: auto
        description: Build number ("auto", "timestamp", or an integer)
      marketing-version:
        type: string
        default: ""
        description: Override marketing version (e.g. 1.2.3)

concurrency:
  group: amore-release
  cancel-in-progress: true

jobs:
  release:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - uses: AmoreComputer/release-action@v1
        with:
          # Uncomment to pin Xcode to what your project builds with, so a runner
          # image update can't drift the default to a version that breaks your
          # build. Leave commented to use whatever the runner ships.
          # xcode-path: /Applications/Xcode_16.app
          scheme: YourScheme
          codesign-identity: ${{ secrets.CODESIGN_IDENTITY }}
          dev-id-cert-p12: ${{ secrets.DEV_ID_CERT_P12 }}
          dev-id-cert-password: ${{ secrets.DEV_ID_CERT_PASSWORD }}
          sparkle-private-key: ${{ secrets.SPARKLE_PRIVATE_KEY }}
          asc-api-key-id: ${{ secrets.ASC_API_KEY_ID }}
          asc-api-issuer: ${{ secrets.ASC_API_ISSUER }}
          asc-api-key: ${{ secrets.ASC_API_KEY }}
          amore-token: ${{ secrets.AMORE_TOKEN }}
          channel: ${{ inputs.channel }}
          build-number: ${{ inputs.build-number || 'auto' }}
          marketing-version: ${{ inputs.marketing-version }}
          # Optional: publish a versioned download filename instead of the
          # product-derived default (for example, YourApp.dmg).
          # artifact-name: YourApp-${{ inputs.marketing-version }}.dmg
          # Leave false to use your account default: Amore+ ships a clean DMG,
          # free accounts always ship the "Built with amore.computer" watermark.
          # Set true only if you want to keep the watermark.
          watermark: false
          # --- Self-hosted S3 hosting only (uncomment if not using Amore hosting) ---
          # s3-bucket: ${{ vars.AMORE_S3_BUCKET }}
          # s3-region: ${{ vars.AMORE_S3_REGION }}
          # s3-public-url: ${{ vars.AMORE_S3_PUBLIC_URL }}
          # s3-endpoint: ${{ vars.AMORE_S3_ENDPOINT }}
          # s3-path-prefix: ${{ vars.AMORE_S3_PATH_PREFIX }}
          # s3-appcast-path: ${{ vars.AMORE_S3_APPCAST_PATH }}
          # aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          # aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## Multi-channel (alpha / beta / stable)

Prefer to drive the channel off the trigger instead of a manual flag? This variant publishes:

- **alpha** on every push to `main`,
- **beta** on any version tag containing `beta` (e.g. `v1.2.3-beta`),
- **stable** on any other version tag (e.g. `v1.2.3`),
- and lets a manual run pick `alpha`, `beta`, or `stable` (stable = no channel).

A small step derives the channel from the event. It's a step rather than an inline
expression because a tag can't be mapped to the stable channel inline: GitHub treats the
empty channel string as falsy, so `startsWith(github.ref, 'refs/tags/') && ''` falls through
the `||` chain and a stable tag ends up mislabeled. Same secrets as above.

```yaml
name: Release
run-name: Release ${{ github.event.repository.name }} ${{ github.ref_type == 'tag' && github.ref_name || format('({0})', github.event_name == 'workflow_dispatch' && inputs.channel || 'alpha') }}

on:
  push:
    branches: [main]      # push to main    -> alpha
    tags: ['v*']          # tag v1.2.3-beta -> beta
                          # tag v1.2.3      -> stable
  workflow_dispatch:
    inputs:
      channel:
        type: choice
        default: alpha
        options:
          - alpha
          - beta
          - stable
        description: Channel for manual runs (stable = no channel)
      build-number:
        type: string
        default: auto
        description: Build number ("auto", "timestamp", or an integer)
      marketing-version:
        type: string
        default: ""
        description: Override marketing version (e.g. 1.2.3)

concurrency:
  group: amore-release
  cancel-in-progress: true

jobs:
  release:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      # push to main -> alpha; tag containing "beta" -> beta; any other v* tag -> stable.
      - name: Resolve channel
        id: ctx
        env:
          EVENT: ${{ github.event_name }}
          REF_TYPE: ${{ github.ref_type }}
          REF_NAME: ${{ github.ref_name }}
          INPUT_CHANNEL: ${{ inputs.channel }}
        run: |
          set -euo pipefail
          channel=""
          if [ "$EVENT" = "workflow_dispatch" ]; then
            channel="$INPUT_CHANNEL"   # the action maps "stable" to the stable channel
          elif [ "$REF_TYPE" = "branch" ]; then
            channel="alpha"
          elif [ "$REF_TYPE" = "tag" ]; then
            case "$REF_NAME" in *beta*) channel="beta" ;; esac
          fi
          echo "channel=$channel" >> "$GITHUB_OUTPUT"
          echo "Resolved channel='${channel:-stable}'"

      - uses: AmoreComputer/release-action@v1
        with:
          # xcode-path: /Applications/Xcode_16.app   # pin to avoid runner drift
          scheme: YourScheme
          codesign-identity: ${{ secrets.CODESIGN_IDENTITY }}
          dev-id-cert-p12: ${{ secrets.DEV_ID_CERT_P12 }}
          dev-id-cert-password: ${{ secrets.DEV_ID_CERT_PASSWORD }}
          sparkle-private-key: ${{ secrets.SPARKLE_PRIVATE_KEY }}
          asc-api-key-id: ${{ secrets.ASC_API_KEY_ID }}
          asc-api-issuer: ${{ secrets.ASC_API_ISSUER }}
          asc-api-key: ${{ secrets.ASC_API_KEY }}
          amore-token: ${{ secrets.AMORE_TOKEN }}
          # false = account default (Amore+ clean, free watermarked); true keeps the watermark.
          watermark: false
          channel: ${{ steps.ctx.outputs.channel }}
```

## Secrets

Set these in your repo under **Settings → Secrets and variables → Actions**.

Amore-managed hosting (the common case) needs:

| Secret | What it is |
| --- | --- |
| `AMORE_TOKEN` | Scoped Amore API token. |
| `CODESIGN_IDENTITY` | Developer ID Application identity string. |
| `DEV_ID_CERT_P12` | base64 of your Developer ID Application `.p12`. |
| `DEV_ID_CERT_PASSWORD` | Password for that `.p12`. |
| `SPARKLE_PRIVATE_KEY` | base64 Ed25519 Sparkle signing key. |
| `ASC_API_KEY_ID` | App Store Connect API key ID (for notarization). |
| `ASC_API_ISSUER` | App Store Connect API issuer ID. |
| `ASC_API_KEY` | base64 of the ASC `.p8` key. |

Self-hosting on S3 / R2 / MinIO instead of Amore hosting? Also set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, and uncomment the `s3-*` inputs.

## Inputs

`scheme` is the Xcode scheme to build. `channel` picks the release channel (e.g. `alpha`, `beta`); empty or `stable` ships stable, so a `workflow_dispatch` choice input can pass straight through. Everything else has a sensible default; see [`action.yml`](action.yml) for the full list, including `path`, `release-notes`, `critical`, `draft`, `phased-rollout`, `watermark`, `no-dmg`, `provisioning-profile`, and the `s3-*` hosting inputs.

`artifact-name` optionally controls the published download filename. Include the extension (`.dmg`, or `.zip` with `no-dmg: true`) and do not include a directory. The action first produces the signed and notarized artifact locally, renames it, then publishes that existing artifact. When omitted, the action keeps the normal one-pass release flow.

`build-number` defaults to `auto`: one past the highest build number the destination already has published. Use `timestamp` if you'd rather not depend on the destination being reachable, or pass an explicit integer.

`provisioning-profile` (base64 of a `.provisionprofile`) is only needed if your app's entitlements require one, e.g. Associated Domains.

`cache` (default `true`) caches Swift package checkouts between runs via GitHub's cache service, keyed per scheme and dependency set, so warm builds skip cloning the package graph. Set it to `false` to always resolve fresh.

Set `cache: external` to bring your own cache action instead — useful on runner providers with their own, faster cache service (WarpBuild, BuildJet, Blacksmith, ...). The action still pins package checkouts to `.amore/SourcePackages`; the workflow caches that directory itself:

```yaml
      - uses: WarpBuilds/cache@v1     # or actions/cache, BuildJet/cache-action, ...
        with:
          path: .amore/SourcePackages
          # The scheme is part of the key: caches never re-save on an exact-key
          # hit, so in a multi-app repo one shared key would freeze the first
          # scheme's content. The bare restore-key seeds new schemes.
          key: ${{ runner.os }}-amore-spm-YourScheme-${{ hashFiles('**/Package.resolved', '**/Package.swift') }}
          restore-keys: |
            ${{ runner.os }}-amore-spm-YourScheme-
            ${{ runner.os }}-amore-spm-

      - uses: AmoreComputer/release-action@v1
        with:
          scheme: YourScheme
          cache: external
          # ...
```

`bundle-id` is optional: when set, amore skips the `xcodebuild` workspace query that otherwise resolves the bundle identifier before archiving, saving ~20 seconds per run.

## Outputs

`version`, `build-number`, `bundle-id`, `download-url`, `latest-url`.

## Versioning

Pin the major tag `@v1` to get non-breaking fixes automatically. Breaking changes ship under `@v2`, which you opt into by editing the ref.
