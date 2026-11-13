# WoWee on iPadOS / iOS

The iPadOS/iOS port. It mirrors `android/`: the shared C++ core is built by the
top-level `CMakeLists.txt` (with `CMAKE_SYSTEM_NAME=iOS`), and this directory
holds the Apple-side app shell, assets staging and build configuration.

See `docs/plan-ipados.md` for the plan and the measured device state.

## Status

Builds, installs, signs and plays in-world on an iPad Air 11" (M3). The app
bundle is built by CMake and driven with `xcodebuild`; there is no separate
`.xcodeproj` in this directory.

## Layout

- `ios/Info.plist` - bundle configuration: landscape, file sharing, Photos
  access, scene manifest
- `ios/LaunchScreen.storyboard` - launch screen
- `ios/Assets.xcassets` - app icons
- `cmake/ios.toolchain.cmake` - the iOS cross-compile toolchain

## Build

Requires macOS with Xcode and the iOS SDK. Three inputs sit beside the
source tree:

- **A vcpkg tree** (any clone with the ports registry) providing `openssl`,
  `glm` and `zlib` for the `arm64-ios` triplet. The vcpkg toolchain loads
  `cmake/ios.toolchain.cmake` through `VCPKG_CHAINLOAD_TOOLCHAIN_FILE`, so
  one configure command wires both.
- **MoltenVK 1.4.2**, linked statically so Vulkan runs on Metal. It is not
  part of this repository: clone the upstream release, which ships the
  prebuilt xcframework, into `extern/MoltenVK`:

  ```
  git clone --depth 1 --branch v1.4.2 \
      https://github.com/KhronosGroup/MoltenVK extern/MoltenVK
  ```

  The link falls back to dynamic lookup when the xcframework is absent, so
  a clone without it configures but does not run.
- **SDL 3.2.24**, fetched by CMake itself; nothing to install.

Configure and build (Release is the default - see the comment in
`cmake/ios.toolchain.cmake` for why a Debug build is not a measurement):

```
cmake -S . -B build-ios \
  -DCMAKE_TOOLCHAIN_FILE=<vcpkg>/scripts/buildsystems/vcpkg.cmake \
  -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=$PWD/cmake/ios.toolchain.cmake \
  -DVCPKG_TARGET_TRIPLET=arm64-ios \
  -DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM=<your-team-id> \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="iPhone Developer"
xcodebuild -project build-ios/wowee.xcodeproj -scheme wowee \
  -configuration Release -destination 'id=<udid>' build
```

If `CMakeLists.txt` changed, build twice: ZERO_CHECK regenerates the
`.xcodeproj` mid-build and the first compile can run with stale settings.

### Signing

Signing is automatic, with the team passed at configure time as above
(`XCODE_ATTRIBUTE_DEVELOPMENT_TEAM`; `CODE_SIGN_STYLE` is `Automatic` in
the generated project). The device must be registered to that team. One
gotcha with no fix in the project: the Mac's login keychain re-locks
periodically and CodeSign then fails with `errSecInternalComponent` until
it is unlocked again - unlock the keychain and rebuild.

**Build Release.** A Debug build is not a measurement of anything: it runs
the Khronos validation layer, which intercepts and checks every Vulkan call
(`enableValidation` follows `NDEBUG`, and `NDEBUG` is not defined in a
Debug build), and it compiles at `-Og` rather than `-O3`. The renderer makes
thousands of Vulkan calls per frame, so the difference is not a few percent.
A Debug build is for the crash it was built to catch.

The app bundle is written by the build. Install and run it with `devicectl`:

```
xcrun devicectl device install app --device <udid> <app>
xcrun devicectl device process launch --device <udid> com.wowee.client
```

MoltenVK is linked statically from `extern/MoltenVK` (cloned in Build above),
so Vulkan runs on Metal.

### Measuring

The per-stage and GPU breakdowns are logged at INFO, and the log keeps
warnings by default. Two keys in `settings.cfg` change that, and they are read
from the config file because an environment variable cannot reach an app on
iOS:

```
loglevel=info
frameprofile=1
```

`frameprofile=1` reports the same breakdowns at warning level, so they
survive the default log level. Both work in a Release build.

## Game data

The game data is the player's own: a full extraction is 19-35 GB, which no
tablet holds. Cut it down on the desktop first with the same tool Android
uses - it is platform-agnostic, and produces a tree with its own
`manifest.json` describing exactly what it kept:

```
tools/android/make_minimal_data.py \
    --source ~/Library/Application\ Support/Wowee/Data/expansions/wotlk \
    --out ~/Data-ipad \
    --profile world --maps all
```

`--source` is the directory holding `manifest.json`, which for a desktop
extraction is `Data/expansions/<id>/` - not `Data/`. The tool says so itself
if it is pointed at the wrong one.

Then copy the result onto the device. The client opens its data one file at
a time through `std::ifstream` - there is no archive reader - so the tree
arrives as ~200,000 loose files, and Apple's file sharing is slow with that
many. The script uses `devicectl`'s copy and reports progress:

```
tools/ios-copy-data.sh --udid <udid> --source ~/Data-ipad
```

Finder works too (Files > On My iPad > WoWee > Documents) and is slower.
Either way the files land in `Documents/Data`, which is where the app points
`WOW_DATA_PATH`; it finds the expansion under `Data/expansions/<id>/`.

| Profile | Size | Reaches |
|---|---|---|
| `login` | 890 MB | Login screen, character select and creation. No world. |
| `world --maps azeroth` | 7.3 GB | One continent |
| `world --maps all` | 11.8 GB | Every map, no sound |
| `full` | 18 GB | Everything, sound included |

Neither `login` nor `world` carries any sound: the matcher is an allowlist and
`sound/` is in none of their include lists. The client names 265 sound files
and `sound/` is 6 GB; the game runs without them.

`full` is `**` minus the macOS `.app` bundles, the manual and the cinematics,
so it keeps sound on its own - `--with-sound` is only for the combination of
one continent *and* sound, which no stock profile expresses.

`tools/android/README.md` documents the profiles and the checker that verifies
one against the paths the client names.

## Configuration

`core::getConfigRoot()` resolves to the app's `Documents/config/` on iOS.
Nothing may write to `HOME`; there it is outside the sandbox and the write
fails with `EPERM`. The log is at `Documents/config/logs/wowee.log`.

Screenshots are saved to `Documents/config/screenshots/` and also into the
photo library, so they show up in Photos alongside the tablet's own. `/share`
offers the last one through the iOS share sheet.

## Testing notes

What the port has been exercised on:

- **Device and OS:** iPad Air 11" (M3, `iPad15,3`), iPadOS 27.2, landscape,
  Release build, external keyboard and trackpad/mouse.
- **Game data:** WotLK 3.3.5a (`Data/expansions/wotlk`), reduced with
  `tools/android/make_minimal_data.py`. Login, character select and
  in-world play are verified. The Vanilla 1.12 and TBC 2.4.3 protocol paths
  are the shared desktop code and were not exercised on the device.
- **Performance:** a steady 20 fps in-world at 786x546 internal (FSR1 to
  the panel's 2360x1640), GPU-bound. `frameprofile=1` logs per-stage CPU
  and GPU times, and `docs/plan-ipados.md` section 8 has the measured
  attribution and the lever list. The same frame time held through an
  8-hour continuous run, with no crashes.
- **Isolation:** every source file the port touches compiles in a host
  (non-iOS) configuration, and the platform-specific pieces sit behind
  `WOWEE_IOS` / `__ANDROID__` / `if(CMAKE_SYSTEM_NAME STREQUAL "iOS")`.

## Known not to work yet

- **Touch input is untested on the iPad.** Android's touch controls are
  compiled in and hidden behind the same mouse-present check, but the port
  has only ever been driven by keyboard and mouse; fingers have not been
  tried.
- **Eight shaders in `assets/shaders` have no built `.spv`** - the build
  machine has no `glslc`. The client loads three of them at startup, logs
  an error and continues: `grass_cull.comp` (GPU grass culling),
  `m2_cull_hiz.comp` (M2 occlusion culling) and `world_map_fog.frag`
  (the world-map fog overlay). Building the eight needs `glslc`.
- **No sound** with the `login` and `world` data profiles; only `full`
  carries `sound/`.
- **Doodads drop out of very dense scenes**: the M2 instance buffer holds
  32,768 instances and logs `instance buffer full` when it runs out.
- **Warden anti-cheat modules do not run** (its loader cannot execute the
  Windows module); the client warns and plays.
- **20 fps in-world**, which is a measurement, not a mystery: the frame is
  GPU-bound (see section 8 of the plan), the same 50.00 ms frame holds for
  hours, and a frame cap (`frame_cap`) and a lower render scale
  (the resolution selector) are both already in place and were measured.
