//
//  SPLocalAuthProvider.h
//  Spotify
//
//  本地安全认证实现：随机盐 + SHA-256 密码哈希 + Keychain 用户存储 + 6 位时效验证码闭环。
//

#import <Foundation/Foundation.h>
#import "SPAuthProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPLocalAuthProvider : NSObject <SPAuthProvider>

+ (BOOL)isValidAccount:(NSString *)account;
+ (BOOL)isValidPassword:(NSString *)password;
/// 0=空/过短, 1=弱, 2=中, 3=强
+ (NSInteger)passwordStrengthFor:(NSString *)password;

@end

NS_ASSUME_NONNULL_END
