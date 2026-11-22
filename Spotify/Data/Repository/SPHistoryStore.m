//
//  SPHistoryStore.m
//  Spotify
//

#import "SPHistoryStore.h"
#import "SPAuthService.h"
#import <YYModel/YYModel.h>

NSNotificationName const SPHistoryDidUpdateNotification = @"com.dyyxs.spotify.historyUpdated";
static NSString * const SPHistoryDefaultsKeyPrefix = @"com.dyyxs.spotify.recentTracks.";
static const NSUInteger SPHistoryMaxCount = 50;

@interface SPHistoryStore () <SPAuthObserver>
@property (nonatomic, strong) NSMutableArray<SPTrack *> *tracksStorage;
@end

@implementation SPHistoryStore

+ (instancetype)shared {
    static SPHistoryStore *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SPHistoryStore new]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _tracksStorage = [NSMutableArray array];
        [self loadFromDefaults];
        [[SPAuthService shared] addObserver:self];
    }
    return self;
}

- (NSString *)scopedDefaultsKey {
    SPUser *user = [SPAuthService shared].currentUser;
    NSString *scope = user.userId.length > 0 ? user.userId : (user.account.length > 0 ? user.account.lowercaseString : @"guest");
    return [SPHistoryDefaultsKeyPrefix stringByAppendingString:scope];
}

- (void)reloadForCurrentUser {
    [self loadFromDefaults];
    [[NSNotificationCenter defaultCenter] postNotificationName:SPHistoryDidUpdateNotification object:self];
}

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    [self reloadForCurrentUser];
}

- (NSArray<SPTrack *> *)recentTracks {
    return [self.tracksStorage copy];
}

- (void)recordTrack:(SPTrack *)track {
    if (!track || track.identifier.length == 0) return;

    NSUInteger existingIdx = [self.tracksStorage indexOfObjectPassingTest:^BOOL(SPTrack *obj, NSUInteger idx, BOOL *stop) {
        return [obj.identifier isEqualToString:track.identifier];
    }];
    if (existingIdx != NSNotFound) {
        [self.tracksStorage removeObjectAtIndex:existingIdx];
    }
    [self.tracksStorage insertObject:track atIndex:0];
    while (self.tracksStorage.count > SPHistoryMaxCount) {
        [self.tracksStorage removeLastObject];
    }
    [self saveToDefaults];
    [[NSNotificationCenter defaultCenter] postNotificationName:SPHistoryDidUpdateNotification object:self];
}

- (void)clearHistory {
    [self.tracksStorage removeAllObjects];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self scopedDefaultsKey]];
    [[NSNotificationCenter defaultCenter] postNotificationName:SPHistoryDidUpdateNotification object:self];
}

- (void)saveToDefaults {
    id jsonObj = [self.tracksStorage yy_modelToJSONObject];
    if ([jsonObj isKindOfClass:NSArray.class]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:jsonObj options:0 error:nil];
        if (data) {
            [[NSUserDefaults standardUserDefaults] setObject:data forKey:[self scopedDefaultsKey]];
        }
    }
}

- (void)loadFromDefaults {
    [self.tracksStorage removeAllObjects];
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:[self scopedDefaultsKey]];
    if (!data) return;
    id jsonObj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([jsonObj isKindOfClass:NSArray.class]) {
        NSArray *restored = [NSArray yy_modelArrayWithClass:SPTrack.class json:jsonObj];
        if (restored.count > 0) {
            [self.tracksStorage addObjectsFromArray:restored];
        }
    }
}

@end
