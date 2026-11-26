//
//  SPListeningStatsViewController.h
//  Spotify
//
//  「听歌统计」页面：原生编辑式排版、单调三次样条趋势曲线、24h 声波节律条、常听歌手与真实单曲排行。
//

#import <UIKit/UIKit.h>
#import "SPListeningStatsStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPListeningStatsViewController : UIViewController

@property (nonatomic, assign, readonly) SPListeningChartRange selectedRange;

- (void)selectRange:(SPListeningChartRange)range animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
