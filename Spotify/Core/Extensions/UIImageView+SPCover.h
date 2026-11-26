//
//  UIImageView+SPCover.h
//  Spotify
//

#import <UIKit/UIKit.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIImageView (SPCover)

/// 是否关闭自动 1px 描边（用于外层容器已自带描边的快捷卡片，避免双倍叠边）
@property (nonatomic, assign) BOOL sp_suppressCoverBorder;

/// 同步当前封面对应的 URL 标记（用于横滑切歌接力换图后防止同 URL 短路错图）
- (void)sp_syncCurrentURLString:(nullable NSString *)urlString;

/// 为封面图像视图应用连续圆角曲线与 1px 动态中性描边
- (void)sp_applyCoverChrome;

/// 取消在途下载并清空残留图与 URL 标记（用于 Cell prepareForReuse）
- (void)sp_cancelCoverLoadAndReset;

/// 加载封面：占位底色 + 渐显 + 按视图尺寸降采样 + 1px 动态描边
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
