//
//  UIImageView+SPCover.h
//  Spotify
//

#import <UIKit/UIKit.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIImageView (SPCover)

/// 加载封面：占位底色 + 渐显 + 按视图尺寸降采样 + 1px 纯白 10% 描边
- (void)sp_setImageWithURLString:(nullable NSString *)urlString placeholderColor:(nullable UIColor *)color;

/// 根据媒体项设置封面（处理"已点赞的歌曲"等本地生成封面的特殊情况）
- (void)sp_setCoverWithItem:(nullable id<SPMediaItem>)item;

/// 设置封面并从真实加载到的图像素中异步提取主色（主线程回调）
- (void)sp_setCoverWithItem:(nullable id<SPMediaItem>)item
    dominantColorCompletion:(nullable void (^)(UIColor *color))completion;

/// "已点赞的歌曲" 的紫色渐变爱心封面
+ (UIImage *)sp_likedSongsCoverImage;

/// 新建空歌单的渐变音符默认封面
+ (UIImage *)sp_defaultPlaylistCoverImageForColor:(nullable UIColor *)themeColor;

@end

NS_ASSUME_NONNULL_END
