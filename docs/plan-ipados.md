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

- **The frame is GPU-bound.** Every render stage is under 50 ms except
  `endFrame`, which sits continuously at **75-80 ms** - post-process, the UI
  overlay, submit and the present wait. That is ~13 fps at native resolution,
  and ~9 fps in the denser parts of the world. Vsync cannot help when the GPU
  itself is the bottleneck.
- **The resolution selector does nothing on iPad.** It is a window-size
  request, and SDL's UIKit backend has no `SetWindowSize` implementation at
  all, so the window stays at the native 2360x1640 and the swapchain is
  recreated at the same size. With `fullscreen=1` every 16:9 row fails the
  aspect guard against the iPad's ~1.44:1 display, so it keeps the desktop
  mode - also a no-op. It is not a render-scale control.
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
- **MetalFX is not reachable through MoltenVK.** It is a Metal-only API with
  no Vulkan surface. `VK_EXT_metal_objects` (interop with Metal's own
  resources) and `VK_EXT_fragment_density_map` exist in the bundled
  `vulkan_core.h`, but neither is a practical way to get MetalFX's spatial
  upscaler. FSR1 is the Vulkan-native equivalent.

### Open performance work (next session)

1. Measure FSR1 on the device. The device config has been pushed with
   `upscaling_mode=1`, `fsr_quality=1` (67%), `antialiasing=0`, `vsync=0`;
   the run was interrupted because the iPad was locked. Compare the
   `SLOW render stage 'endFrame'` lines against the 75-80 ms baseline.
2. If FSR1 works, the real win is a *render scale* (draw the world smaller,
   upscale), which is what the resolution selector should have been.
3. Other levers on the M3: the heavy settings in the saved profile (shadows
   300 yd, view distance 1900, POM, 16x aniso, particles 100%, water
   refraction), and a working pipeline cache on iOS.
