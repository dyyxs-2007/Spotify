//
//  SPMoodRoamViewController.h
//  Spotify
//
//  「漫游调频」场景电台页：拟物刻度调频盘 + 5 档情绪频段 + 实时曲库漫游播放。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPMoodRoamViewController : UIViewController

@property (nonatomic, assign, readonly) NSInteger selectedStationIndex;
@property (nonatomic, assign, readonly) NSUInteger currentTrackCount;

- (void)selectStationAtIndex:(NSInteger)index autoPlay:(BOOL)autoPlay;

@end

NS_ASSUME_NONNULL_END
