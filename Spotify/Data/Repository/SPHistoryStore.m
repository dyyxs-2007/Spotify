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
@property (nonatomic, copy) NSString *activeScopeKey;
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
        _activeScopeKey = [self currentScopeKey];
        [self loadFromDefaults];
        [[SPAuthService shared] addObserver:self];
    }
    return self;
}

- (NSString *)currentScopeKey {
    SPUser *user = [SPAuthService shared].currentUser;
    return user.userId.length > 0 ? user.userId : (user.account.length > 0 ? user.account.lowercaseString : @"guest");
}

- (NSString *)scopedDefaultsKey {
    return [SPHistoryDefaultsKeyPrefix stringByAppendingString:(self.activeScopeKey.length ? self.activeScopeKey : @"guest")];
}

- (void)ensureScopeMatchesCurrentUserLocked {
    NSString *expected = [self currentScopeKey];
    if (![self.activeScopeKey isEqualToString:expected]) {
        self.activeScopeKey = expected;
        [self loadFromDefaults];
    }
}

- (void)reloadForCurrentUser {
    @synchronized (self) {
        self.activeScopeKey = [self currentScopeKey];
        [self loadFromDefaults];
    }
    dispatch_block_t block = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPHistoryDidUpdateNotification object:self];
    };
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    @synchronized (self) {
        if ([self.activeScopeKey isEqualToString:[self currentScopeKey]]) {
            return;
        }
    }
    [self reloadForCurrentUser];
}

- (NSArray<SPTrack *> *)recentTracks {
    @synchronized (self) {
        [self ensureScopeMatchesCurrentUserLocked];
        return [self.tracksStorage copy];
    }
}

- (void)recordTrack:(SPTrack *)track {
    if (!track || track.identifier.length == 0) return;

    @synchronized (self) {
        [self ensureScopeMatchesCurrentUserLocked];
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
    }
    dispatch_block_t block = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPHistoryDidUpdateNotification object:self];
    };
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}

- (void)clearHistory {
    @synchronized (self) {
        [self ensureScopeMatchesCurrentUserLocked];
        [self.tracksStorage removeAllObjects];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self scopedDefaultsKey]];
    }
    dispatch_block_t block = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPHistoryDidUpdateNotification object:self];
    };
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
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
