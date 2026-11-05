#include "core/ios_platform.hpp"

#include "core/logger.hpp"
#include <cstdlib>

#if defined(__APPLE__)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#endif

namespace wowee {
namespace core {

void iosPreparePlatform() {
#if defined(__APPLE__)
    @autoreleasepool {
        // Placeholder for iOS-specific setup (status bar, safe areas, keyboard).
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

        // Keep config and any unpacked resources under Documents so they survive
        // and are reachable through file sharing.
        NSString* data = [docs stringByAppendingPathComponent:@"Data"];
        NSString* config = [docs stringByAppendingPathComponent:@"config"];

        [[NSFileManager defaultManager] createDirectoryAtPath:data
            withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:config
            withIntermediateDirectories:YES attributes:nil error:nil];

        setenv("WOWEE_RESOURCE_ROOT", docs.UTF8String, 1);
        setenv("WOW_DATA_PATH", data.UTF8String, 1);
        setenv("WOWEE_CONFIG_ROOT", config.UTF8String, 1);

        LOG_INFO("iOS data root: ", docs.UTF8String);
    }
#endif
}

} // namespace core
} // namespace wowee