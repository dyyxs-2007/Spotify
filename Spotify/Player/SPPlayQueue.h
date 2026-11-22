//
//  SPPlayQueue.h
//  Spotify
//
//  播放队列：独立管理原始顺序与随机洗牌顺序、单曲/列表循环以及"下一首播放"插队。
//

#import <Foundation/Foundation.h>
#import "SPTrack.h"
#import "SPPlayerService.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPPlayQueue : NSObject

@property (nonatomic, copy, readonly) NSArray<SPTrack *> *originalTracks;
@property (nonatomic, copy, readonly) NSArray<SPTrack *> *playOrderTracks;
@property (nonatomic, assign, readonly) NSInteger currentIndex;
@property (nonatomic, strong, readonly, nullable) SPTrack *currentTrack;
@property (nonatomic, strong, readonly, nullable) SPTrack *previousTrack;
@property (nonatomic, strong, readonly, nullable) SPTrack *nextTrack;
@property (nonatomic, copy, readonly) NSArray<SPTrack *> *upNextTracks;

@property (nonatomic, assign) BOOL shuffleEnabled;
@property (nonatomic, assign) SPRepeatMode repeatMode;

- (void)replaceWithTracks:(NSArray<SPTrack *> *)tracks startIndex:(NSUInteger)startIndex;
- (void)insertNextTrack:(SPTrack *)track;

- (nullable SPTrack *)advanceToNextByAutoPlay:(BOOL)isAutoPlay;
- (nullable SPTrack *)retreatToPrevious;
- (nullable SPTrack *)jumpToUpNextIndex:(NSUInteger)upNextIndex;

@end

NS_ASSUME_NONNULL_END
