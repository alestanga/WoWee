#include "core/ios_platform.hpp"

#include "core/logger.hpp"
#include <cstdlib>

#if defined(__APPLE__)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern "C" int SDL_main(int argc, char* argv[]);
extern "C" void SDL_SetMainReady(void);

// Custom scene delegate in the main binary, so UIKit can always find it.
@interface WoWeeSceneDelegate : UIResponder <UISceneDelegate>
@end

@implementation WoWeeSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    NSBundle *bundle = [NSBundle mainBundle];
    UIViewController *vc = nil;
    NSString *screenname = [bundle objectForInfoDictionaryKey:@"UILaunchStoryboardName"];
    if (screenname) {
        @try {
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:screenname bundle:bundle];
            vc = [storyboard instantiateInitialViewController];
        } @catch (NSException *exception) {
            vc = nil;
        }
    }
    if (vc) {
        CGRect viewFrame = windowScene.coordinateSpace.bounds;
        UIWindow *launchWindow = [[UIWindow alloc] initWithWindowScene:windowScene];
        launchWindow.frame = viewFrame;
        launchWindow.windowLevel = UIWindowLevelNormal + 1.0;
        launchWindow.hidden = NO;
        launchWindow.rootViewController = vc;
    }

    [[NSFileManager defaultManager] changeCurrentDirectoryPath:[bundle resourcePath]];

    dispatch_async(dispatch_get_main_queue(), ^{
        SDL_SetMainReady();
        SDL_main(gArgc, gArgv);
    });
}
@end
#endif

namespace wowee {
namespace core {

namespace {
void (*gMemoryWarningCallback)() = nullptr;
int gArgc = 0;
char** gArgv = nullptr;
}

void iosPreparePlatform() {
#if defined(__APPLE__)
    @autoreleasepool {
        [UIApplication sharedApplication].idleTimerDisabled = YES;

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

void iosStoreArgs(int argc, char** argv) {
#if defined(__APPLE__)
    gArgc = argc;
    gArgv = argv;
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