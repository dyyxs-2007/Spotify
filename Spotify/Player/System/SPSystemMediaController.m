//
//  SPSystemMediaController.m
//  Spotify
//

#import "SPSystemMediaController.h"
#import "SPPlayerService.h"
#import "SPAlbum.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface SPSystemMediaController ()
@property (nonatomic, weak) SPPlayerService *playerService;
@property (nonatomic, assign) BOOL shouldResumeAfterInterruption;
@property (nonatomic, copy, nullable) NSString *artworkTrackId;
@property (nonatomic, strong, nullable) MPMediaItemArtwork *cachedArtwork;
@property (nonatomic, strong, nullable) id<SDWebImageOperation> artworkOperation;
@end

@implementation SPSystemMediaController

- (instancetype)initWithPlayerService:(SPPlayerService *)playerService {
    if (self = [super init]) {
        _playerService = playerService;
        [self setupAudioSession];
        [self setupRemoteCommands];
        [self registerAppLifecycleNotifications];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.artworkOperation cancel];
}

#pragma mark - App Lifecycle

- (void)registerAppLifecycleNotifications {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(handleDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(handleWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)handleDidEnterBackground {
    if (self.playerService.isPlaying || self.playerService.state == SPPlaybackStateLoading) {
        [self activateAudioSession];
        [self updateNowPlayingInfo];
    }
}

- (void)handleWillEnterForeground {
    [self updateNowPlayingInfo];
}

#pragma mark - AVAudioSession

- (void)setupAudioSession {
    [self activateAudioSession];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    [center addObserver:self selector:@selector(handleRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];
}

- (void)activateAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error];
    [session setActive:YES error:&error];
}

- (void)handleInterruption:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    AVAudioSessionInterruptionType type = [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (type == AVAudioSessionInterruptionTypeBegan) {
            self.shouldResumeAfterInterruption = self.playerService.isPlaying;
            [self.playerService pause];
        } else if (type == AVAudioSessionInterruptionTypeEnded) {
            AVAudioSessionInterruptionOptions options = [info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
            if ((options & AVAudioSessionInterruptionOptionShouldResume) && self.shouldResumeAfterInterruption) {
                [self activateAudioSession];
                [self.playerService play];
            }
            self.shouldResumeAfterInterruption = NO;
        }
    });
}

- (void)handleRouteChange:(NSNotification *)note {
    AVAudioSessionRouteChangeReason reason = [note.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.playerService pause];
        });
    }
}

#pragma mark - MPRemoteCommandCenter

- (void)setupRemoteCommands {
    dispatch_block_t registerBlock = ^{
        [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    };
    if (NSThread.isMainThread) registerBlock(); else dispatch_async(dispatch_get_main_queue(), registerBlock);

    MPRemoteCommandCenter *center = [MPRemoteCommandCenter sharedCommandCenter];
    __weak typeof(self) weakSelf = self;

    // 禁用快进/快退，确保锁屏和灵动岛稳定展示上一首/下一首按钮
    center.skipForwardCommand.enabled = NO;
    center.skipBackwardCommand.enabled = NO;
    center.seekForwardCommand.enabled = NO;
    center.seekBackwardCommand.enabled = NO;

    center.playCommand.enabled = YES;
    [center.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.playerService play];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    center.pauseCommand.enabled = YES;
    [center.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.playerService pause];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    center.togglePlayPauseCommand.enabled = YES;
    [center.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.playerService togglePlayPause];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    center.nextTrackCommand.enabled = YES;
    [center.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.playerService next];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    center.previousTrackCommand.enabled = YES;
    [center.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.playerService previous];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    center.changePlaybackPositionCommand.enabled = YES;
    [center.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        if ([event isKindOfClass:MPChangePlaybackPositionCommandEvent.class]) {
            NSTimeInterval position = ((MPChangePlaybackPositionCommandEvent *)event).positionTime;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.playerService seekToTime:position];
            });
            return MPRemoteCommandHandlerStatusSuccess;
        }
        return MPRemoteCommandHandlerStatusCommandFailed;
    }];

    center.changeRepeatModeCommand.enabled = YES;
    [center.changeRepeatModeCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.playerService cycleRepeatMode];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    center.changeShuffleModeCommand.enabled = YES;
    [center.changeShuffleModeCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.playerService toggleShuffle];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}

#pragma mark - MPNowPlayingInfoCenter

- (void)updateNowPlayingInfo {
    SPPlayerService *player = self.playerService;
    SPTrack *track = player.currentTrack;
    if (!track) {
        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
        MPNowPlayingInfoCenter.defaultCenter.playbackState = MPNowPlayingPlaybackStateStopped;
        return;
    }

    if (![self.artworkTrackId isEqualToString:track.identifier]) {
        self.artworkTrackId = track.identifier;
        self.cachedArtwork = nil;
        [self loadArtworkForTrack:track];
    }

    [self applyNowPlayingInfoForTrack:track];
}

- (void)applyNowPlayingInfoForTrack:(SPTrack *)track {
    SPPlayerService *player = self.playerService;
    if (!player || ![player.currentTrack.identifier isEqualToString:track.identifier]) return;

    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    if (player.isPlaying) {
        center.playbackState = MPNowPlayingPlaybackStatePlaying;
    } else if (player.state == SPPlaybackStateIdle) {
        center.playbackState = MPNowPlayingPlaybackStateStopped;
    } else {
        center.playbackState = MPNowPlayingPlaybackStatePaused;
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = track.name ?: @"";
    info[MPMediaItemPropertyArtist] = [track artistNames];
    if (track.album.name.length > 0) {
        info[MPMediaItemPropertyAlbumTitle] = track.album.name;
    }
    info[MPNowPlayingInfoPropertyMediaType] = @(MPNowPlayingInfoMediaTypeAudio);
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = @(1.0);
    info[MPMediaItemPropertyPlaybackDuration] = @(player.duration);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(player.currentTime);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(player.isPlaying ? 1.0 : 0.0);
    if (self.cachedArtwork) {
        info[MPMediaItemPropertyArtwork] = self.cachedArtwork;
    }
    center.nowPlayingInfo = [info copy];
}

- (void)loadArtworkForTrack:(SPTrack *)track {
    [self.artworkOperation cancel];
    self.artworkOperation = nil;

    if (track.coverURL.length == 0) {
        UIImage *fallback = [UIImageView sp_likedSongsCoverImage];
        self.cachedArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:fallback.size
                                                             requestHandler:^UIImage *(CGSize size) { return fallback; }];
        return;
    }

    NSURL *url = [NSURL URLWithString:track.coverURL];
    if (!url) return;

    // 优先同步读取 SDWebImage 内存/磁盘缓存，保证灵动岛与锁屏切换瞬间首帧即有封面
    NSString *cacheKey = [[SDWebImageManager sharedManager] cacheKeyForURL:url];
    UIImage *cachedImg = [[SDImageCache sharedImageCache] imageFromCacheForKey:cacheKey];
    if (cachedImg) {
        self.cachedArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:cachedImg.size
                                                             requestHandler:^UIImage *(CGSize size) { return cachedImg; }];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSString *trackId = track.identifier;
    self.artworkOperation = [[SDWebImageManager sharedManager] loadImageWithURL:url
                                                                        options:SDWebImageRetryFailed
                                                                       progress:nil
                                                                      completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        if (!image || ![weakSelf.artworkTrackId isEqualToString:trackId]) return;
        weakSelf.cachedArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size
                                                                 requestHandler:^UIImage *(CGSize size) { return image; }];
        [weakSelf applyNowPlayingInfoForTrack:track];
    }];
}

@end
