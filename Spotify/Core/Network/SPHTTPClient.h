//
//  SPHTTPClient.h
//  Spotify
//
//  基于系统 NSURLSession 的轻量 JSON 网络客户端（支持时间戳防缓存与 Cookie 参数透传）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const SPHTTPErrorDomain;

@interface SPHTTPClient : NSObject

@property (nonatomic, strong, readonly) NSURL *baseURL;

- (instancetype)initWithBaseURL:(NSURL *)baseURL;

- (NSURLSessionDataTask *)GET:(NSString *)path
                   parameters:(nullable NSDictionary<NSString *, id> *)params
                       cookie:(nullable NSString *)cookie
                  bypassCache:(BOOL)bypassCache
                   completion:(void (^)(NSDictionary *_Nullable json, NSError *_Nullable error))completion;

- (NSURLSessionDataTask *)POST:(NSString *)path
                    parameters:(nullable NSDictionary<NSString *, id> *)params
                        cookie:(nullable NSString *)cookie
                    completion:(void (^)(NSDictionary *_Nullable json, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
