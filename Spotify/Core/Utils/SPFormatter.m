//
//  SPFormatter.m
//  Spotify
//

#import "SPFormatter.h"

@implementation SPFormatter

+ (NSString *)timeString:(NSTimeInterval)seconds {
    if (isnan(seconds) || seconds < 0) seconds = 0;
    NSInteger total = (NSInteger)floor(seconds);
    NSInteger h = total / 3600, m = (total % 3600) / 60, s = total % 60;
    if (h > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

+ (NSString *)totalDurationString:(NSTimeInterval)seconds {
    NSInteger minutes = (NSInteger)round(seconds / 60.0);
    if (minutes >= 60) {
        return [NSString stringWithFormat:@"%ld 小时 %ld 分钟", (long)(minutes / 60), (long)(minutes % 60)];
    }
    return [NSString stringWithFormat:@"%ld 分钟", (long)MAX(minutes, 1)];
}

+ (NSString *)countString:(NSInteger)count {
    if (count >= 100000000) return [NSString stringWithFormat:@"%.1f亿", count / 100000000.0];
    if (count >= 10000) return [NSString stringWithFormat:@"%.1f万", count / 10000.0];
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    return [f stringFromNumber:@(count)] ?: @"0";
}

+ (NSString *)greeting {
    NSInteger hour = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[NSDate date]];
    if (hour >= 5 && hour < 12) return @"早上好";
    if (hour >= 12 && hour < 18) return @"下午好";
    return @"晚上好";
}

@end
