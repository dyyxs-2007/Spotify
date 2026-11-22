//
//  SPKeychainStore.h
//  Spotify
//
//  基于 Security.framework 的 Keychain 轻量读写封装。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKeychainStore : NSObject

+ (BOOL)setData:(NSData *)data forKey:(NSString *)key;
+ (nullable NSData *)dataForKey:(NSString *)key;
+ (BOOL)deleteValueForKey:(NSString *)key;

+ (BOOL)setString:(NSString *)string forKey:(NSString *)key;
+ (nullable NSString *)stringForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
