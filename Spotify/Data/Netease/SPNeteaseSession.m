//
//  SPNeteaseSession.m
//  Spotify
//

#import "SPNeteaseSession.h"
#import "SPHTTPClient.h"
#import "SPKeychainStore.h"

NSString * const SPNeteaseDefaultBaseURL = @"https://msapi.awup.cn";

static NSString * const SPNeteaseBaseURLDefaultsKey = @"sp_netease_base_url_v1";
static NSString * const SPNeteaseAnonCookieDefaultsKey = @"sp_netease_anon_cookie_v1";
static NSString * const SPNeteaseAnonTimestampDefaultsKey = @"sp_netease_anon_ts_v1";
static NSString * const SPNeteaseUserCookieKeychainKey = @"sp.netease.user.cookie.v1";
static NSString * const SPNeteaseUserIdKeychainKey = @"sp.netease.user.id.v1";

static const NSTimeInterval SPAnonCookieTTL = 12 * 3600.0;

@interface SPNeteaseSession ()
@property (nonatomic, strong) NSMutableArray<void (^)(NSString *_Nullable)> *pendingWaiters;
@property (nonatomic, assign) BOOL fetchingAnonCookie;
@end

@implementation SPNeteaseSession

+ (instancetype)shared {
    static SPNeteaseSession *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SPNeteaseSession new]; });
    return instance;
}

+ (NSString *)baseURLString {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:SPNeteaseBaseURLDefaultsKey];
    return saved.length > 0 ? saved : SPNeteaseDefaultBaseURL;
}

+ (void)setBaseURLString:(NSString *)baseURLString {
    NSString *trimmed = [baseURLString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([trimmed hasSuffix:@"/"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    if (trimmed.length == 0) {
        trimmed = SPNeteaseDefaultBaseURL;
    } else if (![trimmed hasPrefix:@"http://"] && ![trimmed hasPrefix:@"https://"]) {
        trimmed = [@"https://" stringByAppendingString:trimmed];
    }
    [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:SPNeteaseBaseURLDefaultsKey];
}

- (instancetype)init {
    if (self = [super init]) {
        _pendingWaiters = [NSMutableArray array];
        _userCookie = [SPKeychainStore stringForKey:SPNeteaseUserCookieKeychainKey];
        _userId = [SPKeychainStore stringForKey:SPNeteaseUserIdKeychainKey];

        NSTimeInterval ts = [[NSUserDefaults standardUserDefaults] doubleForKey:SPNeteaseAnonTimestampDefaultsKey];
        if (ts > 0 && (CFAbsoluteTimeGetCurrent() - ts) < SPAnonCookieTTL) {
            _anonymousCookie = [[NSUserDefaults standardUserDefaults] stringForKey:SPNeteaseAnonCookieDefaultsKey];
        }
    }
    return self;
}

- (void)setUserCookie:(NSString *)userCookie {
    @synchronized (self) {
        _userCookie = [userCookie copy];
        if (userCookie.length > 0) {
            [SPKeychainStore setString:userCookie forKey:SPNeteaseUserCookieKeychainKey];
        } else {
            [SPKeychainStore deleteValueForKey:SPNeteaseUserCookieKeychainKey];
        }
    }
}

- (void)setUserId:(NSString *)userId {
    @synchronized (self) {
        _userId = [userId copy];
        if (userId.length > 0) {
            [SPKeychainStore setString:userId forKey:SPNeteaseUserIdKeychainKey];
        } else {
            [SPKeychainStore deleteValueForKey:SPNeteaseUserIdKeychainKey];
        }
    }
}

- (void)setAnonymousCookie:(NSString *)anonymousCookie {
    @synchronized (self) {
        _anonymousCookie = [anonymousCookie copy];
        if (anonymousCookie.length > 0) {
            [[NSUserDefaults standardUserDefaults] setObject:anonymousCookie forKey:SPNeteaseAnonCookieDefaultsKey];
            [[NSUserDefaults standardUserDefaults] setDouble:CFAbsoluteTimeGetCurrent() forKey:SPNeteaseAnonTimestampDefaultsKey];
        } else {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:SPNeteaseAnonCookieDefaultsKey];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:SPNeteaseAnonTimestampDefaultsKey];
        }
    }
}

- (NSString *)activeCookie {
    @synchronized (self) {
        if (self.userCookie.length > 0) return self.userCookie;
        if (self.anonymousCookie.length > 0) return self.anonymousCookie;
        return nil;
    }
}

- (void)ensureCookieWithClient:(SPHTTPClient *)client completion:(void (^)(NSString * _Nullable))completion {
    NSString *existing = [self activeCookie];
    if (existing.length > 0) {
        if (completion) completion(existing);
        return;
    }

    BOOL shouldStart = NO;
    @synchronized (self) {
        NSString *doubleCheck = (self.userCookie.length > 0) ? self.userCookie : self.anonymousCookie;
        if (doubleCheck.length > 0) {
            if (completion) completion(doubleCheck);
            return;
        }
        if (completion) [self.pendingWaiters addObject:[completion copy]];
        if (!self.fetchingAnonCookie) {
            self.fetchingAnonCookie = YES;
            shouldStart = YES;
        }
    }

    if (!shouldStart) return;

    __weak typeof(self) weakSelf = self;
    [client GET:@"/register/anonimous" parameters:nil cookie:nil bypassCache:YES completion:^(NSDictionary *json, NSError *error) {
        NSString *cookie = [json[@"cookie"] isKindOfClass:NSString.class] ? json[@"cookie"] : nil;
        NSArray<void (^)(NSString *)> *waiters = nil;
        @synchronized (weakSelf) {
            if (cookie.length > 0) {
                weakSelf.anonymousCookie = cookie;
            }
            weakSelf.fetchingAnonCookie = NO;
            waiters = [weakSelf.pendingWaiters copy];
            [weakSelf.pendingWaiters removeAllObjects];
        }
        NSString *resolved = [weakSelf activeCookie] ?: cookie;
        for (void (^block)(NSString *) in waiters) {
            block(resolved);
        }
    }];
}

- (void)clearUserSession {
    self.userCookie = nil;
    self.userId = nil;
}

@end
