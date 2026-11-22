//
//  SPMiniPlayerView.m
//  Spotify
//

#import "SPMiniPlayerView.h"
#import "SPScaleButton.h"
#import "SPPlayerService.h"
#import "UIImage+SPDominantColor.h"
#import "SPPlaylist.h"
#import "SPHaptics.h"
#import "SPToast.h"

#pragma mark - Track Slot Subview

@interface SPMiniPlayerTrackSlotView : UIView
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@end

@implementation SPMiniPlayerTrackSlotView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _coverView = [UIImageView new];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.layer.cornerRadius = 4;
        [self addSubview:_coverView];

        _titleLabel = [UILabel new];
        _titleLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.whiteColor;

        _artistLabel = [UILabel new];
        _artistLabel.font = [SPTheme fontOfSize:12 weight:UIFontWeightRegular];
        _artistLabel.textColor = [UIColor colorWithWhite:1 alpha:0.72];

        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _artistLabel]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 1;
        [self addSubview:textStack];

        [_coverView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(8);
            make.centerY.equalTo(self).offset(-1);
            make.size.mas_equalTo(CGSizeMake(40, 40));
        }];
        [textStack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self.coverView.mas_right).offset(10);
            make.right.equalTo(self).offset(-4);
            make.centerY.equalTo(self.coverView);
        }];
    }
    return self;
}

- (void)layoutSubviews {
    [UIView performWithoutAnimation:^{
        [super layoutSubviews];
    }];
}

@end

#pragma mark - SPMiniPlayerView

@interface SPMiniPlayerView () <SPPlayerObserver, UIScrollViewDelegate>
@property (nonatomic, strong) UIView *backgroundView;
@property (nonatomic, strong) UIScrollView *trackPagerScrollView;
@property (nonatomic, strong) SPMiniPlayerTrackSlotView *prevSlot;
@property (nonatomic, strong) SPMiniPlayerTrackSlotView *centerSlot;
@property (nonatomic, strong) SPMiniPlayerTrackSlotView *nextSlot;
@property (nonatomic, strong) SPScaleButton *deviceButton;
@property (nonatomic, strong) SPScaleButton *playButton;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *bufferFill;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, assign) CGFloat currentProgress;
@property (nonatomic, assign) CGFloat currentBufferProgress;

@property (nonatomic, strong, nullable) UIColor *prevTintedColor;
@property (nonatomic, strong, nullable) UIColor *centerTintedColor;
@property (nonatomic, strong, nullable) UIColor *nextTintedColor;
@property (nonatomic, copy, nullable) NSString *renderedTrackId;
@property (nonatomic, assign) BOOL didInitialStateRender;
@property (nonatomic, assign) BOOL ignoreScrollEvents;
@property (nonatomic, assign) CGFloat lastPagerWidth;
@property (nonatomic, assign) CGFloat lastPagerHeight;
@property (nonatomic, assign) BOOL lastHasAdjacent;
@end

@implementation SPMiniPlayerView

- (UIImageView *)coverView {
    return self.centerSlot.coverView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupViews];
        [[SPPlayerService shared] addObserver:self];
        [self reloadTrackSlots];
        [self reloadState];
        self.didInitialStateRender = YES;

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self.trackPagerScrollView addGestureRecognizer:tap];

        UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeUp)];
        swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
        [self addGestureRecognizer:swipeUp];
    }
    return self;
}

- (void)layoutSubviews {
    [UIView performWithoutAnimation:^{
        [super layoutSubviews];
        [self.backgroundView layoutIfNeeded];
        if (!CGRectIsEmpty(self.bounds)) {
            self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:12].CGPath;
        }
        [self layoutProgressFrames];
        [self layoutTrackPagerIfNeededForce:NO];
    }];
}

- (void)layoutTrackPagerIfNeededForce:(BOOL)force {
    CGFloat w = CGRectGetWidth(self.trackPagerScrollView.bounds);
    CGFloat h = CGRectGetHeight(self.trackPagerScrollView.bounds);
    if (w <= 0 || h <= 0) return;

    SPPlayerService *player = [SPPlayerService shared];
    BOOL hasAdjacent = (player.previousTrack != nil || player.nextTrack != nil);
    if (!force && fabs(w - self.lastPagerWidth) < 0.5 && fabs(h - self.lastPagerHeight) < 0.5 && hasAdjacent == self.lastHasAdjacent) {
        return;
    }

    self.lastPagerWidth = w;
    self.lastPagerHeight = h;
    self.lastHasAdjacent = hasAdjacent;
    self.ignoreScrollEvents = YES;

    [UIView performWithoutAnimation:^{
        if (hasAdjacent) {
            self.prevSlot.hidden = NO;
            self.nextSlot.hidden = NO;
            self.prevSlot.frame = CGRectMake(0, 0, w, h);
            self.centerSlot.frame = CGRectMake(w, 0, w, h);
            self.nextSlot.frame = CGRectMake(w * 2.0, 0, w, h);
            self.trackPagerScrollView.contentSize = CGSizeMake(w * 3.0, h);
            self.trackPagerScrollView.scrollEnabled = YES;
            if (!(self.trackPagerScrollView.isDragging || self.trackPagerScrollView.isDecelerating)) {
                [self.trackPagerScrollView setContentOffset:CGPointMake(w, 0) animated:NO];
            }
        } else {
            self.prevSlot.hidden = YES;
            self.nextSlot.hidden = YES;
            self.centerSlot.frame = CGRectMake(0, 0, w, h);
            self.trackPagerScrollView.contentSize = CGSizeMake(w, h);
            self.trackPagerScrollView.scrollEnabled = NO;
            [self.trackPagerScrollView setContentOffset:CGPointZero animated:NO];
        }
        [self.prevSlot layoutIfNeeded];
        [self.centerSlot layoutIfNeeded];
        [self.nextSlot layoutIfNeeded];
    }];
    self.ignoreScrollEvents = NO;
}

- (void)layoutProgressFrames {
    CGFloat w = CGRectGetWidth(self.progressTrack.bounds);
    CGFloat h = CGRectGetHeight(self.progressTrack.bounds);
    if (w <= 0) return;
    [UIView performWithoutAnimation:^{
        self.bufferFill.frame = CGRectMake(0, 0, w * self.currentBufferProgress, h);
        self.progressFill.frame = CGRectMake(0, 0, w * self.currentProgress, h);
    }];
}

- (void)setupViews {
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.35;
    self.layer.shadowRadius = 10;
    self.layer.shadowOffset = CGSizeMake(0, 4);

    _backgroundView = [UIView new];
    _backgroundView.backgroundColor = [UIColor sp_colorWithHex:0x242428];
    _backgroundView.layer.cornerRadius = 12;
    _backgroundView.layer.cornerCurve = kCACornerCurveContinuous;
    _backgroundView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _backgroundView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    _backgroundView.clipsToBounds = YES;
    [self addSubview:_backgroundView];

    _trackPagerScrollView = [UIScrollView new];
    _trackPagerScrollView.pagingEnabled = YES;
    _trackPagerScrollView.showsHorizontalScrollIndicator = NO;
    _trackPagerScrollView.showsVerticalScrollIndicator = NO;
    _trackPagerScrollView.bounces = YES;
    _trackPagerScrollView.directionalLockEnabled = YES;
    _trackPagerScrollView.clipsToBounds = YES;
    _trackPagerScrollView.delegate = self;
    [_backgroundView addSubview:_trackPagerScrollView];

    _prevSlot = [SPMiniPlayerTrackSlotView new];
    _centerSlot = [SPMiniPlayerTrackSlotView new];
    _nextSlot = [SPMiniPlayerTrackSlotView new];
    [_trackPagerScrollView addSubview:_prevSlot];
    [_trackPagerScrollView addSubview:_centerSlot];
    [_trackPagerScrollView addSubview:_nextSlot];

    _deviceButton = [self iconButton:@"hifispeaker" size:18 action:@selector(deviceTapped)];
    _playButton = [self iconButton:@"play.fill" size:22 action:@selector(playTapped)];
    _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingIndicator.color = UIColor.whiteColor;
    _loadingIndicator.hidesWhenStopped = YES;
    _loadingIndicator.userInteractionEnabled = NO;
    [_backgroundView addSubview:_deviceButton];
    [_backgroundView addSubview:_playButton];
    [_playButton addSubview:_loadingIndicator];

    _progressTrack = [UIView new];
    _progressTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    _progressTrack.layer.cornerRadius = 1;
    _progressTrack.clipsToBounds = YES;
    [_backgroundView addSubview:_progressTrack];

    _bufferFill = [UIView new];
    _bufferFill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
    [_progressTrack addSubview:_bufferFill];

    _progressFill = [UIView new];
    _progressFill.backgroundColor = UIColor.whiteColor;
    [_progressTrack addSubview:_progressFill];

    [_backgroundView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self);
    }];
    [_playButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.backgroundView).offset(-6);
        make.centerY.equalTo(self.backgroundView).offset(-1);
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    [_loadingIndicator mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.playButton);
    }];
    [_deviceButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.playButton.mas_left);
        make.centerY.equalTo(self.playButton);
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    [_trackPagerScrollView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.top.bottom.equalTo(self.backgroundView);
        make.right.equalTo(self.deviceButton.mas_left).offset(-4);
    }];
    [_progressTrack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.backgroundView).offset(12);
        make.right.equalTo(self.backgroundView).offset(-12);
        make.bottom.equalTo(self.backgroundView);
        make.height.mas_equalTo(2);
    }];
}

- (SPScaleButton *)iconButton:(NSString *)symbol size:(CGFloat)size action:(SEL)action {
    SPScaleButton *button = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [button sp_setSymbol:symbol size:size weight:UIImageSymbolWeightRegular animated:NO];
    button.tintColor = UIColor.whiteColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

#pragma mark - Reload Slots

- (UIColor *)tintedBackgroundForTrack:(nullable SPTrack *)track dominantColor:(nullable UIColor *)dominant {
    if (dominant) return [dominant sp_darkenedBy:0.25];
    if (track.coverURL.length > 0) {
        UIColor *cached = [UIImage sp_cachedDominantColorForKey:track.coverURL];
        if (cached) return [cached sp_darkenedBy:0.25];
    }
    if (track.themeColor) return [[track.themeColor sp_clampedForDarkBackground] sp_darkenedBy:0.25];
    return [UIColor sp_colorWithHex:0x242428];
}

- (void)configureSlot:(SPMiniPlayerTrackSlotView *)slot
            withTrack:(nullable SPTrack *)track
             slotType:(NSInteger)slotType {
    if (!track) {
        [UIView performWithoutAnimation:^{
            slot.titleLabel.text = @"";
            slot.artistLabel.text = @"";
            slot.coverView.image = nil;
            [slot setNeedsLayout];
            [slot layoutIfNeeded];
        }];
        return;
    }
    [UIView performWithoutAnimation:^{
        slot.titleLabel.text = track.name ?: @"";
        slot.artistLabel.text = track.artistNames;
        [slot setNeedsLayout];
        [slot layoutIfNeeded];
    }];

    UIColor *initial = [self tintedBackgroundForTrack:track dominantColor:nil];
    if (slotType == 0) self.prevTintedColor = initial;
    else if (slotType == 1) self.centerTintedColor = initial;
    else self.nextTintedColor = initial;

    __weak typeof(self) weakSelf = self;
    NSString *trackId = track.identifier;
    [slot.coverView sp_setCoverWithItem:track dominantColorCompletion:^(UIColor *color) {
        if (!weakSelf) return;
        UIColor *tinted = [color sp_darkenedBy:0.25];
        SPPlayerService *player = [SPPlayerService shared];
        if (slotType == 0 && [player.previousTrack.identifier isEqualToString:trackId]) {
            weakSelf.prevTintedColor = tinted;
        } else if (slotType == 1 && [player.currentTrack.identifier isEqualToString:trackId]) {
            weakSelf.centerTintedColor = tinted;
            if (!weakSelf.trackPagerScrollView.isDragging && !weakSelf.trackPagerScrollView.isDecelerating
                && ![weakSelf.backgroundView.backgroundColor isEqual:tinted]) {
                BOOL canAnimateBg = (weakSelf.window != nil) && !weakSelf.hidden && (weakSelf.alpha > 0.01);
                if (canAnimateBg) {
                    [UIView animateWithDuration:0.28 animations:^{
                        weakSelf.backgroundView.backgroundColor = tinted;
                    }];
                } else {
                    weakSelf.backgroundView.backgroundColor = tinted;
                }
            }
        } else if (slotType == 2 && [player.nextTrack.identifier isEqualToString:trackId]) {
            weakSelf.nextTintedColor = tinted;
        }
    }];
}

- (void)reloadTrackSlots {
    SPPlayerService *player = [SPPlayerService shared];
    SPTrack *track = player.currentTrack;

    BOOL alreadyDisplayingCenter = (track.identifier.length > 0 &&
                                    [self.renderedTrackId isEqualToString:track.identifier] &&
                                    self.centerSlot.coverView.image != nil);
    self.renderedTrackId = track.identifier;

    // 先在无动画块中确保容器与三槽位具有真实非零宽高，再填充文案并布局槽位内部子视图，杜绝首次进入时子控件从 (0,0) 漂移
    [UIView performWithoutAnimation:^{
        [self layoutIfNeeded];
        [self.backgroundView layoutIfNeeded];
        [self layoutTrackPagerIfNeededForce:YES];
    }];

    if (!alreadyDisplayingCenter) {
        [self configureSlot:self.centerSlot withTrack:track slotType:1];
        UIColor *targetBg = self.centerTintedColor ?: [UIColor sp_colorWithHex:0x242428];
        if (![self.backgroundView.backgroundColor isEqual:targetBg]) {
            BOOL canAnimateBg = (self.window != nil) && !self.hidden && (self.alpha > 0.01);
            if (canAnimateBg) {
                [UIView animateWithDuration:0.26 animations:^{
                    self.backgroundView.backgroundColor = targetBg;
                }];
            } else {
                self.backgroundView.backgroundColor = targetBg;
            }
        }
    }

    [self configureSlot:self.prevSlot withTrack:player.previousTrack slotType:0];
    [self configureSlot:self.nextSlot withTrack:player.nextTrack slotType:2];
    [self layoutTrackPagerIfNeededForce:YES];
}

- (void)reloadAdjacentSlotsOnly {
    SPPlayerService *player = [SPPlayerService shared];
    [UIView performWithoutAnimation:^{
        [self layoutIfNeeded];
        [self.backgroundView layoutIfNeeded];
        [self layoutTrackPagerIfNeededForce:YES];
    }];
    [self configureSlot:self.prevSlot withTrack:player.previousTrack slotType:0];
    [self configureSlot:self.nextSlot withTrack:player.nextTrack slotType:2];
    [self layoutTrackPagerIfNeededForce:YES];
}

- (void)reloadState {
    SPPlaybackState state = [SPPlayerService shared].state;
    if (state == SPPlaybackStateLoading) {
        [self.playButton setImage:nil forState:UIControlStateNormal];
        [self.loadingIndicator startAnimating];
    } else {
        [self.loadingIndicator stopAnimating];
        BOOL playing = (state == SPPlaybackStatePlaying);
        self.playButton.opticalHorizontalOffset = playing ? 0.0 : 1.5;
        BOOL shouldAnimate = self.didInitialStateRender && (self.window != nil) && !self.hidden && CGRectGetWidth(self.playButton.bounds) > 0;
        [self.playButton sp_setSymbol:playing ? @"pause.fill" : @"play.fill"
                                 size:22
                               weight:UIImageSymbolWeightRegular
                             animated:shouldAnimate];
    }
}

- (void)reloadProgress {
    SPPlayerService *player = [SPPlayerService shared];
    CGFloat dur = player.duration;
    self.currentProgress = dur > 0 ? MIN(MAX(player.currentTime / dur, 0.0), 1.0) : 0.0;
    self.currentBufferProgress = dur > 0 ? MIN(MAX(player.bufferedTime / dur, 0.0), 1.0) : 0.0;
    [self layoutProgressFrames];
}

#pragma mark - UIScrollViewDelegate (Interactive Track Peek)

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.ignoreScrollEvents || !self.lastHasAdjacent || self.lastPagerWidth <= 0) return;
    if (!(scrollView.isDragging || scrollView.isDecelerating)) return;

    CGFloat delta = (scrollView.contentOffset.x - self.lastPagerWidth) / self.lastPagerWidth;
    UIColor *baseColor = self.centerTintedColor ?: [UIColor sp_colorWithHex:0x242428];
    if (delta > 0 && self.nextTintedColor) {
        self.backgroundView.backgroundColor = [baseColor sp_interpolatedToColor:self.nextTintedColor fraction:delta];
    } else if (delta < 0 && self.prevTintedColor) {
        self.backgroundView.backgroundColor = [baseColor sp_interpolatedToColor:self.prevTintedColor fraction:-delta];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self finalizeTrackPagerSettle:scrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        [self finalizeTrackPagerSettle:scrollView];
    }
}

- (void)finalizeTrackPagerSettle:(UIScrollView *)scrollView {
    if (!self.lastHasAdjacent || self.lastPagerWidth <= 0) return;
    NSInteger page = (NSInteger)llround(scrollView.contentOffset.x / self.lastPagerWidth);

    if (page == 1) {
        UIColor *restored = self.centerTintedColor ?: [UIColor sp_colorWithHex:0x242428];
        if (![self.backgroundView.backgroundColor isEqual:restored]) {
            [UIView animateWithDuration:0.20 animations:^{
                self.backgroundView.backgroundColor = restored;
            }];
        }
        return;
    }

    SPPlayerService *player = [SPPlayerService shared];
    BOOL isNext = (page >= 2);
    SPTrack *targetTrack = isNext ? player.nextTrack : player.previousTrack;
    if (!targetTrack) {
        self.ignoreScrollEvents = YES;
        [scrollView setContentOffset:CGPointMake(self.lastPagerWidth, 0) animated:YES];
        self.ignoreScrollEvents = NO;
        return;
    }

    // 在归位瞬间把目标槽位画面接力到 centerSlot，彻底消除闪动
    SPMiniPlayerTrackSlotView *sourceSlot = isNext ? self.nextSlot : self.prevSlot;
    UIColor *targetColor = isNext ? self.nextTintedColor : self.prevTintedColor;
    self.renderedTrackId = targetTrack.identifier;
    self.centerSlot.coverView.image = sourceSlot.coverView.image;
    self.centerSlot.titleLabel.text = sourceSlot.titleLabel.text;
    self.centerSlot.artistLabel.text = sourceSlot.artistLabel.text;
    if (targetColor) {
        self.centerTintedColor = targetColor;
        self.backgroundView.backgroundColor = targetColor;
    }

    self.ignoreScrollEvents = YES;
    [scrollView setContentOffset:CGPointMake(self.lastPagerWidth, 0) animated:NO];
    self.ignoreScrollEvents = NO;

    [SPHaptics selection];
    if (isNext) {
        [player next];
    } else {
        [player skipToPreviousTrack];
    }
}

#pragma mark - SPPlayerObserver

- (void)playerDidChangeTrack:(SPPlayerService *)player {
    [self reloadTrackSlots];
    [self reloadProgress];
}

- (void)playerDidChangeQueue:(SPPlayerService *)player {
    [self reloadAdjacentSlotsOnly];
}

- (void)playerDidChangeMode:(SPPlayerService *)player {
    [self reloadAdjacentSlotsOnly];
}

- (void)playerDidChangeState:(SPPlayerService *)player {
    [self reloadState];
}

- (void)playerDidUpdateProgress:(SPPlayerService *)player {
    [self reloadProgress];
}

#pragma mark - Actions

- (void)handleTap { [SPHaptics light]; if (self.tapHandler) self.tapHandler(); }
- (void)handleSwipeUp { [SPHaptics medium]; if (self.tapHandler) self.tapHandler(); }
- (void)playTapped { [SPHaptics medium]; [[SPPlayerService shared] togglePlayPause]; }
- (void)deviceTapped { [SPHaptics light]; [SPToast showMessage:@"当前输出：本机扬声器"]; }

@end
