//
//  UIColor+SPHex.m
//  Spotify
//

#import "UIColor+SPHex.h"

@implementation UIColor (SPHex)

+ (UIColor *)sp_colorWithHex:(uint32_t)hex {
    return [self sp_colorWithHex:hex alpha:1.0];
}

+ (UIColor *)sp_colorWithHex:(uint32_t)hex alpha:(CGFloat)alpha {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

+ (UIColor *)sp_colorWithHexString:(NSString *)hexString {
    if (hexString.length == 0) return nil;
    NSString *str = [hexString hasPrefix:@"#"] ? [hexString substringFromIndex:1] : hexString;
    if (str.length != 6) return nil;
    unsigned int value = 0;
    if (![[NSScanner scannerWithString:str] scanHexInt:&value]) return nil;
    return [self sp_colorWithHex:value];
}

- (UIColor *)sp_darkenedBy:(CGFloat)ratio {
    CGFloat h, s, b, a;
    if ([self getHue:&h saturation:&s brightness:&b alpha:&a]) {
        return [UIColor colorWithHue:h saturation:s brightness:b * (1 - ratio) alpha:a];
    }
    return self;
}

- (UIColor *)sp_clampedForDarkBackground {
    CGFloat h, s, b, a;
    if ([self getHue:&h saturation:&s brightness:&b alpha:&a]) {
        b = MIN(MAX(b, 0.30), 0.62);
        s = MIN(s, 0.80);
        return [UIColor colorWithHue:h saturation:s brightness:b alpha:a];
    }
    return self;
}

- (UIColor *)sp_interpolatedToColor:(UIColor *)other fraction:(CGFloat)fraction {
    if (!other) return self;
    CGFloat t = MIN(MAX(fraction, 0.0), 1.0);
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 1;
    CGFloat r2 = 0, g2 = 0, b2 = 0, a2 = 1;
    BOOL ok1 = [self getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    BOOL ok2 = [other getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    if (!ok1 || !ok2) {
        return (t < 0.5) ? self : other;
    }
    return [UIColor colorWithRed:(r1 + (r2 - r1) * t)
                           green:(g1 + (g2 - g1) * t)
                            blue:(b1 + (b2 - b1) * t)
                           alpha:(a1 + (a2 - a1) * t)];
}

@end
