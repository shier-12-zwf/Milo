#!/bin/bash
set -euo pipefail
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ios_directory="$(cd -- "$script_directory/.." && pwd)"
repo_directory="$(git -C "$ios_directory" rev-parse --show-toplevel)"
# Pin the pre-conversation iOS implementation; never read personal app storage.
legacy_ref=4379953
mkdir -p "$ios_directory/.test-work"
test_root="$(mktemp -d "$ios_directory/.test-work/journal-compatibility.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/legacy" "$test_root/fixtures"
while IFS= read -r relative; do
    git -C "$repo_directory" show "$legacy_ref:$relative" > "$test_root/legacy/$(basename -- "$relative")"
done < <(git -C "$repo_directory" ls-tree -r --name-only "$legacy_ref" -- apps/ios/MiloCore/Sources/MiloCore | sed -n '/\.swift$/p')
swift_compiler="$(xcrun --find swiftc)"
macos_sdk="$(xcrun --sdk macosx --show-sdk-path)"
"$swift_compiler" -swift-version 6 -warnings-as-errors -sdk "$macos_sdk" -emit-library -emit-module -module-name LegacyMiloCore -emit-module-path "$test_root/LegacyMiloCore.swiftmodule" -o "$test_root/libLegacyMiloCore.dylib" "$test_root"/legacy/*.swift
"$swift_compiler" -swift-version 6 -warnings-as-errors -sdk "$macos_sdk" -emit-library -emit-module -module-name MiloCore -emit-module-path "$test_root/MiloCore.swiftmodule" -o "$test_root/libMiloCore.dylib" "$ios_directory"/MiloCore/Sources/MiloCore/*.swift
"$swift_compiler" -swift-version 6 -warnings-as-errors -parse-as-library -D LEGACY_DECODER -sdk "$macos_sdk" -I "$test_root" -L "$test_root" -lLegacyMiloCore -Xlinker -rpath -Xlinker "$test_root" "$ios_directory/tests/journal-compatibility-check.swift" -o "$test_root/legacy-check"
"$swift_compiler" -swift-version 6 -warnings-as-errors -parse-as-library -sdk "$macos_sdk" -I "$test_root" -L "$test_root" -lMiloCore -Xlinker -rpath -Xlinker "$test_root" "$ios_directory/tests/journal-compatibility-check.swift" -o "$test_root/current-check"
"$test_root/legacy-check" write-legacy "$test_root/fixtures"
"$test_root/current-check" read-legacy-write-current "$test_root/fixtures"
"$test_root/legacy-check" read-current "$test_root/fixtures"
"$test_root/current-check" read-current "$test_root/fixtures"
