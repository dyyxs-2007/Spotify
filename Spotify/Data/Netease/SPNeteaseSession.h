//
//  SPNeteaseSession.h
//  Spotify
//
//  网易云音乐 API 会话与 Base URL 配置：
//  - 默认 Base URL: https://msapi.awup.cn
//  - 管理已登录用户 Cookie/UID（Keychain 持久化）与免登游客 Cookie（/register/anonimous）
//

#import <Foundation/Foundation.h>

@class SPHTTPClient;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SPNeteaseDefaultBaseURL;

@interface SPNeteaseSession : NSObject

+ (instancetype)shared;

@property (class, nonatomic, copy) NSString *baseURLString;

@property (nonatomic, copy, nullable) NSString *userCookie;
@property (nonatomic, copy, nullable) NSString *userId;
@property (nonatomic, copy, nullable) NSString *anonymousCookie;

- (nullable NSString *)activeCookie;

/// 确保存在可用 Cookie（优先用户登录态，其次缓存的游客态，必要时合并并发获取 /register/anonimous）
- (void)ensureCookieWithClient:(SPHTTPClient *)client
                    completion:(void (^)(NSString *_Nullable cookie))completion;

- (void)clearUserSession;

@end

NS_ASSUME_NONNULL_END
