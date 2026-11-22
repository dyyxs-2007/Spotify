//
//  SPUser.h
//  Spotify
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPUser : NSObject

@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *account;       ///< 手机号或邮箱
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, copy) NSString *planName;      ///< 如 "Spotify Free" / "Premium 体验版"
@property (nonatomic, copy, nullable) NSString *accessToken;
@property (nonatomic, copy, nullable) NSString *refreshToken;
@property (nonatomic, copy, nullable) NSString *cookie;
@property (nonatomic, assign) NSTimeInterval createdAt;

/// 头像首字母（默认取昵称首个可见字符大写）
@property (nonatomic, copy, readonly) NSString *avatarInitial;

@end

NS_ASSUME_NONNULL_END
