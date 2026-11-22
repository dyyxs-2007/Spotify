//
//  SPLyricsCardView.h
//  Spotify
//
//  播放详情页下滑歌词卡片：实时高光滚动、双语翻译切换与点击单句跳转进度。
//

#import <UIKit/UIKit.h>
#import "SPLyricModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPLyricsCardView : UIView

@property (nonatomic, copy, nullable) void (^seekHandler)(NSTimeInterval time);
@property (nonatomic, copy, nullable) void (^expandHandler)(void);
@property (nonatomic, strong, readonly, nullable) SPLyricDocument *document;
@property (nonatomic, assign, getter=isShowingTranslation) BOOL showTranslation;

- (void)setLoading;
- (void)configureWithDocument:(nullable SPLyricDocument *)document;
- (void)updateCurrentTime:(NSTimeInterval)currentTime animated:(BOOL)animated;
- (void)applyThemeColor:(nullable UIColor *)color animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
