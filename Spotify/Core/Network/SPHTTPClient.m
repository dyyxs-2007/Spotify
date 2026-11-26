//
//  SPHTTPClient.m
//  Spotify
//

#import "SPHTTPClient.h"

NSErrorDomain const SPHTTPErrorDomain = @"com.dyyxs.spotify.http";

@interface SPHTTPClient ()
@property (nonatomic, strong) NSURL *baseURL;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation SPHTTPClient

- (instancetype)initWithBaseURL:(NSURL *)baseURL {
    if (self = [super init]) {
        _baseURL = baseURL;
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 15.0;
        config.timeoutIntervalForResource = 30.0;
        config.HTTPMaximumConnectionsPerHost = 6;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.HTTPShouldSetCookies = NO;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)dealloc {
    [_session finishTasksAndInvalidate];
}

- (NSURL *)endpointURLForPath:(NSString *)path queryItems:(nullable NSArray<NSURLQueryItem *> *)extraItems {
    NSString *trimmedPath = [path hasPrefix:@"/"] ? [path substringFromIndex:1] : path;
    NSURL *raw = [self.baseURL URLByAppendingPathComponent:trimmedPath];
    NSURLComponents *comps = [NSURLComponents componentsWithURL:raw resolvingAgainstBaseURL:NO];
    if (extraItems.count > 0) {
        NSMutableArray<NSURLQueryItem *> *merged = [NSMutableArray arrayWithArray:comps.queryItems ?: @[]];
        [merged addObjectsFromArray:extraItems];
        comps.queryItems = merged;
    }
    return comps.URL ?: raw;
}

- (NSURLSessionDataTask *)GET:(NSString *)path
                   parameters:(NSDictionary<NSString *, id> *)params
                       cookie:(NSString *)cookie
                  bypassCache:(BOOL)bypassCache
                   completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    for (NSString *key in params) {
        id val = params[key];
        if (!val || val == NSNull.null) continue;
        [items addObject:[NSURLQueryItem queryItemWithName:key value:[NSString stringWithFormat:@"%@", val]]];
    }
    if (cookie.length > 0) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"cookie" value:cookie]];
    }
    if (bypassCache) {
        long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        [items addObject:[NSURLQueryItem queryItemWithName:@"timestamp" value:[NSString stringWithFormat:@"%lld", ts]]];
    }

    NSURL *url = [self endpointURLForPath:path queryItems:items];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    [req setValue:@"SpotifyiOS/1.0" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    return [self executeRequest:req completion:completion];
}

- (NSURLSessionDataTask *)POST:(NSString *)path
                    parameters:(NSDictionary<NSString *, id> *)params
                        cookie:(NSString *)cookie
                    completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
    NSURL *url = [self endpointURLForPath:path queryItems:@[
        [NSURLQueryItem queryItemWithName:@"timestamp" value:[NSString stringWithFormat:@"%lld", ts]]
    ]];

    NSMutableDictionary *bodyDict = [NSMutableDictionary dictionaryWithDictionary:params ?: @{}];
    if (cookie.length > 0) {
        bodyDict[@"cookie"] = cookie;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"SpotifyiOS/1.0" forHTTPHeaderField:@"User-Agent"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];

    return [self executeRequest:req completion:completion];
}

- (NSURLSessionDataTask *)executeRequest:(NSURLRequest *)request
                              completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (!data || data.length == 0) {
            NSError *emptyErr = [NSError errorWithDomain:SPHTTPErrorDomain
                                                    code:(http ? http.statusCode : -1)
                                                userInfo:@{NSLocalizedDescriptionKey: @"服务器未返回数据"}];
            if (completion) completion(nil, emptyErr);
            return;
        }

        NSError *jsonErr = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || ![obj isKindOfClass:NSDictionary.class]) {
            NSError *parseErr = [NSError errorWithDomain:SPHTTPErrorDomain
                                                    code:(http ? http.statusCode : -2)
                                                userInfo:@{NSLocalizedDescriptionKey: @"响应格式解析失败"}];
            if (completion) completion(nil, parseErr);
            return;
        }

        NSDictionary *dict = (NSDictionary *)obj;
        NSInteger apiCode = [dict[@"code"] respondsToSelector:@selector(integerValue)] ? [dict[@"code"] integerValue] : 200;
        BOOL httpOK = (!http || (http.statusCode >= 200 && http.statusCode < 300));
        if (!httpOK || apiCode != 200) {
            NSString *msg = [dict[@"message"] isKindOfClass:NSString.class] ? dict[@"message"]
                          : ([dict[@"msg"] isKindOfClass:NSString.class] ? dict[@"msg"] : nil);
            if (msg.length == 0) {
                msg = [NSString stringWithFormat:@"请求失败 (code=%ld)", (long)(!httpOK && http ? http.statusCode : apiCode)];
            }
            NSError *apiErr = [NSError errorWithDomain:SPHTTPErrorDomain
                                                  code:apiCode
                                              userInfo:@{NSLocalizedDescriptionKey: msg, @"payload": dict}];
            if (completion) completion(nil, apiErr);
            return;
        }

        if (completion) completion(dict, nil);
    }];
    [task resume];
    return task;
}

@end
