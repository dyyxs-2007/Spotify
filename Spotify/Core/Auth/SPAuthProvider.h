//
//  SPAuthProvider.h
//  Spotify
//
//  认证通道协议 —— 认证层的"插座"。
//  当前默认使用 SPLocalAuthProvider；阶段四可替换为网易云/自研后端实现，UI 零修改。
//

#import <Foundation/Foundation.h>
#import "SPUser.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPAuthCodePurpose) {
    SPAuthCodePurposeLogin = 0,
    SPAuthCodePurposeRegister,
};

@protocol SPAuthProvider <NSObject>

- (NSString *)providerName;

/// 发送 6 位数字验证码（本地 Provider 会回传 debugCode 用于测试闭环；真实后端可传 nil）
- (void)sendVerificationCodeToAccount:(NSString *)account
                              purpose:(SPAuthCodePurpose)purpose
                           completion:(void (^)(BOOL success, NSString *_Nullable debugCode, NSError *_Nullable error))completion;

/// 注册新账号（带验证码校验）
- (void)registerWithAccount:(NSString *)account
                   password:(NSString *)password
           verificationCode:(NSString *)code
                   nickname:(nullable NSString *)nickname
                 completion:(void (^)(SPUser *_Nullable user, NSError *_Nullable error))completion;

/// 密码登录
- (void)loginWithAccount:(NSString *)account
                password:(NSString *)password
              completion:(void (^)(SPUser *_Nullable user, NSError *_Nullable error))completion;

/// 验证码登录
- (void)loginWithAccount:(NSString *)account
        verificationCode:(NSString *)code
              completion:(void (^)(SPUser *_Nullable user, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
