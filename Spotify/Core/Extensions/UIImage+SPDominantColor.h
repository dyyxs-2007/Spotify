//
//  UIImage+SPDominantColor.h
//  Spotify
//
//  从封面图像提取适合深色主题背景的主色调（带内存缓存）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIImage (SPDominantColor)

/// 同步从当前图片提取适合深色背景的主色
- (UIColor *)sp_dominantColor;

/// 同步查询已缓存的封面主色，未命中返回 nil
+ (nullable UIColor *)sp_cachedDominantColorForKey:(nullable NSString *)cacheKey;

/// 异步提取并缓存主色，主线程回调
+ (void)sp_extractDominantColorForImage:(nullable UIImage *)image
                               cacheKey:(nullable NSString *)cacheKey
                             completion:(void (^)(UIColor *color))completion;

@end

NS_ASSUME_NONNULL_END
