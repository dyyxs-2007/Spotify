//
//  SPHistoryStore.h
//  Spotify
//
//  最近收听历史持久化仓库（最多保留 50 首，按播放时间倒序去重）。
//

#import <Foundation/Foundation.h>
#import "SPTrack.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SPHistoryDidUpdateNotification;

@interface SPHistoryStore : NSObject

+ (instancetype)shared;

@property (nonatomic, copy, readonly) NSArray<SPTrack *> *recentTracks;

- (void)recordTrack:(SPTrack *)track;
- (void)clearHistory;
- (void)reloadForCurrentUser;

@end

NS_ASSUME_NONNULL_END
