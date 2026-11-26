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
#import "SPListeningStatsStore.h"
#import "SPToast.h"

NSNotificationName const SPPlayerSleepTimerDidUpdateNotification = @"com.dyyxs.spotify.player.sleepTimerUpdated";

static NSString * const SPPlayerPreloadEnabledDefaultsKey = @"sp_preload_enabled_v1";

@interface SPPlayerService () <SPAudioEngineDelegate>
@property (nonatomic, strong) NSPointerArray *observers;
@property (nonatomic, strong) SPPlayQueue *queue;
@property (nonatomic, strong) id<SPAudioEngine> engine;
@property (nonatomic, strong) SPSystemMediaController *systemController;

@property (nonatomic, assign) SPPlaybackState state;
@property (nonatomic, copy, nullable) NSString *contextTitle;
@property (nonatomic, assign) NSUInteger loadTicket;
@property (nonatomic, assign) NSUInteger playbackSessionId;
@property (nonatomic, assign) BOOL currentSessionRecordedPlay;
@property (nonatomic, assign) NSUInteger consecutiveFailures;
@property (nonatomic, assign) BOOL currentTrackLoadedInEngine;
@property (nonatomic, assign) BOOL lastPlaybackUsedCache;
@property (nonatomic, assign) NSTimeInterval pendingSeekTime;
@property (nonatomic, assign) NSTimeInterval lastSyncedDuration;
@property (nonatomic, assign) NSTimeInterval lastInfoUpdateTimestamp;
@property (nonatomic, assign) UIBackgroundTaskIdentifier transitionBackgroundTaskId;
@property (nonatomic, strong, nullable) NSTimer *sleepTimer;
@property (nonatomic, assign) NSTimeInterval sleepTimerRemaining;
@property (nonatomic, strong, nullable) NSDate *sleepTimerDeadline;
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

- (void)compactObservers {
    // Foundation 经典陷阱：ARC 弱引用置空不会置位 NSPointerArray 的 needsCompaction，需先追加 NULL 再 compact
    [self.observers addPointer:NULL];
    [self.observers compact];
}

- (void)addObserver:(id<SPPlayerObserver>)observer {
    if (!observer) return;
    [self compactObservers];
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
    [self compactObservers];
}

- (void)notify:(SEL)selector {
    [self compactObservers];
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
    SPTrack *requested = tracks[index];
    SPTrack *current = self.currentTrack;
    BOOL isSameActiveTrack = (current && requested.identifier.length > 0 &&
                              [requested.identifier isEqualToString:current.identifier] &&
                              self.currentTrackLoadedInEngine &&
                              self.state != SPPlaybackStateFailed &&
                              (self.duration <= 0 || self.currentTime < self.duration - 2.0));
    if (isSameActiveTrack) {
        self.consecutiveFailures = 0;
        self.contextTitle = contextTitle;
        [self.queue replaceWithTracks:tracks startIndex:index];
        [self notify:@selector(playerDidChangeQueue:)];
        if (!self.isPlaying) {
            [self play];
        }
        return;
    }
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
        [self.engine pause];
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

#pragma mark - Sleep Timer & Reset

- (BOOL)isSleepTimerActive {
    return (self.sleepTimer != nil && self.sleepTimerRemaining > 0);
}

- (void)postSleepTimerNotification {
    dispatch_block_t block = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPPlayerSleepTimerDidUpdateNotification object:self];
    };
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}

- (void)setSleepTimerMinutes:(NSInteger)minutes {
    [self.sleepTimer invalidate];
    self.sleepTimer = nil;
    self.sleepTimerDeadline = nil;

    if (minutes <= 0) {
        self.sleepTimerRemaining = 0;
        [self postSleepTimerNotification];
        return;
    }

    NSTimeInterval duration = (NSTimeInterval)minutes * 60.0;
    self.sleepTimerDeadline = [NSDate dateWithTimeIntervalSinceNow:duration];
    self.sleepTimerRemaining = duration;
    [self postSleepTimerNotification];

    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            [t invalidate];
            return;
        }
        NSTimeInterval remaining = strongSelf.sleepTimerDeadline
            ? MAX(0.0, [strongSelf.sleepTimerDeadline timeIntervalSinceNow])
            : 0.0;
        strongSelf.sleepTimerRemaining = remaining;
        if (remaining <= 0.0) {
            [t invalidate];
            strongSelf.sleepTimer = nil;
            strongSelf.sleepTimerDeadline = nil;
            [strongSelf pause];
            [strongSelf postSleepTimerNotification];
            [SPToast showMessage:@"睡眠定时已到，已为你暂停播放"];
        } else {
            [strongSelf postSleepTimerNotification];
        }
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.sleepTimer = timer;
}

- (void)resetToEmptyState {
    self.loadTicket += 1;
    self.playbackSessionId += 1;
    self.currentSessionRecordedPlay = NO;
    self.consecutiveFailures = 0;
    self.pendingSeekTime = -1;
    self.currentTrackLoadedInEngine = NO;
    self.lastSyncedDuration = 0;
    self.lastPlaybackUsedCache = NO;
    self.contextTitle = nil;

    [[SPListeningStatsStore shared] recordPlaybackProgressForTrack:nil isPlaying:NO];
    [self setSleepTimerMinutes:0];
    [self endTransitionBackgroundTask];
    [self.engine stop];
    [self.queue clear];
    self.state = SPPlaybackStateIdle;
    [self.systemController clearNowPlayingInfo];

    [self notify:@selector(playerDidChangeTrack:)];
    [self notify:@selector(playerDidChangeQueue:)];
    [self notify:@selector(playerDidUpdateProgress:)];
    [self notify:@selector(playerDidChangeState:)];
}

#pragma mark - Track Loading & Preload

- (void)recordCurrentSessionPlayIfNeeded {
    if (self.currentSessionRecordedPlay || !self.currentTrackLoadedInEngine || !self.currentTrack) return;
    self.currentSessionRecordedPlay = YES;
    [[SPListeningStatsStore shared] recordTrackPlay:self.currentTrack sessionId:self.playbackSessionId];
}

- (void)startCurrentTrackWithAutoPlay:(BOOL)autoPlay {
    self.loadTicket += 1;
    self.playbackSessionId += 1;
    self.currentSessionRecordedPlay = NO;
    NSUInteger ticket = self.loadTicket;
    SPTrack *track = self.currentTrack;

    self.currentTrackLoadedInEngine = NO;
    self.lastSyncedDuration = 0;
    self.lastPlaybackUsedCache = NO;
    [[SPListeningStatsStore shared] recordPlaybackProgressForTrack:nil isPlaying:NO];
    // 切歌时立刻暂停上一首音频，避免新曲 URL 解析期间旧歌继续出声或点暂停后“假暂停”
    if (self.engine.state == SPPlaybackStatePlaying || self.engine.state == SPPlaybackStateLoading) {
        [self.engine pause];
    }

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
    if (state == SPPlaybackStatePlaying) {
        // 只有真正出声播放时才清零连续失败计数并计入当前播放会话，防止坏缓存/缓冲中断反复计数
        self.consecutiveFailures = 0;
        [self recordCurrentSessionPlayIfNeeded];
    }
    if (state != SPPlaybackStateLoading) {
        [self endTransitionBackgroundTask];
    }
    [[SPListeningStatsStore shared] recordPlaybackProgressForTrack:self.currentTrack isPlaying:(state == SPPlaybackStatePlaying)];
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
    if (self.state == SPPlaybackStatePlaying && currentTime > 0.05) {
        [self recordCurrentSessionPlayIfNeeded];
    }
    [[SPListeningStatsStore shared] recordPlaybackProgressForTrack:self.currentTrack isPlaying:(self.state == SPPlaybackStatePlaying)];
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
        NSUInteger ticket = self.loadTicket;
        __weak typeof(self) weakSelf = self;
        [self.engine pause];
        [[SPListeningStatsStore shared] recordPlaybackProgressForTrack:nil isPlaying:NO];
        self.playbackSessionId += 1;
        self.currentSessionRecordedPlay = NO;
        [self.engine seekToTime:0 completion:^(BOOL finished) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.loadTicket != ticket) return;
            [strongSelf updateState:SPPlaybackStatePaused];
        }];
    }
}

- (void)audioEngine:(id<SPAudioEngine>)engine didFailWithError:(NSError *)error {
    [[SPAudioCacheManager shared] invalidateCacheForTrack:self.currentTrack];
    [self handlePlaybackFailureWithMessage:error.localizedDescription ?: @"音频播放失败"];
}

@end
