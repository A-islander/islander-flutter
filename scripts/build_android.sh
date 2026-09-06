#!/usr/bin/env bash
# Build locally; never uploads artifacts or changes signing configuration.
set -euo pipefail

mode=debug
packaging=split
for argument in "$@"; do
  case "$argument" in
    --debug) mode=debug ;;
    --release) mode=release ;;
    --universal) packaging=universal ;;
    --help|-h)
      printf '%s\n' 'Usage: bash scripts/build_android.sh [--debug|--release] [--universal]' \
        'Default: debug, split into arm64-v8a / armeabi-v7a / x86_64 APKs.' \
        'Override Flutter executable with FLUTTER_BIN; signing uses ISLANDER_SIGNING_DIR.'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
flutter_bin="${FLUTTER_BIN:-flutter}"
command -v "$flutter_bin" >/dev/null || { printf 'Flutter executable not found: %s\n' "$flutter_bin" >&2; exit 1; }
if command -v sha256sum >/dev/null; then
  checksum=(sha256sum)
elif command -v shasum >/dev/null; then
  checksum=(shasum -a 256)
else
  printf '%s\n' 'Install sha256sum or shasum before building.' >&2
  exit 1
fi

version_spec="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml)"
if [[ ! "$version_spec" =~ ^([0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?)\+([0-9]+)$ ]]; then
  printf '%s\n' 'Expected pubspec version: major.minor.patch+build (optional prerelease).' >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"
build_number="${BASH_REMATCH[3]}"
build_args=(build apk "--$mode" --target lib/main.dart)
abis=(universal)
if [[ "$packaging" == split ]]; then
  build_args+=(--split-per-abi)
  abis=(arm64-v8a armeabi-v7a x86_64)
fi
"$flutter_bin" "${build_args[@]}"

# Only export after a successful build and after checking every expected APK.
source_dir="$project_dir/build/app/outputs/flutter-apk"
for abi in "${abis[@]}"; do
  source_name="app-$abi-$mode.apk"
  if [[ "$abi" == universal ]]; then source_name="app-$mode.apk"; fi
  test -s "$source_dir/$source_name" || { printf 'Missing APK: %s\n' "$source_name" >&2; exit 1; }
done
output_dir="$project_dir/build/distributions/v$version-b$build_number/$mode/$packaging"
mkdir -p "$output_dir"
artifacts=()
for abi in "${abis[@]}"; do
  source_name="app-$abi-$mode.apk"
  if [[ "$abi" == universal ]]; then source_name="app-$mode.apk"; fi
  artifact="islander-android-v$version-b$build_number-$abi-$mode.apk"
  cp "$source_dir/$source_name" "$output_dir/$artifact"
  artifacts+=("$artifact")
done
(
  cd "$output_dir"
  "${checksum[@]}" "${artifacts[@]}" > SHA256SUMS.txt
)
printf '\nArtifacts: %s\n' "$output_dir"
printf '  %s\n' "${artifacts[@]}" SHA256SUMS.txt
