//
//  SPFullScreenLyricsViewController.h
//  Spotify
//
//  全屏沉浸式实时歌词浏览页：大字号双语同步滚动、点句跳转播放与底部控播条。
//

#import <UIKit/UIKit.h>
#import "SPTrack.h"
#import "SPLyricModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPFullScreenLyricsViewController : UIViewController

@property (nonatomic, copy, nullable) void (^translationDidChangeHandler)(BOOL showTranslation);

- (instancetype)initWithTrack:(SPTrack *)track
                     document:(nullable SPLyricDocument *)document
                   themeColor:(nullable UIColor *)themeColor
              showTranslation:(BOOL)showTranslation;

@end

NS_ASSUME_NONNULL_END
