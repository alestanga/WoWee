#pragma once

namespace wowee {
namespace core {

// iPadOS/iOS platform shims.  Mirrors macos_platform.hpp.  Real implementations
// (status bar, safe areas, on-screen keyboard, app lifecycle) land here as the
// port progresses.
void iosPreparePlatform();

// Point the client at the app's Documents directory, which is the location
// exposed over USB/Finder via UIFileSharingEnabled, so the player can copy
// their extracted Data/ in.  Sets WOWEE_RESOURCE_ROOT, WOW_DATA_PATH and
// WOWEE_CONFIG_ROOT, mirroring WoweeActivity on Android.
void iosSetupDataPaths();

} // namespace core
} // namespace wowee