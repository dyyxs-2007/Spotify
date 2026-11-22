//
//  AppDelegate.m
//  Spotify
//

#import "AppDelegate.h"
#import "SPMusicRepository.h"
#import "SPMockMusicSource.h"
#import "SPNeteaseMusicSource.h"
#import "SPAuthService.h"
#import "SPLocalAuthProvider.h"
#import "SPNeteaseAuthProvider.h"

static NSString * const SPMusicSourceTypeDefaultsKey = @"sp_music_source_type_v1";
static NSString * const SPAuthProviderTypeDefaultsKey = @"sp_auth_provider_type_v1";

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSString *sourceType = [[NSUserDefaults standardUserDefaults] stringForKey:SPMusicSourceTypeDefaultsKey];
    if ([sourceType isEqualToString:@"mock"]) {
        [SPMusicRepository shared].source = [SPMockMusicSource new];
    } else {
        [SPMusicRepository shared].source = [SPNeteaseMusicSource new];
    }

    NSString *authType = [[NSUserDefaults standardUserDefaults] stringForKey:SPAuthProviderTypeDefaultsKey];
    if ([authType isEqualToString:@"netease"]) {
        [SPAuthService shared].provider = [SPNeteaseAuthProvider new];
    } else {
        [SPAuthService shared].provider = [SPLocalAuthProvider new];
    }

    // 图片缓存：内存上限 80MB
    SDImageCache.sharedImageCache.config.maxMemoryCost = 80 * 1024 * 1024;
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

@end
