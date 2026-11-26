//
//  SPNeteaseAuthProvider.m
//  Spotify
//

#import "SPNeteaseAuthProvider.h"
#import "SPHTTPClient.h"
#import "SPNeteaseSession.h"
#import "SPNeteaseParser.h"

static NSErrorDomain const SPNeteaseAuthErrorDomain = @"com.dyyxs.spotify.auth.netease";

#define SP_AUTH_MAIN(block) \
    if (NSThread.isMainThread) { block(); } else { dispatch_async(dispatch_get_main_queue(), block); }

@interface SPNeteaseAuthProvider ()
@property (nonatomic, strong) SPHTTPClient *client;
@end

@implementation SPNeteaseAuthProvider

- (instancetype)init {
    return [self initWithBaseURLString:[SPNeteaseSession baseURLString]];
}

- (instancetype)initWithBaseURLString:(NSString *)baseURLString {
    if (self = [super init]) {
        NSURL *url = [NSURL URLWithString:baseURLString] ?: [NSURL URLWithString:SPNeteaseDefaultBaseURL];
        _client = [[SPHTTPClient alloc] initWithBaseURL:url];
    }
    return self;
}

- (NSString *)providerName {
    return [NSString stringWithFormat:@"网易云账号认证 (%@)", self.client.baseURL.host ?: @"msapi.awup.cn"];
}

- (NSError *)authError:(NSString *)message code:(NSInteger)code {
    return [NSError errorWithDomain:SPNeteaseAuthErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"认证请求失败"}];
}

- (SPUser *)parseUserFromAuthJSON:(NSDictionary *)json account:(NSString *)account fallbackCookie:(nullable NSString *)fallbackCookie {
    NSDictionary *profile = [SPNeteaseParser dictValue:json[@"profile"]];
    NSDictionary *acc = [SPNeteaseParser dictValue:json[@"account"]];
    NSString *cookie = [SPNeteaseParser stringValue:json[@"cookie"]] ?: fallbackCookie;
    NSString *uid = [SPNeteaseParser stringValue:profile[@"userId"]]
                 ?: [SPNeteaseParser stringValue:acc[@"id"]]
                 ?: account;

    SPUser *user = [SPUser new];
    user.userId = uid;
    user.account = account.length > 0 ? account : [NSString stringWithFormat:@"ID: %@", uid];
    user.nickname = [SPNeteaseParser stringValue:profile[@"nickname"]] ?: user.account;
    user.planName = ([profile[@"vipType"] respondsToSelector:@selector(integerValue)] && [profile[@"vipType"] integerValue] > 0)
        ? @"网易云 VIP" : @"网易云账号";
    user.cookie = cookie;
    user.accessToken = [SPNeteaseParser stringValue:json[@"token"]];
    user.createdAt = [[NSDate date] timeIntervalSince1970];
    return user;
}

#pragma mark - QR Login

- (void)createQRCodeWithCompletion:(void (^)(NSString * _Nullable, NSString * _Nullable, NSError * _Nullable))completion {
    __weak typeof(self) weakSelf = self;
    [self.client GET:@"/login/qr/key" parameters:nil cookie:nil bypassCache:YES completion:^(NSDictionary *json, NSError *error) {
        NSDictionary *data = [SPNeteaseParser dictValue:json[@"data"]];
        NSString *unikey = [SPNeteaseParser stringValue:data[@"unikey"]];
        if (error || unikey.length == 0) {
            SP_AUTH_MAIN(^{
                if (completion) completion(nil, nil, error ?: [weakSelf authError:@"获取二维码密钥失败" code:-201]);
            });
            return;
        }

        [weakSelf.client GET:@"/login/qr/create"
                  parameters:@{@"key": unikey}
                      cookie:nil
                 bypassCache:YES
                  completion:^(NSDictionary *createJson, NSError *createErr) {
            NSDictionary *createData = [SPNeteaseParser dictValue:createJson[@"data"]];
            NSString *qrURL = [SPNeteaseParser stringValue:createData[@"qrurl"]];
            SP_AUTH_MAIN(^{
                if (!createErr && qrURL.length > 0) {
                    if (completion) completion(unikey, qrURL, nil);
                } else {
                    if (completion) completion(nil, nil, createErr ?: [weakSelf authError:@"生成登录二维码失败" code:-202]);
                }
            });
        }];
    }];
}

- (void)checkQRStatusForKey:(NSString *)unikey
                 completion:(void (^)(NSInteger, NSString * _Nullable, NSString * _Nullable, NSError * _Nullable))completion {
    if (unikey.length == 0) {
        SP_AUTH_MAIN(^{
            if (completion) completion(0, nil, nil, [self authError:@"二维码 key 无效" code:-203]);
        });
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.client GET:@"/login/qr/check"
          parameters:@{@"key": unikey, @"noCookie": @"true"}
              cookie:nil
         bypassCache:YES
          completion:^(NSDictionary *json, NSError *error) {
        // /login/qr/check 的状态码 800/801/802/803 会进入 error.userInfo[@"payload"]
        NSDictionary *payload = json ?: [SPNeteaseParser dictValue:error.userInfo[@"payload"]];
        if (!payload) {
            SP_AUTH_MAIN(^{
                if (completion) completion(0, nil, nil, error ?: [weakSelf authError:@"检测扫码状态失败" code:-204]);
            });
            return;
        }
        NSInteger statusCode = [payload[@"code"] respondsToSelector:@selector(integerValue)] ? [payload[@"code"] integerValue] : 0;
        NSString *msg = [SPNeteaseParser stringValue:payload[@"message"]] ?: [SPNeteaseParser stringValue:payload[@"msg"]];
        NSString *cookie = [SPNeteaseParser stringValue:payload[@"cookie"]];
        SP_AUTH_MAIN(^{
            if (completion) completion(statusCode, msg, cookie, nil);
        });
    }];
}

- (void)fetchUserProfileWithCookie:(NSString *)cookie
                        completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    if (cookie.length == 0) {
        SP_AUTH_MAIN(^{
            if (completion) completion(nil, [self authError:@"登录凭证缺失" code:-205]);
        });
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.client GET:@"/login/status" parameters:nil cookie:cookie bypassCache:YES completion:^(NSDictionary *json, NSError *error) {
        NSDictionary *data = [SPNeteaseParser dictValue:json[@"data"]];
        NSDictionary *profile = [SPNeteaseParser dictValue:data[@"profile"]];
        if (error || !profile) {
            SP_AUTH_MAIN(^{
                if (completion) completion(nil, error ?: [weakSelf authError:@"获取网易云账号资料失败" code:-206]);
            });
            return;
        }
        SPUser *user = [weakSelf parseUserFromAuthJSON:data account:@"" fallbackCookie:cookie];
        SP_AUTH_MAIN(^{
            if (completion) completion(user, nil);
        });
    }];
}

#pragma mark - SPAuthProvider

- (void)sendVerificationCodeToAccount:(NSString *)account
                              purpose:(SPAuthCodePurpose)purpose
                           completion:(void (^)(BOOL, NSString * _Nullable, NSError * _Nullable))completion {
    NSString *trimmed = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSPredicate *phonePred = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^1[3-9]\\d{9}$"];
    if (![phonePred evaluateWithObject:trimmed]) {
        SP_AUTH_MAIN(^{
            if (completion) completion(NO, nil, [self authError:@"网易云验证码仅支持 11 位中国大陆手机号" code:-101]);
        });
        return;
    }

    [self.client GET:@"/captcha/sent"
          parameters:@{@"phone": trimmed, @"ctcode": @"86"}
              cookie:nil
         bypassCache:YES
          completion:^(NSDictionary *json, NSError *error) {
        SP_AUTH_MAIN(^{
            if (error) {
                if (completion) completion(NO, nil, error);
            } else {
                if (completion) completion(YES, nil, nil);
            }
        });
    }];
}

- (void)registerWithAccount:(NSString *)account
                   password:(NSString *)password
           verificationCode:(NSString *)code
                   nickname:(NSString *)nickname
                 completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    NSString *trimmed = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || code.length == 0 || password.length < 8) {
        SP_AUTH_MAIN(^{
            if (completion) completion(nil, [self authError:@"请填写完整手机号、验证码与至少 8 位密码" code:-102]);
        });
        return;
    }
    NSString *name = [nickname stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) name = @"听友";

    __weak typeof(self) weakSelf = self;
    [self.client POST:@"/register/cellphone"
           parameters:@{@"phone": trimmed, @"password": password, @"captcha": code, @"nickname": name}
               cookie:nil
           completion:^(NSDictionary *json, NSError *error) {
        SP_AUTH_MAIN(^{
            if (error || !json) {
                if (completion) completion(nil, error ?: [weakSelf authError:@"注册失败" code:-103]);
                return;
            }
            if (completion) completion([weakSelf parseUserFromAuthJSON:json account:trimmed fallbackCookie:nil], nil);
        });
    }];
}

- (void)loginWithAccount:(NSString *)account
                password:(NSString *)password
              completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    NSString *trimmed = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || password.length == 0) {
        SP_AUTH_MAIN(^{
            if (completion) completion(nil, [self authError:@"请输入账号与密码" code:-104]);
        });
        return;
    }

    BOOL isEmail = [trimmed containsString:@"@"];
    NSString *path = isEmail ? @"/login" : @"/login/cellphone";
    NSDictionary *params = isEmail
        ? @{@"email": trimmed, @"password": password}
        : @{@"phone": trimmed, @"password": password};

    __weak typeof(self) weakSelf = self;
    [self.client POST:path parameters:params cookie:nil completion:^(NSDictionary *json, NSError *error) {
        SP_AUTH_MAIN(^{
            if (error || !json) {
                if (completion) completion(nil, error ?: [weakSelf authError:@"登录失败" code:-105]);
                return;
            }
            if (completion) completion([weakSelf parseUserFromAuthJSON:json account:trimmed fallbackCookie:nil], nil);
        });
    }];
}

- (void)loginWithAccount:(NSString *)account
        verificationCode:(NSString *)code
              completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    NSString *trimmed = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || code.length == 0) {
        SP_AUTH_MAIN(^{
            if (completion) completion(nil, [self authError:@"请输入手机号与验证码" code:-106]);
        });
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.client POST:@"/login/cellphone"
           parameters:@{@"phone": trimmed, @"captcha": code}
               cookie:nil
           completion:^(NSDictionary *json, NSError *error) {
        SP_AUTH_MAIN(^{
            if (error || !json) {
                if (completion) completion(nil, error ?: [weakSelf authError:@"验证码登录失败" code:-107]);
                return;
            }
            if (completion) completion([weakSelf parseUserFromAuthJSON:json account:trimmed fallbackCookie:nil], nil);
        });
    }];
}

@end
