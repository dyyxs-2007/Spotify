//
//  SPLocalAuthProvider.m
//  Spotify
//

#import "SPLocalAuthProvider.h"
#import "SPKeychainStore.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <YYModel/YYModel.h>

static NSErrorDomain const SPLocalAuthErrorDomain = @"com.dyyxs.spotify.auth";
static NSString * const SPLocalUsersKeychainKey = @"sp.auth.local.users.v1";

@interface SPLocalUserRecord : NSObject
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *account;
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, copy) NSString *planName;
@property (nonatomic, copy) NSString *salt;
@property (nonatomic, copy) NSString *passwordHash;
@property (nonatomic, assign) NSTimeInterval createdAt;
@end

@implementation SPLocalUserRecord
@end

@interface SPPendingCode : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, assign) NSTimeInterval sentAt;
@property (nonatomic, assign) NSTimeInterval expiresAt;
@end

@implementation SPPendingCode
@end

@interface SPLocalAuthProvider ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, SPPendingCode *> *pendingCodes;
@end

@implementation SPLocalAuthProvider

- (instancetype)init {
    if (self = [super init]) {
        _pendingCodes = [NSMutableDictionary dictionary];
        [self seedDemoAccountIfNeeded];
    }
    return self;
}

- (NSString *)providerName { return @"LocalAuth (Keychain + SHA256)"; }

#pragma mark - Validation

+ (BOOL)isValidAccount:(NSString *)account {
    NSString *trimmed = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return NO;
    NSPredicate *phonePred = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^1[3-9]\\d{9}$"];
    NSPredicate *emailPred = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"];
    return [phonePred evaluateWithObject:trimmed] || [emailPred evaluateWithObject:trimmed];
}

+ (BOOL)isValidPassword:(NSString *)password {
    if (password.length < 8) return NO;
    BOOL hasLetter = [password rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound;
    BOOL hasDigit = [password rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound;
    return hasLetter && hasDigit;
}

+ (NSInteger)passwordStrengthFor:(NSString *)password {
    if (password.length < 8) return 0;
    NSInteger score = 1;
    BOOL hasUpper = [password rangeOfCharacterFromSet:NSCharacterSet.uppercaseLetterCharacterSet].location != NSNotFound;
    BOOL hasLower = [password rangeOfCharacterFromSet:NSCharacterSet.lowercaseLetterCharacterSet].location != NSNotFound;
    BOOL hasDigit = [password rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound;
    NSCharacterSet *symbols = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    BOOL hasSymbol = [password rangeOfCharacterFromSet:symbols].location != NSNotFound;
    if ((hasUpper || hasLower) && hasDigit) score += 1;
    if (password.length >= 10 && ((hasUpper && hasLower) || hasSymbol)) score += 1;
    return score;
}

#pragma mark - Crypto

- (NSString *)randomHexWithByteLength:(NSUInteger)byteLength {
    uint8_t bytes[32] = {0};
    NSUInteger count = MIN(byteLength, sizeof(bytes));
    if (SecRandomCopyBytes(kSecRandomDefault, count, bytes) != errSecSuccess) {
        for (NSUInteger i = 0; i < count; i++) bytes[i] = (uint8_t)arc4random_uniform(256);
    }
    NSMutableString *hex = [NSMutableString stringWithCapacity:count * 2];
    for (NSUInteger i = 0; i < count; i++) [hex appendFormat:@"%02x", bytes[i]];
    return [hex copy];
}

- (NSString *)sha256WithSalt:(NSString *)salt password:(NSString *)password {
    NSString *salted = [NSString stringWithFormat:@"%@:%@", salt, password];
    NSData *data = [salted dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [hex copy];
}

- (NSString *)randomSixDigitCode {
    uint32_t value = 0;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(value), (uint8_t *)&value) != errSecSuccess) {
        value = arc4random();
    }
    return [NSString stringWithFormat:@"%06u", (value % 900000) + 100000];
}

#pragma mark - Storage

- (NSMutableDictionary<NSString *, SPLocalUserRecord *> *)loadAllRecords {
    NSData *data = [SPKeychainStore dataForKey:SPLocalUsersKeychainKey];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (!data) return dict;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSArray.class]) return dict;
    NSArray<SPLocalUserRecord *> *list = [NSArray yy_modelArrayWithClass:SPLocalUserRecord.class json:json];
    for (SPLocalUserRecord *record in list) {
        if (record.account.length > 0) dict[record.account.lowercaseString] = record;
    }
    return dict;
}

- (BOOL)saveAllRecords:(NSDictionary<NSString *, SPLocalUserRecord *> *)records {
    id json = [records.allValues yy_modelToJSONObject];
    if (![json isKindOfClass:NSArray.class]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    return data ? [SPKeychainStore setData:data forKey:SPLocalUsersKeychainKey] : NO;
}

- (void)seedDemoAccountIfNeeded {
    NSMutableDictionary<NSString *, SPLocalUserRecord *> *records = [self loadAllRecords];
    NSString *demoAccount = @"demo@spotify.local";
    if (records[demoAccount]) return;

    SPLocalUserRecord *demo = [SPLocalUserRecord new];
    demo.userId = @"u_demo_001";
    demo.account = demoAccount;
    demo.nickname = @"Spotify 体验官";
    demo.planName = @"Premium 体验版";
    demo.salt = [self randomHexWithByteLength:16];
    demo.passwordHash = [self sha256WithSalt:demo.salt password:@"Spotify123"];
    demo.createdAt = NSDate.date.timeIntervalSince1970;
    records[demoAccount] = demo;
    [self saveAllRecords:records];
}

- (SPUser *)userFromRecord:(SPLocalUserRecord *)record {
    SPUser *user = [SPUser new];
    user.userId = record.userId;
    user.account = record.account;
    user.nickname = record.nickname;
    user.planName = record.planName;
    user.accessToken = [self randomHexWithByteLength:24];
    user.refreshToken = [self randomHexWithByteLength:24];
    user.createdAt = record.createdAt;
    return user;
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:SPLocalAuthErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (NSString *)defaultNicknameForAccount:(NSString *)account {
    if ([account containsString:@"@"]) {
        NSString *prefix = [account componentsSeparatedByString:@"@"].firstObject;
        return prefix.length > 0 ? prefix : @"听友";
    }
    if (account.length >= 4) {
        return [NSString stringWithFormat:@"听友%@", [account substringFromIndex:account.length - 4]];
    }
    return @"音乐爱好者";
}

#pragma mark - SPAuthProvider

- (void)sendVerificationCodeToAccount:(NSString *)account
                              purpose:(SPAuthCodePurpose)purpose
                           completion:(void (^)(BOOL, NSString * _Nullable, NSError * _Nullable))completion {
    NSString *normalized = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (![SPLocalAuthProvider isValidAccount:normalized]) {
        if (completion) completion(NO, nil, [self errorWithCode:400 userInfoMessage:@"请输入有效的手机号或邮箱"]);
        return;
    }

    NSDictionary *records = [self loadAllRecords];
    BOOL exists = (records[normalized] != nil);
    if (purpose == SPAuthCodePurposeRegister && exists) {
        if (completion) completion(NO, nil, [self errorWithCode:409 message:@"该账号已注册，请直接登录"]);
        return;
    }
    if (purpose == SPAuthCodePurposeLogin && !exists) {
        if (completion) completion(NO, nil, [self errorWithCode:404 message:@"该账号尚未注册，请先注册"]);
        return;
    }

    NSString *codeKey = [NSString stringWithFormat:@"%ld:%@", (long)purpose, normalized];
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    SPPendingCode *existing = self.pendingCodes[codeKey];
    if (existing && (now - existing.sentAt) < 60.0) {
        NSInteger remain = (NSInteger)ceil(60.0 - (now - existing.sentAt));
        if (completion) completion(NO, nil, [self errorWithCode:429 message:[NSString stringWithFormat:@"发送过于频繁，请 %ld 秒后再试", (long)remain]]);
        return;
    }

    SPPendingCode *pending = [SPPendingCode new];
    pending.code = [self randomSixDigitCode];
    pending.sentAt = now;
    pending.expiresAt = now + 300.0; // 5 分钟有效
    self.pendingCodes[codeKey] = pending;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (completion) completion(YES, pending.code, nil);
    });
}

- (NSError *)errorWithCode:(NSInteger)code userInfoMessage:(NSString *)msg {
    return [self errorWithCode:code message:msg];
}

- (BOOL)consumeValidCode:(NSString *)code forAccount:(NSString *)normalized purpose:(SPAuthCodePurpose)purpose error:(NSError **)error {
    NSString *codeKey = [NSString stringWithFormat:@"%ld:%@", (long)purpose, normalized];
    SPPendingCode *pending = self.pendingCodes[codeKey];
    if (!pending) {
        if (error) *error = [self errorWithCode:400 message:@"请先获取验证码"];
        return NO;
    }
    if (CFAbsoluteTimeGetCurrent() > pending.expiresAt) {
        [self.pendingCodes removeObjectForKey:codeKey];
        if (error) *error = [self errorWithCode:410 message:@"验证码已过期，请重新获取"];
        return NO;
    }
    if (![pending.code isEqualToString:[code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]) {
        if (error) *error = [self errorWithCode:401 message:@"验证码错误"];
        return NO;
    }
    [self.pendingCodes removeObjectForKey:codeKey];
    return YES;
}

- (void)registerWithAccount:(NSString *)account
                   password:(NSString *)password
           verificationCode:(NSString *)code
                   nickname:(NSString *)nickname
                 completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    NSString *normalized = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (![SPLocalAuthProvider isValidAccount:normalized]) {
        if (completion) completion(nil, [self errorWithCode:400 message:@"请输入有效的手机号或邮箱"]);
        return;
    }
    if (![SPLocalAuthProvider isValidPassword:password]) {
        if (completion) completion(nil, [self errorWithCode:400 message:@"密码需至少 8 位且同时包含字母和数字"]);
        return;
    }

    NSError *codeError = nil;
    if (![self consumeValidCode:code forAccount:normalized purpose:SPAuthCodePurposeRegister error:&codeError]) {
        if (completion) completion(nil, codeError);
        return;
    }

    NSMutableDictionary<NSString *, SPLocalUserRecord *> *records = [self loadAllRecords];
    if (records[normalized]) {
        if (completion) completion(nil, [self errorWithCode:409 message:@"该账号已注册"]);
        return;
    }

    SPLocalUserRecord *record = [SPLocalUserRecord new];
    record.userId = [NSString stringWithFormat:@"u_%@", [[self randomHexWithByteLength:6] substringToIndex:10]];
    record.account = normalized;
    NSString *trimmedNick = [nickname stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    record.nickname = trimmedNick.length > 0 ? trimmedNick : [self defaultNicknameForAccount:normalized];
    record.planName = @"Premium 体验版";
    record.salt = [self randomHexWithByteLength:16];
    record.passwordHash = [self sha256WithSalt:record.salt password:password];
    record.createdAt = NSDate.date.timeIntervalSince1970;

    records[normalized] = record;
    [self saveAllRecords:records];

    SPUser *user = [self userFromRecord:record];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (completion) completion(user, nil);
    });
}

- (void)loginWithAccount:(NSString *)account
                password:(NSString *)password
              completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    NSString *normalized = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (![SPLocalAuthProvider isValidAccount:normalized]) {
        if (completion) completion(nil, [self errorWithCode:400 message:@"请输入有效的手机号或邮箱"]);
        return;
    }
    if (password.length == 0) {
        if (completion) completion(nil, [self errorWithCode:400 message:@"请输入密码"]);
        return;
    }

    NSDictionary<NSString *, SPLocalUserRecord *> *records = [self loadAllRecords];
    SPLocalUserRecord *record = records[normalized];
    if (!record) {
        if (completion) completion(nil, [self errorWithCode:404 message:@"账号不存在，请先注册"]);
        return;
    }

    NSString *candidateHash = [self sha256WithSalt:record.salt password:password];
    if (![candidateHash isEqualToString:record.passwordHash]) {
        if (completion) completion(nil, [self errorWithCode:401 message:@"账号或密码错误"]);
        return;
    }

    SPUser *user = [self userFromRecord:record];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (completion) completion(user, nil);
    });
}

- (void)loginWithAccount:(NSString *)account
        verificationCode:(NSString *)code
              completion:(void (^)(SPUser * _Nullable, NSError * _Nullable))completion {
    NSString *normalized = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (![SPLocalAuthProvider isValidAccount:normalized]) {
        if (completion) completion(nil, [self errorWithCode:400 message:@"请输入有效的手机号或邮箱"]);
        return;
    }

    NSDictionary<NSString *, SPLocalUserRecord *> *records = [self loadAllRecords];
    SPLocalUserRecord *record = records[normalized];
    if (!record) {
        if (completion) completion(nil, [self errorWithCode:404 message:@"账号不存在，请先注册"]);
        return;
    }

    NSError *codeError = nil;
    if (![self consumeValidCode:code forAccount:normalized purpose:SPAuthCodePurposeLogin error:&codeError]) {
        if (completion) completion(nil, codeError);
        return;
    }

    SPUser *user = [self userFromRecord:record];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (completion) completion(user, nil);
    });
}

@end
