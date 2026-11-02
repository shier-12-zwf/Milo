#!/bin/bash
set -euo pipefail

# Native macOS, offline regression checks for the app's real async coordinator.
# Compile the Foundation-only core directly so no package resolution or network
# download is needed. AccountModel is the explicit test stub in the harness.
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ios_directory="$(cd -- "$script_directory/.." && pwd)"
mkdir -p "$ios_directory/.test-work"
test_root="$(mktemp -d "$ios_directory/.test-work/journal-ai.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

swift_compiler="$(xcrun --find swiftc)"
macos_sdk="$(xcrun --sdk macosx --show-sdk-path)"
"$swift_compiler" -swift-version 6 -warnings-as-errors \
    -sdk "$macos_sdk" \
    -emit-library -emit-module -module-name MiloCore \
    -emit-module-path "$test_root/MiloCore.swiftmodule" \
    -o "$test_root/libMiloCore.dylib" \
    "$ios_directory"/MiloCore/Sources/MiloCore/*.swift

"$swift_compiler" -swift-version 6 -warnings-as-errors -D MILO_AI_COORDINATOR_TESTS \
    -sdk "$macos_sdk" \
    -I "$test_root" -L "$test_root" -lMiloCore \
    -Xlinker -rpath -Xlinker "$test_root" \
    "$ios_directory/App/Account/AIConnection.swift" \
    "$ios_directory/App/JournalModel.swift" \
    "$ios_directory/tests/journal-ai-check.swift" \
    -o "$test_root/journal-ai-check"

"$test_root/journal-ai-check"

# Compile a separate process with the production gate, without the coordinator
# harness flag: even an injected closure and enabled old draft must stay offline.
"$swift_compiler" -swift-version 6 -warnings-as-errors \
    -sdk "$macos_sdk" \
    -I "$test_root" -L "$test_root" -lMiloCore \
    -Xlinker -rpath -Xlinker "$test_root" \
    "$ios_directory/App/Account/AIConnection.swift" \
    "$ios_directory/App/JournalModel.swift" \
    "$ios_directory/tests/ai-pause-check.swift" \
    -o "$test_root/ai-pause-check"

"$test_root/ai-pause-check"
