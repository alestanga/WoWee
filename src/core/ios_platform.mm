#include "core/ios_platform.hpp"

#include "core/logger.hpp"
#include <cstdlib>
#include <cstring>

#if defined(__APPLE__)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <SDL3/SDL_system.h>

extern "C" int SDL_main(int argc, char* argv[]);
extern "C" void SDL_SetMainReady(void);

// Globals for argc/argv, accessible from the scene delegate.
int gIosArgc = 0;
char** gIosArgv = nullptr;

// Custom scene delegate in the main binary, so UIKit can always find it.
@interface WoWeeSceneDelegate : UIResponder <UISceneDelegate>
@end

@implementation WoWeeSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;

    // Order probe: if this logs *after* "Window initialized", SDL created
    // its UIWindow before the scene existed - a window with no scene is
    // never displayed on iOS 13+, which is a black screen.
    //
    // Point the log at Documents/config first: this callback runs before
    // SDL_main's iosSetupDataPaths, and the logger latches its file on the
    // first line it writes - without this the rest of the run lands in
    // Library/Logs where nobody looks.
    if (!getenv("WOWEE_CONFIG_ROOT")) {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* docs = paths.firstObject;
        if (docs) {
            NSString* config = [docs stringByAppendingPathComponent:@"config"];
            [[NSFileManager defaultManager] createDirectoryAtPath:config
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
            setenv("WOWEE_CONFIG_ROOT", config.UTF8String, 1);
        }
    }
    LOG_WARNING("Scene willConnect: ", (void*)scene,
                " state=", (int)scene.activationState);

    NSBundle *bundle = [NSBundle mainBundle];
    [[NSFileManager defaultManager] changeCurrentDirectoryPath:[bundle resourcePath]];

    // Do NOT create a launch window or call SDL_main here.  SDL's app
    // delegate (didFinishLaunchingWithOptions) handles both: it creates
    // the launch window and schedules postFinishLaunch -> SDL_main.  Doing
    // it here too caused a second (stuck) launch window and a blocked
    // main thread.
}

// SDL's own scene delegate forwards these to SDL so the app lifecycle
// (foreground/background events, event pump state) tracks the scene.  We
// replace that delegate, so forward them here or SDL never learns the
// scene became active.
- (void)sceneDidBecomeActive:(UIScene *)scene {
    SDL_OnApplicationDidEnterForeground();
}
- (void)sceneWillResignActive:(UIScene *)scene {
    SDL_OnApplicationWillEnterBackground();
}
- (void)sceneWillEnterForeground:(UIScene *)scene {
    SDL_OnApplicationWillEnterForeground();
}
- (void)sceneDidEnterBackground:(UIScene *)scene {
    SDL_OnApplicationDidEnterBackground();
}
@end
#endif

namespace wowee {
namespace core {

namespace {
void (*gMemoryWarningCallback)() = nullptr;
}

void iosPreparePlatform() {
#if defined(__APPLE__)
    @autoreleasepool {
        [UIApplication sharedApplication].idleTimerDisabled = YES;

        // SDL creates its UIWindow in SDL_CreateWindow, and UIKit only
        // attaches a window to a scene that is already connected - a window
        // created before UIWindowScene connects gets no scene and is never
        // displayed (black screen while everything else runs).  SDL_main can
        // start before the system connects the scene, so pump the run loop
        // here until one exists.
        UIScene* scene = nil;
        for (UIScene* s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = s; break; }
        }
        if (!scene) {
            LOG_WARNING("UIWindowScene not connected yet - waiting");
            NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
            while (!scene && [deadline timeIntervalSinceNow] > 0.0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                for (UIScene* s in [UIApplication sharedApplication].connectedScenes) {
                    if ([s isKindOfClass:[UIWindowScene class]]) { scene = s; break; }
                }
            }
            LOG_WARNING(scene ? "UIWindowScene connected after pumping the run loop"
                              : "UIWindowScene STILL missing after 3s - window will not display");
        } else {
            LOG_WARNING("UIWindowScene already connected before window create");
        }

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

        NSString* data = [docs stringByAppendingPathComponent:@"Data"];
        NSString* config = [docs stringByAppendingPathComponent:@"config"];

        [[NSFileManager defaultManager] createDirectoryAtPath:data
            withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:config
            withIntermediateDirectories:YES attributes:nil error:nil];

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

void iosLogWindowStatus(const char* stage) {
#if defined(__APPLE__)
    @autoreleasepool {
        // Dump every UIWindow in every connected scene, plus (via deprecated
        // but functional UIApplication APIs, silenced locally) any window that
        // belongs to NO scene - SDL's window ends up in one of these buckets,
        // and a black screen means it is in the wrong one.
        NSMutableString* out = [NSMutableString
            stringWithFormat:@"Window status [%s]:", stage ? stage : "?"];

        NSSet<UIScene*>* scenes = [UIApplication sharedApplication].connectedScenes;
        [out appendFormat:@" %d scene(s)", (int)scenes.count];
        for (UIScene* s in scenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) {
                [out appendFormat:@"\n  scene %p (not a UIWindowScene)", (void*)s];
                continue;
            }
            UIWindowScene* ws = (UIWindowScene*)s;
            [out appendFormat:@"\n  scene %p state=%d bounds=%@ windows=%d",
                               (void*)s, (int)ws.activationState,
                               NSStringFromCGRect(ws.coordinateSpace.bounds),
                               (int)ws.windows.count];
            for (UIWindow* w in ws.windows) {
                [out appendFormat:@"\n    <%@ %p> frame=%@ hidden=%d alpha=%.2f "
                                    @"level=%.1f key=%d root=%@",
                                   NSStringFromClass([w class]), (void*)w,
                                   NSStringFromCGRect(w.frame), w.hidden ? 1 : 0,
                                   w.alpha, w.windowLevel, w.isKeyWindow ? 1 : 0,
                                   w.rootViewController
                                       ? NSStringFromClass([w.rootViewController class])
                                       : @"nil"];
            }
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // A window created without a scene never shows up in scene.windows -
        // this is where SDL's window would be if UIKit_GetActiveWindowScene()
        // returned nil at creation time.
        NSArray<UIWindow*>* allWindows = [UIApplication sharedApplication].windows;
        [out appendFormat:@"\n  UIApplication.windows: %d", (int)allWindows.count];
        for (UIWindow* w in allWindows) {
            [out appendFormat:@"\n    <%@ %p> scene=%p hidden=%d key=%d",
                               NSStringFromClass([w class]), (void*)w,
                               (void*)w.windowScene, w.hidden ? 1 : 0,
                               w.isKeyWindow ? 1 : 0];
        }
#pragma clang diagnostic pop
        // LOG_WARNING, not LOG_INFO: the config file drops the runtime level
        // to warning before the window exists, so an INFO line never shows up.
        LOG_WARNING(out.UTF8String);

        // One follow-up sample a few seconds later, once the app has settled:
        // the launch window fades out only after the main run loop starts
        // spinning, so the first sample can legitimately still show it.
        if (!stage || strncmp(stage, "t+", 2) != 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                             iosLogWindowStatus("t+3s");
                           });
        }
    }
#endif
}

void iosStoreArgs(int argc, char** argv) {
#if defined(__APPLE__)
    gIosArgc = argc;
    gIosArgv = argv;
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
                        NSArray<UIWindow*>* ws = ((UIWindowScene*)scene).windows;
                        if (ws.count > 0) { keyWindow = ws.firstObject; break; }
                    }
                }
            }
            if (!keyWindow) {
                for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                        NSArray<UIWindow*>* ws = ((UIWindowScene*)scene).windows;
                        if (ws.count > 0) { keyWindow = ws.firstObject; break; }
                    }
                }
            }
            UIViewController* root = keyWindow.rootViewController;
            if (root) [root presentViewController:alert animated:YES completion:nil];
        });
    }
#endif
}

const char* iosSceneDelegateClassName() {
    return "WoWeeSceneDelegate";
}

} // namespace core
} // namespace wowee