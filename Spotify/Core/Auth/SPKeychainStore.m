//
//  SPKeychainStore.m
//  Spotify
//

#import "SPKeychainStore.h"
#import <Security/Security.h>

static NSString * const SPKeychainService = @"com.dyyxs.Spotify.auth";
static NSString * const SPKeychainFallbackPrefix = @"com.dyyxs.Spotify.kc_fallback.";

@implementation SPKeychainStore

+ (NSMutableDictionary *)baseQueryForKey:(NSString *)key {
    return [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: SPKeychainService,
        (__bridge id)kSecAttrAccount: key,
    } mutableCopy];
}

+ (BOOL)setData:(NSData *)data forKey:(NSString *)key {
    if (!data || key.length == 0) return NO;
    NSMutableDictionary *query = [self baseQueryForKey:key];
    SecItemDelete((__bridge CFDictionaryRef)query);

    NSMutableDictionary *attrs = [query mutableCopy];
    attrs[(__bridge id)kSecValueData] = data;
    attrs[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)attrs, NULL);
    if (status == errSecSuccess) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[SPKeychainFallbackPrefix stringByAppendingString:key]];
        return YES;
    }
    if (status == errSecMissingEntitlement) {
        // 无签名/无 Keychain Entitlement 的 Ad-hoc 模拟器环境兜底
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:[SPKeychainFallbackPrefix stringByAppendingString:key]];
        return YES;
    }
    return NO;
}

+ (NSData *)dataForKey:(NSString *)key {
    if (key.length == 0) return nil;
    NSMutableDictionary *query = [self baseQueryForKey:key];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        return (__bridge_transfer NSData *)result;
    }
    return [[NSUserDefaults standardUserDefaults] dataForKey:[SPKeychainFallbackPrefix stringByAppendingString:key]];
}

+ (BOOL)deleteValueForKey:(NSString *)key {
    if (key.length == 0) return NO;
    NSMutableDictionary *query = [self baseQueryForKey:key];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:[SPKeychainFallbackPrefix stringByAppendingString:key]];
    return status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement;
}

+ (BOOL)setString:(NSString *)string forKey:(NSString *)key {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return data ? [self setData:data forKey:key] : NO;
}

+ (NSString *)stringForKey:(NSString *)key {
    NSData *data = [self dataForKey:key];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

@end
