//
//  UIImage+SPDominantColor.m
//  Spotify
//

#import "UIImage+SPDominantColor.h"
#import "SPLRUCache.h"

@implementation UIImage (SPDominantColor)

+ (SPLRUCache<NSString *, UIColor *> *)sp_colorCache {
    static SPLRUCache<NSString *, UIColor *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[SPLRUCache alloc] initWithMaxCount:200];
    });
    return cache;
}

+ (UIColor *)sp_cachedDominantColorForKey:(NSString *)cacheKey {
    if (cacheKey.length == 0) return nil;
    return [[self sp_colorCache] objectForKey:cacheKey];
}

+ (void)sp_clearDominantColorCache {
    [[self sp_colorCache] removeAllObjects];
}

+ (void)sp_extractDominantColorForImage:(UIImage *)image
                               cacheKey:(NSString *)cacheKey
                             completion:(void (^)(UIColor *))completion {
    if (!completion) return;
    if (!image) {
        completion([UIColor sp_colorWithHex:0x282828]);
        return;
    }
    if (cacheKey.length > 0) {
        UIColor *cached = [[self sp_colorCache] objectForKey:cacheKey];
        if (cached) {
            completion(cached);
            return;
        }
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIColor *color = [image sp_dominantColor];
        if (cacheKey.length > 0) {
            [[self sp_colorCache] setObject:color forKey:cacheKey];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(color);
        });
    });
}

- (UIColor *)sp_dominantColor {
    CGImageRef cgImage = self.CGImage;
    if (!cgImage) return [UIColor sp_colorWithHex:0x282828];

    enum {
        kSampleSide = 16,
        kTotalPixels = kSampleSide * kSampleSide,
        kBucketCount = 12
    };
    const NSUInteger side = kSampleSide;
    const NSUInteger totalPixels = kTotalPixels;
    uint8_t rawData[kTotalPixels * 4];
    memset(rawData, 0, sizeof(rawData));

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
    CGContextRef context = CGBitmapContextCreate(rawData, side, side, 8, side * 4, colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    if (!context) return [UIColor sp_colorWithHex:0x282828];

    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), cgImage);
    CGContextRelease(context);

    // 12 个色相桶，按饱和度加权，避免灰黑/纯白主宰结果
    const NSInteger bucketCount = kBucketCount;
    double bucketWeight[kBucketCount] = {0};
    double bucketR[kBucketCount] = {0};
    double bucketG[kBucketCount] = {0};
    double bucketB[kBucketCount] = {0};

    double fallbackWeight = 0, fallbackR = 0, fallbackG = 0, fallbackB = 0;

    for (NSUInteger i = 0; i < totalPixels; i++) {
        NSUInteger offset = i * 4;
        uint8_t a = rawData[offset + 3];
        if (a < 64) continue;

        double alphaFactor = a / 255.0;
        double r = MIN(rawData[offset] / alphaFactor, 255.0);
        double g = MIN(rawData[offset + 1] / alphaFactor, 255.0);
        double b = MIN(rawData[offset + 2] / alphaFactor, 255.0);

        double maxC = MAX(r, MAX(g, b));
        double minC = MIN(r, MIN(g, b));
        double delta = maxC - minC;

        // 跳过极暗或高亮灰白像素
        if (maxC < 38 || (delta < 22 && maxC > 220)) continue;

        double sat = maxC > 0 ? (delta / maxC) : 0;
        double weight = 1.0 + sat * 2.0;

        fallbackWeight += weight;
        fallbackR += r * weight;
        fallbackG += g * weight;
        fallbackB += b * weight;

        if (delta < 14) continue; // 低饱和像素不入色相桶，保留给兜底均值

        double hue = 0;
        if (maxC == r) {
            hue = (g - b) / delta + (g < b ? 6.0 : 0.0);
        } else if (maxC == g) {
            hue = (b - r) / delta + 2.0;
        } else {
            hue = (r - g) / delta + 4.0;
        }
        hue /= 6.0;
        NSInteger bucket = MIN((NSInteger)(hue * bucketCount), bucketCount - 1);

        bucketWeight[bucket] += weight;
        bucketR[bucket] += r * weight;
        bucketG[bucket] += g * weight;
        bucketB[bucket] += b * weight;
    }

    NSInteger bestBucket = -1;
    double maxWeight = 0;
    for (NSInteger b = 0; b < bucketCount; b++) {
        if (bucketWeight[b] > maxWeight) {
            maxWeight = bucketWeight[b];
            bestBucket = b;
        }
    }

    UIColor *result = nil;
    if (bestBucket >= 0 && maxWeight > 0) {
        double w = bucketWeight[bestBucket];
        result = [UIColor colorWithRed:(bucketR[bestBucket] / w) / 255.0
                                 green:(bucketG[bestBucket] / w) / 255.0
                                  blue:(bucketB[bestBucket] / w) / 255.0
                                 alpha:1.0];
    } else if (fallbackWeight > 0) {
        result = [UIColor colorWithRed:(fallbackR / fallbackWeight) / 255.0
                                 green:(fallbackG / fallbackWeight) / 255.0
                                  blue:(fallbackB / fallbackWeight) / 255.0
                                 alpha:1.0];
    } else {
        return [UIColor sp_colorWithHex:0x282828];
    }

    return [result sp_clampedForDarkBackground];
}

@end
