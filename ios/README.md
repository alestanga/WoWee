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

Requires macOS with Xcode and the iOS SDK. vcpkg dependencies come from a
vcpkg tree using the `arm64-ios` triplet; SDL 3.2.24 is fetched by CMake
rather than taken from vcpkg.

```
cmake -S . -B build-ios \
  -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake
xcodebuild -project build-ios/wowee.xcodeproj -scheme wowee \
  -configuration Release -destination 'id=<udid>' build
```

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

MoltenVK is linked statically from `extern/MoltenVK`, so Vulkan runs on Metal.
It is not in this repository; see the plan for where it comes from.

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

Then copy the result into the app's Documents folder over USB with Finder
(Files > On My iPad > WoWee). The app points `WOW_DATA_PATH` at
`Documents/Data` and finds the expansion under `Data/expansions/<id>/`.

| Profile | Size | Reaches |
|---|---|---|
| `login` | 787 MB | Login screen, character select and creation. No world. |
| `world --maps azeroth` | 7.5 GB | One continent |
| `world --maps all` | 12 GB | Every map, no sound |
| `world --maps azeroth --with-sound` | 13.5 GB | One continent, with sound |
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
