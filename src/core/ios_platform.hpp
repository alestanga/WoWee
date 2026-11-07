#pragma once

namespace wowee {
namespace core {

// iPadOS/iOS platform shims.  Mirrors macos_platform.hpp.
void iosPreparePlatform();

// Point the client at the app's Documents directory, which is the location
// exposed over USB/Finder via UIFileSharingEnabled, so the player can copy
// their extracted Data/ in.  Sets WOWEE_RESOURCE_ROOT, WOW_DATA_PATH and
// WOWEE_CONFIG_ROOT, mirroring WoweeActivity on Android.
void iosSetupDataPaths();

// Register a callback invoked when the OS issues a memory warning.  The
// client uses this to drop caches (textures, DBC, file cache) before the
// system terminates it.  Pass nullptr to clear.
void iosSetMemoryWarningCallback(void (*callback)());

} // namespace core
} // namespace wowee