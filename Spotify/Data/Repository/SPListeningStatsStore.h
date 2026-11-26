//
//  SPListeningStatsStore.h
//  Spotify
//
//  按账号隔离的听歌统计与时间节律持久化仓库（记录每日/分时听歌时长、播放次数、常听单曲与艺人）。
//

#import <Foundation/Foundation.h>
#import "SPTrack.h"
#import "SPArtist.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SPListeningStatsDidUpdateNotification;

typedef NS_ENUM(NSInteger, SPListeningChartRange) {
    SPListeningChartRange7Days = 0,
    SPListeningChartRangeHourly = 1,
    SPListeningChartRange14Days = 2,
};

@interface SPListeningChartPoint : NSObject
@property (nonatomic, copy) NSString *axisLabel;
@property (nonatomic, copy) NSString *detailTitle;
@property (nonatomic, assign) CGFloat minutes;
@property (nonatomic, assign) NSUInteger playCount;
@property (nonatomic, assign) BOOL isDefaultFocus;
@end

@interface SPListeningTopTrackItem : NSObject
@property (nonatomic, strong) SPTrack *track;
@property (nonatomic, assign) NSUInteger playCount;
@property (nonatomic, assign) NSTimeInterval totalSeconds;
@end

@interface SPListeningTopArtistItem : NSObject
@property (nonatomic, strong) SPArtist *artist;
@property (nonatomic, assign) NSUInteger playCount;
@property (nonatomic, assign) NSTimeInterval totalSeconds;
@end

@interface SPListeningStatsSnapshot : NSObject
@property (nonatomic, assign) CGFloat totalMinutes;
@property (nonatomic, assign) NSUInteger totalPlayCount;
@property (nonatomic, assign) NSUInteger activeDaysCount;
@property (nonatomic, copy) NSString *personaTitle;
@property (nonatomic, copy) NSString *personaSummary;
@property (nonatomic, copy) NSArray<SPListeningChartPoint *> *points7Days;
@property (nonatomic, copy) NSArray<SPListeningChartPoint *> *points14Days;
@property (nonatomic, copy) NSArray<SPListeningChartPoint *> *pointsHourly;
/// 24 小时逐时分布（0..23 点）：分钟数与播放次数
@property (nonatomic, copy) NSArray<NSNumber *> *hourlyMinutes24;
@property (nonatomic, copy) NSArray<NSNumber *> *hourlyPlays24;
/// 最活跃小时（0..23，空记录时为 -1）与主活跃时段下标（0..3，空记录时为 -1）
@property (nonatomic, assign) NSInteger peakHour;
@property (nonatomic, assign) NSInteger dominantPeriodIndex;
/// 四个时段的时长占比：[清晨 05-11, 午后 11-17, 傍晚 17-22, 深夜 22-05]
@property (nonatomic, copy) NSArray<NSNumber *> *periodShares;
@property (nonatomic, copy) NSArray<SPListeningTopTrackItem *> *topTracks;
@property (nonatomic, copy) NSArray<SPListeningTopArtistItem *> *topArtists;
@end

@interface SPListeningStatsStore : NSObject

+ (instancetype)shared;

- (void)recordTrackPlay:(SPTrack *)track;
- (void)recordTrackPlay:(SPTrack *)track sessionId:(NSUInteger)sessionId;
- (void)recordPlaybackProgressForTrack:(nullable SPTrack *)track isPlaying:(BOOL)isPlaying;
- (void)recordListeningSeconds:(NSTimeInterval)seconds
                      forTrack:(nullable SPTrack *)track
                        atDate:(NSDate *)date
                     countPlay:(BOOL)countPlay;

- (void)reloadForCurrentUser;
- (void)clearCurrentUserStats;

- (SPListeningStatsSnapshot *)currentSnapshot;

@end

NS_ASSUME_NONNULL_END
