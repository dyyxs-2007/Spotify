//
//  SPPlayerService.m
//  Spotify
//

#import "SPPlayerService.h"
#import "SPAudioEngine.h"
#import "SPAVPlayerEngine.h"
#import "SPPlayQueue.h"
#import "SPAudioCacheManager.h"
#import "SPSystemMediaController.h"
#import "SPHistoryStore.h"
#import "SPToast.h"

static NSString * const SPPlayerPreloadEnabledDefaultsKey = @"sp_preload_enabled_v1";

@interface SPPlayerService () <SPAudioEngineDelegate>
@property (nonatomic, strong) NSPointerArray *observers;
@property (nonatomic, strong) SPPlayQueue *queue;
@property (nonatomic, strong) id<SPAudioEngine> engine;
@property (nonatomic, strong) SPSystemMediaController *systemController;

@property (nonatomic, assign) SPPlaybackState state;
@property (nonatomic, copy, nullable) NSString *contextTitle;
@property (nonatomic, assign) NSUInteger loadTicket;
@property (nonatomic, assign) NSUInteger consecutiveFailures;
@property (nonatomic, assign) BOOL currentTrackLoadedInEngine;
@property (nonatomic, assign) BOOL lastPlaybackUsedCache;
@property (nonatomic, assign) NSTimeInterval pendingSeekTime;
@property (nonatomic, assign) NSTimeInterval lastSyncedDuration;
@property (nonatomic, assign) NSTimeInterval lastInfoUpdateTimestamp;
@property (nonatomic, assign) UIBackgroundTaskIdentifier transitionBackgroundTaskId;
@end

@implementation SPPlayerService

+ (instancetype)shared {
    static SPPlayerService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SPPlayerService new]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _observers = [NSPointerArray weakObjectsPointerArray];
        _queue = [SPPlayQueue new];
        _engine = [SPAVPlayerEngine new];
        _engine.delegate = self;
        _pendingSeekTime = -1;
        _transitionBackgroundTaskId = UIBackgroundTaskInvalid;
        _systemController = [[SPSystemMediaController alloc] initWithPlayerService:self];
    }
    return self;
}

- (BOOL)isPreloadEnabled {
    NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:SPPlayerPreloadEnabledDefaultsKey];
    return saved ? saved.boolValue : YES;
}

- (void)setPreloadEnabled:(BOOL)preloadEnabled {
    [[NSUserDefaults standardUserDefaults] setBool:preloadEnabled forKey:SPPlayerPreloadEnabledDefaultsKey];
}

#pragma mark - Observers

- (void)addObserver:(id<SPPlayerObserver>)observer {
    if (!observer) return;
    [self.observers compact];
    for (id<SPPlayerObserver> existing in self.observers) {
        if (existing == observer) return;
    }
    [self.observers addPointer:(__bridge void *)observer];
}

- (void)removeObserver:(id<SPPlayerObserver>)observer {
    if (!observer) return;
    for (NSUInteger i = 0; i < self.observers.count; i++) {
        if ([self.observers pointerAtIndex:i] == (__bridge void *)observer) {
            [self.observers removePointerAtIndex:i];
            break;
        }
    }
    [self.observers compact];
}

- (void)notify:(SEL)selector {
    [self.observers compact];
    NSArray *snapshot = [self.observers allObjects];
    for (id<SPPlayerObserver> observer in snapshot) {
        if ([observer respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [observer performSelector:selector withObject:self];
#pragma clang diagnostic pop
        }
    }
}

#pragma mark - State

- (SPTrack *)currentTrack { return self.queue.currentTrack; }
- (SPTrack *)previousTrack { return self.queue.previousTrack; }
- (SPTrack *)nextTrack { return self.queue.nextTrack; }
- (BOOL)isPlaying { return self.state == SPPlaybackStatePlaying; }
- (SPRepeatMode)repeatMode { return self.queue.repeatMode; }
- (BOOL)isShuffleEnabled { return self.queue.shuffleEnabled; }
- (NSArray<SPTrack *> *)upNextTracks { return self.queue.upNextTracks; }

- (NSTimeInterval)currentTime {
    if (!self.currentTrackLoadedInEngine && self.pendingSeekTime >= 0) {
        return self.pendingSeekTime;
    }
    return self.engine.currentTime;
}

- (NSTimeInterval)duration {
    if (self.engine.duration > 0) return self.engine.duration;
    return self.currentTrack.duration;
}

- (NSTimeInterval)bufferedTime { return self.engine.bufferedTime; }

#pragma mark - Commands

- (void)prepareTracks:(NSArray<SPTrack *> *)tracks startIndex:(NSUInteger)index contextTitle:(NSString *)contextTitle {
    if (index >= tracks.count) return;
    [self.engine stop];
    self.pendingSeekTime = -1;
    self.contextTitle = contextTitle;
    [self.queue replaceWithTracks:tracks startIndex:index];
    [self startCurrentTrackWithAutoPlay:NO];
    [self notify:@selector(playerDidChangeQueue:)];
}

- (void)playTracks:(NSArray<SPTrack *> *)tracks startIndex:(NSUInteger)index contextTitle:(NSString *)contextTitle {
    if (index >= tracks.count) return;
    self.consecutiveFailures = 0;
    self.pendingSeekTime = -1;
    self.contextTitle = contextTitle;
    [self.queue replaceWithTracks:tracks startIndex:index];
    [self startCurrentTrackWithAutoPlay:YES];
    [self notify:@selector(playerDidChangeQueue:)];
}

- (void)playUpNextAtIndex:(NSUInteger)index {
    SPTrack *track = [self.queue jumpToUpNextIndex:index];
    if (!track) return;
    self.consecutiveFailures = 0;
    self.pendingSeekTime = -1;
    [self startCurrentTrackWithAutoPlay:YES];
    [self notify:@selector(playerDidChangeQueue:)];
}

- (void)insertNextTrack:(SPTrack *)track {
    if (!track) return;
    BOOL wasEmpty = (self.currentTrack == nil);
    [self.queue insertNextTrack:track];
    if (wasEmpty) {
        self.contextTitle = track.name;
        [self startCurrentTrackWithAutoPlay:NO];
    } else {
        // 新插队的歌曲大概率很快会被播到，提前预加载
        [[SPAudioCacheManager shared] preloadTracks:@[track]];
    }
    [self notify:@selector(playerDidChangeQueue:)];
}

- (void)play {
    if (!self.currentTrack) return;
    [self.systemController activateAudioSession];
    if (!self.currentTrackLoadedInEngine || self.state == SPPlaybackStateFailed) {
        self.consecutiveFailures = 0;
        [self startCurrentTrackWithAutoPlay:YES];
        return;
    }
    [self.engine play];
}

- (void)pause {
    if (!self.currentTrack) return;
    if (!self.currentTrackLoadedInEngine) {
        self.loadTicket += 1;
        [self updateState:SPPlaybackStatePaused];
        return;
    }
    [self.engine pause];
}

- (void)togglePlayPause {
    if (self.isPlaying || self.state == SPPlaybackStateLoading) {
        [self pause];
    } else {
        [self play];
    }
}

- (void)next {
    if (![self.queue advanceToNextByAutoPlay:NO]) return;
    self.consecutiveFailures = 0;
    self.pendingSeekTime = -1;
    [self startCurrentTrackWithAutoPlay:YES];
    [self notify:@selector(playerDidChangeQueue:)];
}

- (void)previous {
    if (!self.currentTrack) return;
    if (self.currentTime > 3.0) {
        [self seekToTime:0];
        return;
    }
    [self skipToPreviousTrack];
}

- (void)skipToPreviousTrack {
    if (![self.queue retreatToPrevious]) return;
    self.consecutiveFailures = 0;
    self.pendingSeekTime = -1;
    [self startCurrentTrackWithAutoPlay:YES];
    [self notify:@selector(playerDidChangeQueue:)];
}

- (void)seekToTime:(NSTimeInterval)time {
    if (!self.currentTrack) return;
    NSTimeInterval target = MIN(MAX(time, 0), MAX(self.duration, 0));
    if (!self.currentTrackLoadedInEngine) {
        self.pendingSeekTime = target;
        [self notify:@selector(playerDidUpdateProgress:)];
        [self syncNowPlayingInfoForce:YES];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.engine seekToTime:target completion:^(BOOL finished) {
        [weakSelf syncNowPlayingInfoForce:YES];
    }];
}

- (void)toggleShuffle {
    self.queue.shuffleEnabled = !self.queue.shuffleEnabled;
    [self preloadAdjacentTracks];
    [self notify:@selector(playerDidChangeMode:)];
    [self notify:@selector(playerDidChangeQueue:)];
}

- (void)cycleRepeatMode {
    self.queue.repeatMode = (self.queue.repeatMode + 1) % 3;
    [self notify:@selector(playerDidChangeMode:)];
}

#pragma mark - Track Loading & Preload

- (void)startCurrentTrackWithAutoPlay:(BOOL)autoPlay {
    self.loadTicket += 1;
    NSUInteger ticket = self.loadTicket;
    SPTrack *track = self.currentTrack;

    self.currentTrackLoadedInEngine = NO;
    self.lastSyncedDuration = 0;
    self.lastPlaybackUsedCache = NO;

    [self notify:@selector(playerDidChangeTrack:)];
    [self notify:@selector(playerDidUpdateProgress:)];

    if (!track) {
        [self.engine stop];
        [self updateState:SPPlaybackStateIdle];
        return;
    }

    if (!autoPlay) {
        [self updateState:SPPlaybackStatePaused];
        [self syncNowPlayingInfoForce:YES];
        return;
    }

    [self beginTransitionBackgroundTask];
    [self.systemController activateAudioSession];
    [self updateState:SPPlaybackStateLoading];
    [self syncNowPlayingInfoForce:YES];

    __weak typeof(self) weakSelf = self;
    [[SPAudioCacheManager shared] resolvePlayableAssetForTrack:track
                                                    completion:^(AVURLAsset *asset, BOOL isCacheHit, NSError *error) {
        if (ticket != weakSelf.loadTicket) return;
        if (!asset || error) {
            [weakSelf handlePlaybackFailureWithMessage:error.localizedDescription ?: @"暂无播放地址"];
            return;
        }
        weakSelf.consecutiveFailures = 0;
        weakSelf.currentTrackLoadedInEngine = YES;
        weakSelf.lastPlaybackUsedCache = isCacheHit;
        [[SPHistoryStore shared] recordTrack:track];

        NSTimeInterval initialSeek = weakSelf.pendingSeekTime;
        weakSelf.pendingSeekTime = -1;
        [weakSelf.engine loadAsset:asset autoPlay:YES];
        if (initialSeek > 0) {
            [weakSelf.engine seekToTime:initialSeek completion:nil];
        }
        [weakSelf preloadAdjacentTracks];
    }];
}

- (void)beginTransitionBackgroundTask {
    [self endTransitionBackgroundTask];
    __weak typeof(self) weakSelf = self;
    self.transitionBackgroundTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"SPTrackTransition"
                                                                                 expirationHandler:^{
        [weakSelf endTransitionBackgroundTask];
    }];
}

- (void)endTransitionBackgroundTask {
    if (self.transitionBackgroundTaskId != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.transitionBackgroundTaskId];
        self.transitionBackgroundTaskId = UIBackgroundTaskInvalid;
    }
}

- (void)preloadAdjacentTracks {
    if (!self.isPreloadEnabled) return;
    NSMutableArray<SPTrack *> *adjacent = [NSMutableArray array];
    SPTrack *nextTrack = self.queue.nextTrack;
    SPTrack *prevTrack = self.queue.previousTrack;
    if (nextTrack) [adjacent addObject:nextTrack];
    if (prevTrack && prevTrack != nextTrack) [adjacent addObject:prevTrack];
    if (adjacent.count > 0) {
        [[SPAudioCacheManager shared] preloadTracks:adjacent];
    }
}

- (void)handlePlaybackFailureWithMessage:(NSString *)message {
    self.consecutiveFailures += 1;
    if (self.consecutiveFailures < self.queue.playOrderTracks.count && [self.queue advanceToNextByAutoPlay:NO]) {
        [SPToast showMessage:[NSString stringWithFormat:@"%@，已自动跳过", message]];
        self.pendingSeekTime = -1;
        [self startCurrentTrackWithAutoPlay:YES];
        [self notify:@selector(playerDidChangeQueue:)];
    } else {
        [SPToast showMessage:message];
        [self updateState:SPPlaybackStateFailed];
    }
}

- (void)updateState:(SPPlaybackState)state {
    if (self.state == state) return;
    self.state = state;
    if (state != SPPlaybackStateLoading) {
        [self endTransitionBackgroundTask];
    }
    [self notify:@selector(playerDidChangeState:)];
    [self syncNowPlayingInfoForce:YES];
}

- (void)syncNowPlayingInfoForce:(BOOL)force {
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    BOOL durationJustResolved = (self.lastSyncedDuration <= 0 && self.duration > 0);
    if (force || durationJustResolved || (now - self.lastInfoUpdateTimestamp >= 5.0)) {
        self.lastSyncedDuration = self.duration;
        self.lastInfoUpdateTimestamp = now;
        [self.systemController updateNowPlayingInfo];
    }
}

#pragma mark - SPAudioEngineDelegate

- (void)audioEngine:(id<SPAudioEngine>)engine didChangeState:(SPPlaybackState)state {
    [self updateState:state];
}

- (void)audioEngine:(id<SPAudioEngine>)engine
didUpdateCurrentTime:(NSTimeInterval)currentTime
           duration:(NSTimeInterval)duration
       bufferedTime:(NSTimeInterval)bufferedTime {
    // 真实流媒体时长解析出来后回写，防止假时长与真时长不一致引发后续跳变
    if (duration > 0 && self.currentTrack && fabs(self.currentTrack.duration - duration) > 1.0) {
        self.currentTrack.duration = duration;
    }
    [self notify:@selector(playerDidUpdateProgress:)];
    [self syncNowPlayingInfoForce:NO];
}

- (void)audioEngineDidFinishPlaying:(id<SPAudioEngine>)engine {
    SPTrack *nextTrack = [self.queue advanceToNextByAutoPlay:YES];
    if (nextTrack) {
        self.consecutiveFailures = 0;
        self.pendingSeekTime = -1;
        [self startCurrentTrackWithAutoPlay:YES];
        [self notify:@selector(playerDidChangeQueue:)];
    } else {
        __weak typeof(self) weakSelf = self;
        [self.engine pause];
        [self.engine seekToTime:0 completion:^(BOOL finished) {
            [weakSelf updateState:SPPlaybackStatePaused];
        }];
    }
}

- (void)audioEngine:(id<SPAudioEngine>)engine didFailWithError:(NSError *)error {
    [self handlePlaybackFailureWithMessage:error.localizedDescription ?: @"音频播放失败"];
}

@end
