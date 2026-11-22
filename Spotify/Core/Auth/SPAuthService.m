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
#import "SPKeychainStore.h"
#import <YYModel/YYModel.h>

static NSString * const SPSessionKeychainKey = @"sp.auth.current.session.v1";

@interface SPAuthService ()
@property (nonatomic, strong) NSHashTable<id<SPAuthObserver>> *observers;
@property (nonatomic, strong, nullable) SPUser *currentUser;
@end

@implementation SPAuthService

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

- (BOOL)isLoggedIn { return self.currentUser != nil; }

- (void)addObserver:(id<SPAuthObserver>)observer { [self.observers addObject:observer]; }
- (void)removeObserver:(id<SPAuthObserver>)observer { [self.observers removeObject:observer]; }

- (void)notifyUserChanged {
    dispatch_block_t work = ^{
        for (id<SPAuthObserver> observer in self.observers.allObjects) {
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
    if (!data) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([json isKindOfClass:NSDictionary.class]) {
        SPUser *user = [SPUser yy_modelWithJSON:json];
        if (user.userId.length > 0 && user.account.length > 0) {
            self.currentUser = user;
        }
    }
}

- (void)persistUserSession:(nullable SPUser *)user {
    self.currentUser = user;
    if (user) {
        NSData *data = [user yy_modelToJSONData];
        if (data) [SPKeychainStore setData:data forKey:SPSessionKeychainKey];
    } else {
        [SPKeychainStore deleteValueForKey:SPSessionKeychainKey];
    }
    [[SPLibraryStore shared] reloadForCurrentUser];
    [[SPHistoryStore shared] reloadForCurrentUser];
    [[SPMusicRepository shared] clearMetadataCaches];
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
