//
//  SPNeteaseAuthProvider.h
//  Spotify
//
//  基于网易云音乐 API (/captcha/sent, /login/cellphone, /login/qr/*, /login/status) 的认证通道。
//

#import <Foundation/Foundation.h>
#import "SPAuthProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPNeteaseAuthProvider : NSObject <SPAuthProvider>

- (instancetype)initWithBaseURLString:(NSString *)baseURLString;

#pragma mark - QR Code Login (推荐：无网易云盾风控)
- (void)createQRCodeWithCompletion:(void (^)(NSString *_Nullable unikey, NSString *_Nullable qrURL, NSError *_Nullable error))completion;

/// statusCode: 800=过期, 801=等待扫码, 802=待确认, 803=授权成功(含 cookie)
- (void)checkQRStatusForKey:(NSString *)unikey
                 completion:(void (^)(NSInteger statusCode, NSString *_Nullable message, NSString *_Nullable cookie, NSError *_Nullable error))completion;

- (void)fetchUserProfileWithCookie:(NSString *)cookie
                        completion:(void (^)(SPUser *_Nullable user, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
