//
//  SPAuthService.m
//  Spotify
//

#import "SPAuthService.h"
#import "SPLocalAuthProvider.h"
#import "SPNeteaseSession.h"
#import "SPMusicRepository.h"
#import "SPLibraryStore.h"
#import "SPHistoryStore.h"
#import "SPListeningStatsStore.h"
#import "SPPlayerService.h"
#import "SPKeychainStore.h"
#import <YYModel/YYModel.h>

static NSString * const SPSessionKeychainKey = @"sp.auth.current.session.v1";

@interface SPAuthService ()
@property (nonatomic, strong) NSHashTable<id<SPAuthObserver>> *observers;
@property (nonatomic, strong, nullable) SPUser *currentUser;
@end

@implementation SPAuthService

@synthesize currentUser = _currentUser;

+ (instancetype)shared {
    static SPAuthService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SPAuthService new]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _observers = [NSHashTable weakObjectsHashTable];
        _provider = [SPLocalAuthProvider new];
        [self restoreSessionFromKeychain];
    }
    return self;
}

- (nullable SPUser *)currentUser {
    @synchronized (self) {
        return _currentUser;
    }
}

- (void)setCurrentUser:(nullable SPUser *)currentUser {
    @synchronized (self) {
        _currentUser = currentUser;
    }
}

- (BOOL)isLoggedIn { return self.currentUser != nil; }

- (void)addObserver:(id<SPAuthObserver>)observer {
    if (!observer) return;
    @synchronized (self) {
        [self.observers addObject:observer];
    }
}

- (void)removeObserver:(id<SPAuthObserver>)observer {
    if (!observer) return;
    @synchronized (self) {
        [self.observers removeObject:observer];
    }
}

- (void)notifyUserChanged {
    dispatch_block_t work = ^{
        NSArray<id<SPAuthObserver>> *snapshot = nil;
        @synchronized (self) {
            snapshot = [self.observers.allObjects copy];
        }
        for (id<SPAuthObserver> observer in snapshot) {
            if ([observer respondsToSelector:@selector(authServiceDidChangeUser:)]) {
                [observer authServiceDidChangeUser:self];
            }
        }
    };
    if (NSThread.isMainThread) work(); else dispatch_async(dispatch_get_main_queue(), work);
}

#pragma mark - Persistence

- (void)restoreSessionFromKeychain {
    NSData *data = [SPKeychainStore dataForKey:SPSessionKeychainKey];
    if (!data) {
        [[SPNeteaseSession shared] clearUserSession];
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([json isKindOfClass:NSDictionary.class]) {
        SPUser *user = [SPUser yy_modelWithJSON:json];
        if (user.userId.length > 0 && user.account.length > 0) {
            self.currentUser = user;
        }
    }
    if (self.currentUser.cookie.length > 0) {
        [SPNeteaseSession shared].userCookie = self.currentUser.cookie;
        [SPNeteaseSession shared].userId = self.currentUser.userId;
    } else {
        [[SPNeteaseSession shared] clearUserSession];
    }
}

- (void)persistUserSession:(nullable SPUser *)user {
    BOOL accountChanged = NO;
    @synchronized (self) {
        SPUser *previousUser = _currentUser;
        accountChanged = (user == nil)
            || (previousUser == nil)
            || ![previousUser.userId isEqualToString:user.userId]
            || ![previousUser.account isEqualToString:user.account];

        _currentUser = user;
        if (user) {
            NSData *data = [user yy_modelToJSONData];
            if (data) [SPKeychainStore setData:data forKey:SPSessionKeychainKey];
            if (user.cookie.length > 0) {
                [SPNeteaseSession shared].userCookie = user.cookie;
                [SPNeteaseSession shared].userId = user.userId;
            } else {
                // 切换到本地/邮箱账号时清理残留的网易云 Cookie，防止跨账号歌单混用
                [[SPNeteaseSession shared] clearUserSession];
            }
        } else {
            [SPKeychainStore deleteValueForKey:SPSessionKeychainKey];
            [[SPNeteaseSession shared] clearUserSession];
        }
    }

    if (accountChanged) {
        // 退出登录、切换账号或新账号接入时，立即停止播放并复位为空白播放页待机态
        [[SPPlayerService shared] resetToEmptyState];
    }

    [[SPMusicRepository shared] clearMetadataCaches];
    [[SPLibraryStore shared] reloadForCurrentUser];
    [[SPHistoryStore shared] reloadForCurrentUser];
    [[SPListeningStatsStore shared] reloadForCurrentUser];
    [self notifyUserChanged];
}

- (void)adoptAuthenticatedUser:(SPUser *)user {
    if (!user || user.userId.length == 0) return;
    dispatch_block_t work = ^{
        [self persistUserSession:user];
    };
    if (NSThread.isMainThread) work(); else dispatch_async(dispatch_get_main_queue(), work);
}

#pragma mark - Actions

- (void)sendVerificationCodeToAccount:(NSString *)account
                              purpose:(SPAuthCodePurpose)purpose
                           completion:(void (^)(BOOL, NSString * _Nullable, NSError * _Nullable))completion {
    [self.provider sendVerificationCodeToAccount:account purpose:purpose completion:^(BOOL success, NSString *debugCode, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(success, debugCode, error);
        });
    }];
}

- (void)registerWithAccount:(NSString *)account
                   password:(NSString *)password
           verificationCode:(NSString *)code
                   nickname:(NSString *)nickname
                 completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    __weak typeof(self) weakSelf = self;
    [self.provider registerWithAccount:account
                              password:password
                      verificationCode:code
                              nickname:nickname
                            completion:^(SPUser *user, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (user && !error) [weakSelf persistUserSession:user];
            if (completion) completion(user, error);
        });
    }];
}

- (void)loginWithAccount:(NSString *)account
                password:(NSString *)password
              completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    __weak typeof(self) weakSelf = self;
    [self.provider loginWithAccount:account password:password completion:^(SPUser *user, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (user && !error) [weakSelf persistUserSession:user];
            if (completion) completion(user, error);
        });
    }];
}

- (void)loginWithAccount:(NSString *)account
        verificationCode:(NSString *)code
              completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    __weak typeof(self) weakSelf = self;
    [self.provider loginWithAccount:account verificationCode:code completion:^(SPUser *user, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (user && !error) [weakSelf persistUserSession:user];
            if (completion) completion(user, error);
        });
    }];
}

- (void)logout {
    [[SPNeteaseSession shared] clearUserSession];
    [self persistUserSession:nil];
}

@end
