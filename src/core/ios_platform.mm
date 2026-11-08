#include "core/ios_platform.hpp"

#include "core/logger.hpp"
#include <cstdlib>

#if defined(__APPLE__)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#endif

namespace wowee {
namespace core {

namespace {
void (*gMemoryWarningCallback)() = nullptr;
}

void iosPreparePlatform() {
#if defined(__APPLE__)
    @autoreleasepool {
        // Keep the screen awake while the client runs; a WoW session is long
        // and an auto-lock mid-pull is worse than a drained battery.
        [UIApplication sharedApplication].idleTimerDisabled = YES;

        // Hide the status bar on iPad/iPhone; the client is fullscreen.
        // Status bar visibility is owned by SDL's UIKit view controller
        // (prefersStatusBarHidden).  Nothing to do here beyond keeping the
        // screen awake, which is handled above.

        // Forward OS memory warnings to the registered callback.  SDL also
        // posts SDL_EVENT_LOW_MEMORY, but this guarantees the handler runs
        // even if the event queue is busy.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* /*note*/) {
                        if (gMemoryWarningCallback) gMemoryWarningCallback();
                    }];

        LOG_INFO("iOS platform prepared");
    }
#endif
}

void iosSetupDataPaths() {
#if defined(__APPLE__)
    @autoreleasepool {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* docs = paths.firstObject;
        if (!docs) return;

        // Keep config and game data under Documents so they survive and are
        // reachable through file sharing.
        NSString* data = [docs stringByAppendingPathComponent:@"Data"];
        NSString* config = [docs stringByAppendingPathComponent:@"config"];

        [[NSFileManager defaultManager] createDirectoryAtPath:data
            withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:config
            withIntermediateDirectories:YES attributes:nil error:nil];

        // Shipped assets (shaders, textures, interface) live in the app bundle's
        // Resources directory, not in Documents.  Point the resource root there
        // so enterResourceRoot() lands on assets/ and shaders resolve.
        NSString* resources = [[NSBundle mainBundle] resourcePath];
        if (resources) {
            setenv("WOWEE_RESOURCE_ROOT", resources.UTF8String, 1);
        }
        setenv("WOW_DATA_PATH", data.UTF8String, 1);
        setenv("WOWEE_CONFIG_ROOT", config.UTF8String, 1);

        LOG_INFO("iOS data root: ", docs.UTF8String);
        LOG_INFO("iOS resource root: ", resources ? resources.UTF8String : "(null)");
    }
#endif
}

void iosSetMemoryWarningCallback(void (*callback)()) {
#if defined(__APPLE__)
    gMemoryWarningCallback = callback;
#endif
}

void iosShowAlert(const char* title, const char* message) {
#if defined(__APPLE__)
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController* alert = [UIAlertController
                alertControllerWithTitle:(title ? [NSString stringWithUTF8String:title] : @"WoWee")
                               message:(message ? [NSString stringWithUTF8String:message] : @"")
                        preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                     style:UIAlertActionStyleDefault
                                                   handler:nil]];
            UIWindow* keyWindow = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
                    if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                        for (UIWindow* w in ((UIWindowScene*)scene).windows) {
                            if (w.isKeyWindow) { keyWindow = w; break; }
                        }
                        if (!keyWindow && ((UIWindowScene*)scene).windows.count > 0) {
                            keyWindow = ((UIWindowScene*)scene).windows.firstObject;
                        }
                        if (keyWindow) break;
                    }
                }
            }
            if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;
            UIViewController* root = keyWindow.rootViewController;
            if (root) [root presentViewController:alert animated:YES completion:nil];
        });
    }
#endif
}

} // namespace core
} // namespace wowee