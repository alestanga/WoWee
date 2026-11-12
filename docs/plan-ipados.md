# iPadOS Port Plan

**Status:** running on device (iPad Air 11" M3, iPadOS 27.2). Login, character
select and in-world play all verified.
**Target:** iPadOS (and iOS) on arm64, touch-driven, installed as an IPA.
**Goal:** mirror the Android port's architecture: shared C++ core built by the
top-level CMake, Apple-side app shell, SDL3 + Vulkan via MoltenVK.

## 1. What is already portable

Same as Android (see `docs/plan-android.md` §1): SDL3 windowing/input, Vulkan
renderer, SPIR-V shaders, CMake cross-build, runtime data/config paths, FSR2
off path, Warden stub. iPadOS adds Apple-specific constraints below but no
new abstraction in the core.

## 2. Key differences from Android

| Area | Android approach | iPadOS approach |
|---|---|---|
| Windowing/input | SDLActivity (Java) | SDL3 UIKit backend (Objective-C), app bundle |
| Graphics | native Vulkan | MoltenVK (Vulkan -> Metal) |
| Build | Gradle + NDK | Xcode + CMake toolchain file |
| Packaging | APK/AAB | IPA via Xcode archive |
| Distribution | sideload / Play | TestFlight / App Store (or sideload) |
| Soft keyboard | SDL text input | UIKeyboard / SDL text input |
| Files/storage | `getExternalFiles()` | App sandbox + File Sharing (iTunes/Finder) or iCloud |
| Touch | `src/ui/touch_controls.cpp` | reuse same module |

## 3. Blockers

1. ~~**No macOS/Xcode in this environment.**~~ Resolved: builds happen on the
   user's Mac with Xcode; the repo's CI still only does scaffold + cross-compile
   headers.
2. ~~**MoltenVK.**~~ Resolved: MoltenVK 1.4.2 static xcframework vendored in
   `extern/MoltenVK/`.
3. **Code signing & provisioning.** Signing team `5NLYCB4UAX` works, but the
   Mac's login keychain re-locks periodically and then CodeSign fails with
   `errSecInternalComponent`. The user must unlock the Mac before a build can
   finish. Nothing to fix in the project.
4. **Touch UX.** Reuse Android's `touch_controls.cpp`; iPad has larger screen
   and (optionally) keyboard/trackpad/mouse. Deferred - the iPad is played
   with keyboard + mouse for now.
5. **App lifecycle / background.** iOS suspends aggressively; need to handle
   `SDL_APP_WILLENTERBACKGROUND` to pause network/render.
6. **Large data (35 GB).** Same constraint as Android, and the same answer:
   `tools/android/make_minimal_data.py` cuts the extraction down to a profile
   that fits (787 MB for the login screen, 7.5 GB for one continent, 12 GB for
   every map). The tool is platform-agnostic - it reads `manifest.json` and
   writes a tree with its own - so the iPad uses it unchanged. The result is
   copied into `Documents/Data` over USB with Finder. See `ios/README.md`.

## 4. Work breakdown

- Phase 0 (done): scaffold `ios/`, `docs/plan-ipados.md`, CMake iOS guards,
  `src/core/ios_platform.{hpp,mm}`.
- Phase 1 (done): CMake iOS toolchain file (`cmake/ios.toolchain.cmake`),
  `libwowee` + MoltenVK built and linked.
- Phase 2 (done): Xcode app bundle, Info.plist, LaunchScreen, SDL main glue,
  first run to login screen, and through to in-world play.
- Phase 3 (pending): touch controls (reuse Android module), soft keyboard,
  safe areas.
- Phase 4 (partial): the scene delegate forwards the lifecycle; background
  pause still to do.
- Phase 5 (pending): TestFlight/App Store packaging, release workflow.
- Data sizing (done): the extraction is cut down with the existing profile
  tool, and the app bundle carries only the assets the client reads (the
  project's own soundtrack and the README screenshots are not in it).

## 5. GitHub workflow

Fork `Kelsidavis/WoWee` to the personal account, develop on the `ipados`
branch, open PR upstream when stable. See README/CONTRIBUTING.md.

## 6. Open questions

- Use SwiftUI/UIKit app shell or SDL's default UIKit main? Prefer SDL's.
- Mouse/trackpad support on iPad (pointer) - leverage SDL mouse events.
- Whether to ship as iPad-only or universal (iPhone). Start iPad-only.

## 7. What the iPad build is made of

- **Build:** `xcodebuild -project build-ios/wowee.xcodeproj -scheme wowee
  -configuration Debug -destination 'id=<udid>' build`, with
  `PATH="$HOME/Library/Python/3.9/bin:/Users/ale/Documents/corsix-ios/tools/pkgconf/bin:$PATH"`.
  vcpkg dependencies come from `/Users/ale/Documents/corsix-ios/vcpkg`
  (triplet `arm64-ios`); SDL 3.2.24 is fetched by CMake rather than taken from
  vcpkg.
- **Install / run / inspect:**
  - install: `xcrun devicectl device install app --device <udid> <app>`
  - launch: `xcrun devicectl device process launch --device <udid> com.wowee.client`
    (`--terminate-existing` restarts it)
  - screenshot: `xcrun devicectl device capture screenshot --device <udid> --destination <path.png>`
  - log: `Documents/config/logs/wowee.log` under the `appDataContainer`
    domain; config: `Documents/config/settings.cfg` the same way.
  - crash reports: `--domain-type systemCrashLogs`.
- **Orientation:** landscape, forced through `SDL_HINT_ORIENTATIONS` and the
  Info.plist (the plist is generated at CMake configure time, so a plist edit
  needs a reconfigure).
- **Configuration root:** `core::getConfigRoot()` resolves to the app's
  `Documents/config/` on iOS. Nothing may write to `HOME`; on iOS that is
  outside the sandbox and the write fails with `EPERM`. See commit `f5968c1c`.

## 8. Performance on the M3 (iPad Air 11")

Measured 2026-11-10 on an iPad Air 11" (M3), 2360x1640.

- **The numbers below were measured on a Debug build, and a Debug build is not
  a measurement of anything.** `enableValidation` follows `NDEBUG`
  (`include/rendering/vk_context.hpp`), so a Debug build loads the Khronos
  validation layer, which intercepts and checks every Vulkan call - and the
  renderer makes thousands of them per frame. A Debug build also compiles at
  `-Og` rather than `-O3`. `cmake/ios.toolchain.cmake` now defaults to
  Release, for that reason.

  It also inflates the GPU numbers, which is the part that makes it
  misleading rather than merely slow: the marks are
  `VK_PIPELINE_STAGE_BOTTOM_OF_PIPE` timestamps, so they measure elapsed
  GPU-queue time *including the gaps*. If the CPU cannot record the frame
  fast enough the GPU starves, and the gap is charged to whichever pass it
  lands in. "The world pass is 63.5 ms of 76" may be starvation rather
  than fragment work.

  So the first thing a Release build has to answer is whether the frame is
  still 76 ms of GPU time. If it is not, nothing below needs chasing.
- **The frame is GPU-bound.** Every render stage is under 50 ms except
  `endFrame`, which sits continuously at **75-80 ms** - post-process, the UI
  overlay, submit and the present wait. That is ~13 fps at native resolution,
  and ~9 fps in the denser parts of the world. Vsync cannot help when the GPU
  itself is the bottleneck.
- **The 30 -> 20 -> 15 -> 12 fps steps are vsync quantisation, not a cap.**
  They are 60 Hz vsync intervals of 2, 3, 4 and 5 (33, 50, 67 and 83 ms),
  and a 76 ms GPU frame lands in the fifth one. The frame cap is unlimited
  by default (`frameCapFpsForChoice(0)` returns 0).
- **The resolution selector now sets the internal resolution, upscaled by
  FSR1** (`56eb6fae`), and the list it offers is derived from the device's
  own screen (`00c74bf4`). On a platform that can resize its window
  nothing changes; on the iPad the world is drawn at the requested size and
  stretched onto the surface. Measured on the device:
  `FSR: initializing at 1036x720 -> 2360x1640 (scale=0.67)`.
- **FSR1 upscaling is already wired** and should work on iPad:
  `setFSREnabled` / `setFSRQuality` in `PostProcessPipeline`, with the
  client's own EASU/RCAS shaders (`fsr_easu.frag.spv`, `fsr_rcas.frag.spv`)
  bundled in the app. On Apple only *frame generation* is forced off; the
  upscaling path itself is not. Enabling FSR1 forces MSAA off
  (`MsaaChangeRequest`). Quality choices map to a render scale of
  {0.77, 0.67, 0.59, 1.00} (`fsrScaleForChoice` in
  `include/ui/graphics_choices.hpp`).
- **FSR2/FSR3** need `shaderStorageImageWriteWithoutFormat` and
  `shaderInt16`; `setFSR2Enabled` refuses with a warning when the device
  cannot provide them.
- **MetalFX is Metal-only, but MoltenVK can hand over Metal objects.**
  MetalFX (`MTLFXSpatialScaler`, `MTLFXTemporalScaler`) has no Vulkan
  surface, so it cannot be called from the renderer directly. The bridge is
  `VK_EXT_metal_objects`, which **MoltenVK 1.4.2 supports on iOS 8.0+**
  (`MoltenVK/MoltenVK/Layers/MVKExtensions.def`:
  `MVK_EXTENSION(EXT_metal_objects, EXT_METAL_OBJECTS, DEVICE, 10.11, 8.0, 1.0)`).
  Its `getMetalObjects` implementation exports the device, the command queue,
  buffers, textures and shared events (`MVKDevice.mm`), so the pieces a
  MetalFX pass needs are all reachable.

  What is *not* settled is the surrounding work, which is why this is not
  simply "add MetalFX":
  - The extension is a **device** extension and is **off by default**.
    MoltenVK enables extensions only when asked
    (`MVKExtension::MVKExtension` sets `enabled = enableForPlatform && ...`),
    so the client must enable it explicitly alongside its other
    `enable_extension_if_present` calls.
  - MetalFX encodes into an `MTLCommandBuffer`; the client's frame is a
    Vulkan command buffer on MoltenVK's queue. Ordering the two needs
    `MTLSharedEvent` plumbing that `VK_EXT_metal_objects` also provides, but
    nothing in this codebase does it yet.
  - The client's render targets would have to be created so that the Metal
    side can use them, and the final upscale has to land back in a Vulkan
    image the present path can read.
  - `MTLFXTemporalScaler` additionally wants depth and motion vectors. The
    client has a motion-vector pass (`dispatchMotionVectors`), so that part
    is in reach; `MTLFXSpatialScaler` wants colour only.

  So the route is open but it is a project, not a flag. FSR1 is the
  Vulkan-native equivalent and is already wired.

### Open performance work (next session)

1. **Rebuild Release and re-measure.** Everything measured so far was
   measured on a Debug build with the validation layer loaded, which is not a
   measurement of the client. `tools/ios-fsr-measure.sh` does the
   comparison; it needs a Release build to be worth anything.
2. If the frame is still 76 ms of GPU time after that, the levers in order
   of cost on a tiler:
   - `antialiasing=0` - 2x MSAA at 2360x1640 is 7.7M samples and a
     full-screen resolve.
   - `pom=0` - 32 parallax steps per pixel on WMO and character surfaces.
   - the resolution selector, now that it sets the internal resolution.
   - `shadowdistance` 300 -> 150, and the view distance.
   - the heavy settings in the saved profile (16x aniso, particles 100%,
     water refraction), and a working pipeline cache on iOS.

   `tools/ios-fsr-measure.sh` measures against a baseline and prints both.
