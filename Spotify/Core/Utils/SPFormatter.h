//
//  SPFormatter.h
//  Spotify
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPFormatter : NSObject

/// 3:05 / 1:02:03
+ (NSString *)timeString:(NSTimeInterval)seconds;
/// "1 小时 20 分钟" / "38 分钟"
+ (NSString *)totalDurationString:(NSTimeInterval)seconds;
/// 9,876 / 1.2万 / 3.4亿
+ (NSString *)countString:(NSInteger)count;
/// 按当前时间返回 "早上好/下午好/晚上好"
+ (NSString *)greeting;

@end

NS_ASSUME_NONNULL_END
