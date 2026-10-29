# SpektraLab for iOS

The macOS film and print simulator, ported to iOS. One shared source tree:
the engine, the model, the service layer and most of the interface compile
for both platforms, and the platform-specific surfaces are `#if` blocks
rather than forks.

## Build (on a Mac)

```
brew install xcodegen
ios/build.sh              # simulator
ios/build.sh device       # device, needs your signing team
ios/build.sh project      # just regenerate SpektraLab-iOS.xcodeproj
ios/build.sh ipa          # unsigned Release .ipa (for Sideloadly / CI)
```

`build.sh` compiles the engine's Metal kernels **for iOS** (the safe-math
flags the engine's `spk_math_probe` guard demands are set there — the macOS
metallib does not load on iOS and must never be copied across), stages the
engine data into `ios/Resources/engine/`, regenerates the Xcode project with
XcodeGen, and builds.

Xcode 26+ (the same floor the Mac target has), iOS 17.0+.

## Build without a Mac (GitHub Actions + Sideloadly)

The Apple toolchain only runs on macOS, but a free GitHub Actions macOS
runner can be the build machine, and the signature can be applied on a
Windows PC afterwards:

1. **Fork the repository on GitHub** (or push the port to your own repo —
   the changed files are `ios/` in full, `.github/workflows/ios-ipa.yml`,
   and the 12 patched shared sources listed below).
2. On the repo's **Actions** tab, run the **"iOS ipa (unsigned)"** workflow
   (`workflow_dispatch`). A `macos-latest` runner selects its newest Xcode,
   installs XcodeGen, and runs `ios/build.sh ipa`.
3. Download the `SpektraLab-unsigned-ipa` artifact — an unsigned Release
   `.ipa`.
4. On Windows, install **Sideloadly** (sideloadly.io) plus Apple's
   **iTunes** and **iCloud** for Windows from apple.com (the driver
   libraries; the Microsoft Store versions do not carry them).
5. Plug the iPhone in, drag the `.ipa` into Sideloadly, enter your Apple ID,
   and start. A free Apple ID signs for **7 days** and allows up to 3
   sideloaded apps; a paid developer account ($99/yr) signs for a year.
6. On the phone: 设置 ▸ 通用 ▸ VPN 与设备管理 ▸ trust the certificate,
   then launch.

If the first cloud build fails, the Actions log names the file and line —
Swift or Xcode version drift between the port and the runner's newest Xcode
is the likely cause, and the fixes are usually one-liners.

## Size

The macOS bundle is 32 MB. The iOS bundle carries the same engine data
(~15 MB: constants, 28 film and paper profiles, print LUTs), the DI view
LUTs (~15 MB), film covers and licences, plus ~4 MB of code — roughly
**35 MB**, well inside "tens of MB". To slim it further, drop
`Resources/DI` from the target if the Digital Intermediate viewer is not
needed on mobile.

## What was ported

| layer | macOS | iOS |
|---|---|---|
| engine (C++20, C ABI) | compiled into the app | same sources, same target layout; `vulkan_gpu.cpp` compiles to nothing under `#ifndef __APPLE__` |
| engine kernels | `engine/build.sh` → metallib (macOS target) | `ios/build.sh` → metallib (iOS target), same math flags |
| Model, Service, Canvas core, Controls, Panels/Sections, Localization, Theme, Diagnostics | — | **shared verbatim**, except the `#if os(macOS)` blocks listed below |
| canvas | `CanvasNSView` (NSView, NSEvent, NSMenu) | `ios/app/CanvasUIView.swift` (MTKView + UIKit gestures) |
| @main / window | `SpektrafilmApp.swift`, `Windows/` | `ios/app/SpektraLabApp.swift`, `EditorScreen.swift` |
| import | `NSOpenPanel` | `fileImporter` + `PHPickerViewController` (`ios/app/ImportPicker.swift`) |
| export page | `Export/ExportPage.swift` | `ios/app/ExportSheet.swift` — `Exporter.export` unchanged, results saved to the photo library (additions-only permission) |
| filmstrip | `Panels/Filmstrip.swift` (drag reorder, Finder) | `ios/app/FilmstripBar.swift` (tap select, context menu) |
| agent CLI / MCP, update check | yes | not ported |

### Shared-file patches (the only edits to macOS sources)

* `Model/Session.swift` — the two `NSMenu` builders and their `@objc`
  targets are macOS-only; the `CanvasHost` conformance is shared.
* `Canvas/MetalCanvasView.swift` — `CanvasTool`, `StraightenLine` and the
  `CanvasHost` protocol are shared (the protocol's `contextMenu()`
  requirement is macOS-only); everything from `CanvasNSView` down is
  `#if os(macOS)`.
* `Theme/Theme.swift` — `NSFont` text metrics get a `UIFont` branch behind a
  `SystemFontWeight` alias.
* `Controls/ColorWheel.swift` — the sRGB interpolation reads `UIColor` on
  iOS.
* `Controls/ScrubSlider.swift` — ⌥ fine / ⇧ snap are pointer modifiers;
  iOS scrubs at full sensitivity.
* `Controls/PanelResize.swift`, `Controls/SectionLayout.swift` — cursor
  pushes are macOS-only.
* `Controls/CurveEditor.swift` — the `NSViewRepresentable` point context
  menu is macOS-only; iOS renders a passthrough (see "known gaps").
* `Import/Library.swift` — `chooseFilesOrFolder` is macOS-only; iOS imports
  through the UI layer.
* `Import/ThumbnailCache.swift`, `Export/Exporter.swift`,
  `Diagnostics/Diagnostics.swift` — import lines and one `NSWorkspace`
  reveal guarded.

### iOS canvas gestures

One-finger drag pans (and drives a mask grip or a pair placement first, in
the Mac's priority order); pinch zooms about the pinch; double-tap toggles
fit ↔ 100 %; a tap picks when a picker (eyedropper / white balance) is
active and clicks a pair hole otherwise. The grab radius is 22 pt — a
finger, not a cursor.

## Memory on iOS

The Mac's floor is 24 MP frames with GB-scale transient buffers. iOS keeps
the same pipeline but the session's `previewLongEdge` (Settings on the Mac)
is the lever to keep the live tier small; the pooled-buffer discipline in
`gpu.hpp` already avoids the reuse-while-reading class of bug. The 8 GB
disk cache from the Mac is not ported — nothing in the iOS flow depends on
it yet. Full-resolution export still runs through the same
`spk_reprint`-at-full-tier path; on low-memory devices that is the one
operation that can be Jetsam-killed, and tiling it is the first thing to do
if it bites.

## Known gaps (in priority order)

1. **On-canvas crop handle dragging** — the crop tool's grips, rectangle
   draw and ⌘-straighten are mouse gestures in `CanvasNSView`; on iOS the
   crop edits through the Crop section's controls (same `Geometry`), and
   the canvas shows the overlay read-only.
2. **Curve point context menu** — deleting a curve point by right-click is
   macOS-only; the iOS plot's long-press deletion is to come.
3. **Filmstrip drag reorder** — iOS cells select and context-menu only;
   order editing waits for a drag-and-drop pass.
4. **Diagnostics UI** — the Diagnostics model is compiled in; no iOS page
   reads it yet.
5. **Icon** — the macOS `SpektraLab.icon` (Icon Composer) is referenced by
   the iOS target; if your Xcode refuses it for iOS, drop the
   `ASSETCATALOG_COMPILER_APPICON_NAME` setting and add a plain AppIcon.
6. **CGColorSpace.rommrgb / adobeRGB1998 availability** — used by
   `ImageDecoder`; believed available on iOS 17, verify on device.
7. **RAW decoding breadth** — `CIRAWFilter` on iOS supports a somewhat
   different camera set than macOS; check your cameras.

## Licence notes

The port changes nothing about licensing: GPL-3.0 for this fork's code,
CC BY-SA 4.0 for spektrafilm's film profiles (`license/`), the engine data
and notices travel with the bundle exactly as on the Mac.
