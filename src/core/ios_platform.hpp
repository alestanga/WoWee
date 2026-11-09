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

// Log every UIWindow in the active scene (class, frame, hidden, level,
// key state, root view controller) plus a follow-up sample 3s later.
// Diagnostic for black-screen bugs: shows whether something is covering
// the SDL window or the window never became visible.
void iosLogWindowStatus(const char* stage);

// Show a native alert dialog.  Used to surface missing-data warnings on
// iOS, where the client's ImGui UI may not be available yet.
void iosShowAlert(const char* title, const char* message);

// Store argc/argv from main() so the scene delegate can invoke SDL_main.
void iosStoreArgs(int argc, char** argv);

// Minimal scene delegate class name for Info.plist.
extern const char* iosSceneDelegateClassName();

} // namespace core
} // namespace wowee