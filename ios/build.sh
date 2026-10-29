#!/bin/bash
# build.sh — the SpektraLab iOS app, one command.
#
#   ios/build.sh                # metallib + resources + project + simulator build
#   ios/build.sh device         # the same, for a connected device (needs signing)
#   ios/build.sh project        # just regenerate the Xcode project
#   ios/build.sh ipa            # unsigned Release .ipa (for Sideloadly / CI)
#
# What it does, in order:
#
#   1. compiles the engine's Metal kernels **for iOS** — the same safe-math
#      flags the Mac's build.sh sets (`-fmetal-math-mode=safe`,
#      `-fmetal-math-fp32-functions=precise`), because the engine's
#      `spk_math_probe` guard refuses to start under fast math. A metallib
#      stamped for macOS does not load on iOS; this step is why the iOS
#      target never touches the macOS one.
#   2. stages the engine data (constants, profiles, print LUTs, the product
#      profiles) into `ios/Resources/engine/`, with the iOS metallib in
#      place of the macOS one.
#   3. regenerates `SpektraLab-iOS.xcodeproj` with XcodeGen.
#   4. builds, for the iOS simulator by default.
#
# Requires: macOS with Xcode 26+, `xcodegen` (brew install xcodegen).

set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/.." && pwd)
engine="$root/engine"
out="$here/build"
mkdir -p "$out" "$here/Resources/engine"

TARGET=${1:-simulator}
case "$TARGET" in
  simulator) sdk=iphonesimulator; minflag="-mios-simulator-version-min=17.0"; dest="generic/platform=iOS Simulator" ;;
  device)    sdk=iphoneos;        minflag="-mios-version-min=17.0";            dest="generic/platform=iOS" ;;
  ipa)       sdk=iphoneos;        minflag="-mios-version-min=17.0";            dest="generic/platform=iOS" ;;
  project)   sdk="";              minflag="";                                  dest="" ;;
  *) echo "usage: build.sh [simulator|device|project|ipa]" >&2; exit 2 ;;
esac

math_flags=(-fmetal-math-mode=safe -fmetal-math-fp32-functions=precise)

# --- 1. the metallib, for iOS ----------------------------------------------
if [[ -n "$sdk" ]]; then
  echo "==> metal kernels ($sdk)"
  airs=()
  for m in "$engine"/src/shaders/*.metal; do
    air="$out/$(basename "$m" .metal).air"
    xcrun -sdk "$sdk" metal "${math_flags[@]}" $minflag -Werror -c "$m" -o "$air"
    airs+=("$air")
  done
  xcrun -sdk "$sdk" metallib "${airs[@]}" -o "$out/spektrafilm.metallib"
  echo "    metallib -> $out/spektrafilm.metallib"
fi

# --- 2. engine data into the iOS resource folder ---------------------------
echo "==> staging engine resources"
rsync -a --delete "$engine/resources/" "$here/Resources/engine/"
if [[ -d "$engine/resources_product/profiles" ]]; then
  cp "$engine/resources_product/profiles/"*.json "$here/Resources/engine/profiles/"
  cp "$engine/resources_product/NOTICE.md" "$here/Resources/engine/PRODUCT_PROFILES_NOTICE.md"
fi
if [[ -n "$sdk" ]]; then
  cp "$out/spektrafilm.metallib" "$here/Resources/engine/spektrafilm.metallib"
fi
du -sh "$here/Resources/engine" | cut -f1 | xargs -I{} echo "    engine data: {}"

# --- 3. the project --------------------------------------------------------
echo "==> xcodegen generate"
cd "$here" && xcodegen generate

# --- 4. build --------------------------------------------------------------
if [[ -n "$sdk" ]]; then
  echo "==> xcodebuild ($dest)"
  sign_args=()
  if [[ "$TARGET" == "ipa" ]]; then
    # An unsigned build: the .app is packaged into a .ipa and signed later
    # (Sideloadly / AltStore with the user's Apple ID, or Xcode with a team).
    sign_args=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
  fi
  config=Debug
  [[ "$TARGET" == "ipa" ]] && config=Release
  xcodebuild -project "$here/SpektraLab-iOS.xcodeproj" \
    -scheme SpektraLab-iOS \
    -configuration "$config" \
    -destination "$dest" \
    -derivedDataPath "$out/DerivedData" \
    "${sign_args[@]}" \
    build
  echo "==> done. products in ios/build/DerivedData/Build/Products"
else
  echo "==> project generated. Open SpektraLab-iOS.xcodeproj in Xcode."
fi

# --- 5. the unsigned .ipa --------------------------------------------------
if [[ "$TARGET" == "ipa" ]]; then
  app="$out/DerivedData/Build/Products/Release-iphoneos/SpektraLab.app"
  [[ -d "$app" ]] || { echo "build.sh: $app not found" >&2; exit 1; }
  rm -rf "$out/Payload" "$out/SpektraLab-unsigned.ipa"
  mkdir -p "$out/Payload"
  cp -R "$app" "$out/Payload/"
  (cd "$out" && zip -qry SpektraLab-unsigned.ipa Payload)
  rm -rf "$out/Payload"
  du -sh "$out/SpektraLab-unsigned.ipa" | cut -f1 | xargs -I{} \
    echo "==> ipa -> ios/build/SpektraLab-unsigned.ipa ({})"
fi
