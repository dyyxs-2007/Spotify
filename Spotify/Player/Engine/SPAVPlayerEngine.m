//
//  SPAVPlayerEngine.m
//  Spotify
//

#import "SPAVPlayerEngine.h"
#import <AVFoundation/AVFoundation.h>

static void * const SPAVPlayerEngineContext = (void *)&SPAVPlayerEngineContext;

@interface SPAVPlayerEngine ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong, nullable) AVPlayerItem *currentItem;
@property (nonatomic, strong, nullable) id timeObserver;
@property (nonatomic, assign) SPPlaybackState state;
@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) NSTimeInterval bufferedTime;
@property (nonatomic, assign) NSTimeInterval pendingSeekTime;
@property (nonatomic, assign) NSTimeInterval lastSeekTargetTime;
@property (nonatomic, assign) CFAbsoluteTime lastSeekTimestamp;
@property (nonatomic, assign) BOOL shouldAutoPlay;
@property (nonatomic, assign) BOOL seeking;
@property (nonatomic, assign) NSUInteger seekGeneration;
@end

@implementation SPAVPlayerEngine

@synthesize delegate = _delegate;

- (instancetype)init {
    if (self = [super init]) {
        _player = [AVPlayer new];
        _player.automaticallyWaitsToMinimizeStalling = YES;
        _player.allowsExternalPlayback = YES;
        _player.audiovisualBackgroundPlaybackPolicy = AVPlayerAudiovisualBackgroundPlaybackPolicyContinuesIfPossible;
        _pendingSeekTime = -1;
        [_player addObserver:self forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew context:SPAVPlayerEngineContext];

        __weak typeof(self) weakSelf = self;
        _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 4)
                                                              queue:dispatch_get_main_queue()
                                                         usingBlock:^(CMTime time) {
            [weakSelf handlePeriodicTime:time];
        }];
    }
    return self;
}

- (void)dealloc {
    [self teardownCurrentItem];
    @try {
        [self.player removeObserver:self forKeyPath:@"timeControlStatus" context:SPAVPlayerEngineContext];
    } @catch (NSException *exception) {}
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
}

#pragma mark - SPAudioEngine

- (void)loadURL:(NSURL *)url autoPlay:(BOOL)autoPlay {
    [self loadAsset:[AVURLAsset assetWithURL:url] autoPlay:autoPlay];
}

- (void)loadAsset:(AVURLAsset *)asset autoPlay:(BOOL)autoPlay {
    [self teardownCurrentItem];
    self.shouldAutoPlay = autoPlay;
    self.seeking = NO;
    self.seekGeneration += 1;
    self.pendingSeekTime = -1;
    self.lastSeekTimestamp = 0;
    self.currentTime = 0;
    self.duration = 0;
    self.bufferedTime = 0;
    [self updateState:SPPlaybackStateLoading];

    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    self.currentItem = item;

    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:SPAVPlayerEngineContext];
    [item addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:SPAVPlayerEngineContext];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleItemDidPlayToEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleItemFailedToPlayToEnd:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:item];

    [self.player replaceCurrentItemWithPlayerItem:item];
}

- (void)play {
    self.shouldAutoPlay = YES;
    if (!self.currentItem) return;
    if (self.currentItem.status == AVPlayerItemStatusReadyToPlay) {
        [self.player play];
        if (self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
            [self updateState:SPPlaybackStatePlaying];
        } else {
            [self updateState:SPPlaybackStateLoading];
        }
    } else if (self.currentItem.status == AVPlayerItemStatusUnknown) {
        [self updateState:SPPlaybackStateLoading];
    }
}

- (void)pause {
    self.shouldAutoPlay = NO;
    [self.player pause];
    if (self.currentItem && self.state != SPPlaybackStateIdle && self.state != SPPlaybackStateFailed) {
        [self updateState:SPPlaybackStatePaused];
    }
}

- (void)stop {
    self.shouldAutoPlay = NO;
    self.seeking = NO;
    self.seekGeneration += 1;
    self.pendingSeekTime = -1;
    [self.player pause];
    [self teardownCurrentItem];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.currentTime = 0;
    self.duration = 0;
    self.bufferedTime = 0;
    [self updateState:SPPlaybackStateIdle];
}

- (void)seekToTime:(NSTimeInterval)time completion:(void (^)(BOOL))completion {
    NSTimeInterval clamped = MAX(time, 0);
    if (self.duration > 0) clamped = MIN(clamped, self.duration);

    if (!self.currentItem || self.currentItem.status != AVPlayerItemStatusReadyToPlay) {
        self.pendingSeekTime = clamped;
        self.currentTime = clamped;
        [self notifyProgress];
        if (completion) completion(YES);
        return;
    }

    self.seeking = YES;
    self.seekGeneration += 1;
    NSUInteger generation = self.seekGeneration;
    self.currentTime = clamped;
    [self notifyProgress];

    __weak typeof(self) weakSelf = self;
    CMTime cmTime = CMTimeMakeWithSeconds(clamped, 600);
    [self.player seekToTime:cmTime
            toleranceBefore:kCMTimeZero
             toleranceAfter:kCMTimeZero
          completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            // 仅当本次 seek 仍是最新代次时才解除 seeking，避免快速连续拖动时旧 seek 被取消提前放开进度保护
            if (generation == strongSelf.seekGeneration) {
                strongSelf.seeking = NO;
                if (finished) {
                    strongSelf.currentTime = clamped;
                    strongSelf.lastSeekTargetTime = clamped;
                    strongSelf.lastSeekTimestamp = CFAbsoluteTimeGetCurrent();
                    [strongSelf notifyProgress];
                }
            }
            if (completion) completion(finished);
        });
    }];
}

#pragma mark - Teardown & State

- (void)teardownCurrentItem {
    AVPlayerItem *item = self.currentItem;
    if (!item) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    @try {
        [item removeObserver:self forKeyPath:@"status" context:SPAVPlayerEngineContext];
        [item removeObserver:self forKeyPath:@"loadedTimeRanges" context:SPAVPlayerEngineContext];
    } @catch (NSException *exception) {}
    self.currentItem = nil;
}

- (void)updateState:(SPPlaybackState)state {
    if (self.state == state) return;
    self.state = state;
    if ([self.delegate respondsToSelector:@selector(audioEngine:didChangeState:)]) {
        [self.delegate audioEngine:self didChangeState:state];
    }
}

- (void)notifyProgress {
    if ([self.delegate respondsToSelector:@selector(audioEngine:didUpdateCurrentTime:duration:bufferedTime:)]) {
        [self.delegate audioEngine:self
              didUpdateCurrentTime:self.currentTime
                          duration:self.duration
                      bufferedTime:self.bufferedTime];
    }
}

#pragma mark - KVO & Notifications

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (context != SPAVPlayerEngineContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    dispatch_block_t work = ^{
        if (object == self.currentItem) {
            if ([keyPath isEqualToString:@"status"]) {
                [self handleItemStatusChanged];
            } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
                [self updateBufferedTime];
            }
        } else if (object == self.player && [keyPath isEqualToString:@"timeControlStatus"]) {
            [self handleTimeControlStatusChanged];
        }
    };
    if (NSThread.isMainThread) work(); else dispatch_async(dispatch_get_main_queue(), work);
}

- (void)handleItemStatusChanged {
    AVPlayerItem *item = self.currentItem;
    if (!item) return;

    if (item.status == AVPlayerItemStatusReadyToPlay) {
        CMTime dur = item.duration;
        if (CMTIME_IS_NUMERIC(dur)) {
            NSTimeInterval seconds = CMTimeGetSeconds(dur);
            if (seconds > 0 && !isnan(seconds)) self.duration = seconds;
        }
        [self notifyProgress];

        if (self.pendingSeekTime >= 0) {
            NSTimeInterval target = self.pendingSeekTime;
            self.pendingSeekTime = -1;
            AVPlayerItem *targetItem = item;
            __weak typeof(self) weakSelf = self;
            [self seekToTime:target completion:^(BOOL finished) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf || strongSelf.currentItem != targetItem) return;
                if (strongSelf.shouldAutoPlay) {
                    [strongSelf.player play];
                    if (strongSelf.player.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
                        [strongSelf updateState:SPPlaybackStatePlaying];
                    } else {
                        [strongSelf updateState:SPPlaybackStateLoading];
                    }
                } else {
                    [strongSelf updateState:SPPlaybackStatePaused];
                }
            }];
        } else if (self.shouldAutoPlay) {
            [self.player play];
            if (self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
                [self updateState:SPPlaybackStatePlaying];
            } else {
                [self updateState:SPPlaybackStateLoading];
            }
        } else {
            [self updateState:SPPlaybackStatePaused];
        }
    } else if (item.status == AVPlayerItemStatusFailed) {
        [self updateState:SPPlaybackStateFailed];
        NSError *error = item.error ?: [NSError errorWithDomain:@"com.dyyxs.spotify.engine"
                                                           code:-1
                                                       userInfo:@{NSLocalizedDescriptionKey: @"音频加载失败"}];
        if ([self.delegate respondsToSelector:@selector(audioEngine:didFailWithError:)]) {
            [self.delegate audioEngine:self didFailWithError:error];
        }
    }
}

- (void)handleTimeControlStatusChanged {
    if (!self.currentItem || self.currentItem.status != AVPlayerItemStatusReadyToPlay) return;
    switch (self.player.timeControlStatus) {
        case AVPlayerTimeControlStatusPaused:
            if (!self.shouldAutoPlay || self.state == SPPlaybackStatePlaying) {
                self.shouldAutoPlay = NO;
                [self updateState:SPPlaybackStatePaused];
            }
            break;
        case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
            if (self.shouldAutoPlay) [self updateState:SPPlaybackStateLoading];
            break;
        case AVPlayerTimeControlStatusPlaying:
            [self updateState:SPPlaybackStatePlaying];
            break;
    }
}

- (void)updateBufferedTime {
    NSArray<NSValue *> *ranges = self.currentItem.loadedTimeRanges;
    if (ranges.count == 0) return;
    CMTimeRange range = ranges.firstObject.CMTimeRangeValue;
    NSTimeInterval start = CMTimeGetSeconds(range.start);
    NSTimeInterval dur = CMTimeGetSeconds(range.duration);
    if (!isnan(start) && !isnan(dur)) {
        self.bufferedTime = MAX(start + dur, 0);
        [self notifyProgress];
    }
}

- (void)handlePeriodicTime:(CMTime)time {
    if (!self.currentItem || self.seeking) return;
    if (CMTIME_IS_NUMERIC(time)) {
        NSTimeInterval seconds = CMTimeGetSeconds(time);
        if (!isnan(seconds) && seconds >= 0) {
            // Seek 刚释放后 0.35s 内过滤 AVPlayer 偶发吐出的旧时间戳，避免滑块闪回
            BOOL withinGuard = (CFAbsoluteTimeGetCurrent() - self.lastSeekTimestamp < 0.35);
            if (!(withinGuard && fabs(seconds - self.lastSeekTargetTime) > 1.5)) {
                self.currentTime = seconds;
            }
        }
    }
    CMTime dur = self.currentItem.duration;
    if (CMTIME_IS_NUMERIC(dur)) {
        NSTimeInterval total = CMTimeGetSeconds(dur);
        if (!isnan(total) && total > 0) self.duration = total;
    }
    [self notifyProgress];
}

- (void)handleItemDidPlayToEnd:(NSNotification *)note {
    AVPlayerItem *endedItem = note.object;
    if (endedItem != self.currentItem) return;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || endedItem != strongSelf.currentItem) return;
        if ([strongSelf.delegate respondsToSelector:@selector(audioEngineDidFinishPlaying:)]) {
            [strongSelf.delegate audioEngineDidFinishPlaying:strongSelf];
        }
    });
}

- (void)handleItemFailedToPlayToEnd:(NSNotification *)note {
    AVPlayerItem *failedItem = note.object;
    if (failedItem != self.currentItem) return;
    NSError *error = note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]
        ?: [NSError errorWithDomain:@"com.dyyxs.spotify.engine" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"音频播放中断"}];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || failedItem != strongSelf.currentItem) return;
        [strongSelf updateState:SPPlaybackStateFailed];
        if ([strongSelf.delegate respondsToSelector:@selector(audioEngine:didFailWithError:)]) {
            [strongSelf.delegate audioEngine:strongSelf didFailWithError:error];
        }
    });
}

@end
