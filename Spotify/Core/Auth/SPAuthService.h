//
//  SPAuthService.h
//  Spotify
//
//  全局认证门面：管理当前登录用户、Keychain 会话恢复与登出，
//  通过多播观察者通知首页/音乐库/抽屉/设置页同步刷新用户态。
//

#import <Foundation/Foundation.h>
#import "SPAuthProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class SPAuthService;

@protocol SPAuthObserver <NSObject>
@optional
- (void)authServiceDidChangeUser:(SPAuthService *)authService;
@end

@interface SPAuthService : NSObject

+ (instancetype)shared;

@property (nonatomic, strong) id<SPAuthProvider> provider;
@property (nonatomic, strong, readonly, nullable) SPUser *currentUser;
@property (nonatomic, assign, readonly, getter=isLoggedIn) BOOL loggedIn;

- (void)addObserver:(id<SPAuthObserver>)observer;
- (void)removeObserver:(id<SPAuthObserver>)observer;

- (void)sendVerificationCodeToAccount:(NSString *)account
                              purpose:(SPAuthCodePurpose)purpose
                           completion:(void (^)(BOOL success, NSString *_Nullable debugCode, NSError *_Nullable error))completion;

- (void)registerWithAccount:(NSString *)account
                   password:(NSString *)password
           verificationCode:(NSString *)code
                   nickname:(nullable NSString *)nickname
                 completion:(void (^)(SPUser *_Nullable user, NSError *_Nullable error))completion;

- (void)loginWithAccount:(NSString *)account
                password:(NSString *)password
              completion:(void (^)(SPUser *_Nullable user, NSError *_Nullable error))completion;

- (void)loginWithAccount:(NSString *)account
        verificationCode:(NSString *)code
              completion:(void (^)(SPUser *_Nullable user, NSError *_Nullable error))completion;

/// 直接采用已通过第三方/扫码鉴权获得的用户会话并广播通知
- (void)adoptAuthenticatedUser:(SPUser *)user;

- (void)logout;

@end

NS_ASSUME_NONNULL_END
