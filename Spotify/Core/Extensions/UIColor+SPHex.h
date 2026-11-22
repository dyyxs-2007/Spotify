//
//  UIColor+SPHex.h
//  Spotify
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIColor (SPHex)

+ (UIColor *)sp_colorWithHex:(uint32_t)hex;
+ (UIColor *)sp_colorWithHex:(uint32_t)hex alpha:(CGFloat)alpha;
/// 支持 "#RRGGBB" / "RRGGBB"，解析失败返回 nil
+ (nullable UIColor *)sp_colorWithHexString:(nullable NSString *)hexString;

/// 按比例降低亮度（0~1），用于把封面色压暗成适合深色主题的背景
- (UIColor *)sp_darkenedBy:(CGFloat)ratio;
/// 把颜色的亮度/饱和度限制在区间内，保证白色文字在其上可读
- (UIColor *)sp_clampedForDarkBackground;

/// 线性颜色插值（fraction 范围为 0~1），用于切歌拖拽时实时过渡主题色
- (UIColor *)sp_interpolatedToColor:(UIColor *)other fraction:(CGFloat)fraction;

@end

NS_ASSUME_NONNULL_END
