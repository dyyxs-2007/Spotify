//
//  SPPlayerService.h
//  Spotify
//
//  播放器门面（UI 唯一入口）。UI 只调用这里的方法、只订阅这里的状态，永远不直接接触 AVPlayer。
//
//  阶段二：接入 SPAudioEngine（AVPlayer 实现）、SPPlayQueue、URL 解析与系统锁屏/控制中心。
//

#import <Foundation/Foundation.h>
#import "SPTrack.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPPlaybackState) {
    SPPlaybackStateIdle = 0,
    SPPlaybackStateLoading,
    SPPlaybackStatePlaying,
    SPPlaybackStatePaused,
    SPPlaybackStateFailed,
};

typedef NS_ENUM(NSInteger, SPRepeatMode) {
    SPRepeatModeOff = 0,
    SPRepeatModeAll,
    SPRepeatModeOne,
};

@class SPPlayerService;

/// 播放器状态观察者（多播代理，弱引用持有）
@protocol SPPlayerObserver <NSObject>
@optional
- (void)playerDidChangeTrack:(SPPlayerService *)player;
- (void)playerDidChangeState:(SPPlayerService *)player;
- (void)playerDidUpdateProgress:(SPPlayerService *)player;
- (void)playerDidChangeQueue:(SPPlayerService *)player;
- (void)playerDidChangeMode:(SPPlayerService *)player;
@end

@interface SPPlayerService : NSObject

+ (instancetype)shared;

#pragma mark - State (readonly)
@property (nonatomic, strong, readonly, nullable) SPTrack *currentTrack;
@property (nonatomic, assign, readonly) SPPlaybackState state;
@property (nonatomic, assign, readonly, getter=isPlaying) BOOL playing;
@property (nonatomic, assign, readonly) NSTimeInterval currentTime;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly) NSTimeInterval bufferedTime;
@property (nonatomic, assign, readonly) BOOL lastPlaybackUsedCache;
/// 播放来源描述，如 "每日推荐"
@property (nonatomic, copy, readonly, nullable) NSString *contextTitle;
@property (nonatomic, assign, readonly) SPRepeatMode repeatMode;
@property (nonatomic, assign, readonly, getter=isShuffleEnabled) BOOL shuffleEnabled;
@property (nonatomic, assign, getter=isPreloadEnabled) BOOL preloadEnabled;
/// 当前曲目之后将要播放的歌曲（已考虑随机顺序）
@property (nonatomic, copy, readonly) NSArray<SPTrack *> *upNextTracks;
@property (nonatomic, strong, readonly, nullable) SPTrack *previousTrack;
@property (nonatomic, strong, readonly, nullable) SPTrack *nextTrack;

#pragma mark - Observers
- (void)addObserver:(id<SPPlayerObserver>)observer;
- (void)removeObserver:(id<SPPlayerObserver>)observer;

#pragma mark - Commands
/// 预置播放队列但保持暂停（用于启动时恢复默认迷你播放条状态）
- (void)prepareTracks:(NSArray<SPTrack *> *)tracks startIndex:(NSUInteger)index contextTitle:(nullable NSString *)contextTitle;
- (void)playTracks:(NSArray<SPTrack *> *)tracks startIndex:(NSUInteger)index contextTitle:(nullable NSString *)contextTitle;
- (void)playUpNextAtIndex:(NSUInteger)index;
- (void)insertNextTrack:(SPTrack *)track;
- (void)play;
- (void)pause;
- (void)togglePlayPause;
- (void)next;
- (void)previous;
/// 直接切换到队列中的上一首（不触发 3 秒后重头播放逻辑，用于左右滑动预览提交）
- (void)skipToPreviousTrack;
- (void)seekToTime:(NSTimeInterval)time;
- (void)toggleShuffle;
- (void)cycleRepeatMode;

@end

NS_ASSUME_NONNULL_END
