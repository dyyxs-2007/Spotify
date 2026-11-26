//
//  SPNowPlayingViewController.m
//  Spotify
//

#import "SPNowPlayingViewController.h"
#import "SPCoverPreviewViewController.h"
#import "SPFullScreenLyricsViewController.h"
#import "SPQueueViewController.h"
#import "SPLyricsCardView.h"
#import "SPGradientView.h"
#import "SPScaleButton.h"
#import "SPPlayerService.h"
#import "SPMusicRepository.h"
#import "SPLibraryStore.h"
#import "SPLibraryActionSheet.h"
#import "UIImage+SPDominantColor.h"
#import "SPAlbum.h"
#import "SPFormatter.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPPlayerScrollView : UIScrollView
@end

@implementation SPPlayerScrollView

- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
    if ([view isKindOfClass:UISlider.class]) {
        return NO;
    }
    return [super touchesShouldCancelInContentView:view];
}

@end

#pragma mark - Track Card Slot (Cover + Title + Artist + Like)

@interface SPNowPlayingTrackCardView : UIView
@property (nonatomic, strong) UIView *coverShadowContainer;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UIStackView *trackMetaStack;
@property (nonatomic, strong) UILabel *trackTitleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) SPScaleButton *likeButton;
@property (nonatomic, strong) MASConstraint *coverMaxHeightConstraint;
@property (nonatomic, copy, nullable) void (^likeHandler)(void);
@property (nonatomic, assign) BOOL liked;
@property (nonatomic, copy, nullable) NSString *trackIdentifier;
@end

@implementation SPNowPlayingTrackCardView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _coverShadowContainer = [UIView new];
        _coverShadowContainer.layer.shadowColor = UIColor.blackColor.CGColor;
        _coverShadowContainer.layer.shadowOpacity = 0.5;
        _coverShadowContainer.layer.shadowRadius = 24;
        _coverShadowContainer.layer.shadowOffset = CGSizeMake(0, 14);
        [self addSubview:_coverShadowContainer];

        _coverView = [UIImageView new];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.layer.cornerRadius = 8;
        _coverView.layer.cornerCurve = kCACornerCurveContinuous;
        [_coverShadowContainer addSubview:_coverView];

        _trackTitleLabel = [UILabel new];
        _trackTitleLabel.font = [SPTheme fontOfSize:22 weight:UIFontWeightBold];
        _trackTitleLabel.textColor = UIColor.whiteColor;
        [_trackTitleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        _artistLabel = [UILabel new];
        _artistLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightRegular];
        _artistLabel.textColor = [UIColor colorWithWhite:1 alpha:0.72];
        [_artistLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        UIStackView *trackMetaStack = [[UIStackView alloc] initWithArrangedSubviews:@[_trackTitleLabel, _artistLabel]];
        trackMetaStack.axis = UILayoutConstraintAxisVertical;
        trackMetaStack.spacing = 4;
        _trackMetaStack = trackMetaStack;
        [self addSubview:trackMetaStack];

        _likeButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
        [_likeButton sp_setSymbol:@"heart" size:22 weight:UIImageSymbolWeightMedium animated:NO];
        _likeButton.tintColor = UIColor.whiteColor;
        [_likeButton addTarget:self action:@selector(likeBtnTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_likeButton];

        [_coverShadowContainer mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self).offset(10);
            make.centerX.equalTo(self);
            make.height.equalTo(self.coverShadowContainer.mas_width);
            self.coverMaxHeightConstraint = make.width.mas_equalTo(320);
        }];
        [_coverView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.coverShadowContainer);
        }];
        [trackMetaStack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.coverShadowContainer.mas_bottom).offset(24);
            make.left.equalTo(self).offset(28);
            make.right.equalTo(self.likeButton.mas_left).offset(-12);
            make.bottom.equalTo(self).offset(-4);
        }];
        [_likeButton mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(self).offset(-24);
            make.centerY.equalTo(trackMetaStack);
            make.size.mas_equalTo(CGSizeMake(44, 44));
        }];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGRectIsEmpty(self.coverShadowContainer.bounds)) {
        self.coverShadowContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.coverShadowContainer.bounds
                                                                                 cornerRadius:8].CGPath;
    }
}

- (void)likeBtnTapped {
    if (self.likeHandler) self.likeHandler();
}

- (void)configureWithTrack:(nullable SPTrack *)track
   dominantColorCompletion:(nullable void (^)(UIColor *color))completion {
    self.trackIdentifier = track.identifier;
    if (!track) {
        self.trackTitleLabel.text = @"";
        self.artistLabel.text = @"";
        [self.coverView sp_cancelCoverLoadAndReset];
        [self applyLiked:NO animated:NO];
        return;
    }
    self.trackTitleLabel.text = track.name ?: @"";
    self.artistLabel.text = [track artistNames];
    [self applyLiked:[[SPLibraryStore shared] isTrackLiked:track.identifier] animated:NO];
    [self.coverView sp_setCoverWithItem:track dominantColorCompletion:completion];
}

- (void)applyLiked:(BOOL)liked animated:(BOOL)animated {
    self.liked = liked;
    NSString *symbol = liked ? @"heart.fill" : @"heart";
    self.likeButton.tintColor = liked ? SPTheme.brandGreenColor : UIColor.whiteColor;
    [self.likeButton sp_setSymbol:symbol size:22 weight:UIImageSymbolWeightMedium animated:animated];
}

- (void)applyPlayingScale:(BOOL)playing animated:(BOOL)animated {
    CGAffineTransform targetTransform = playing ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.92, 0.92);
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.35
                              delay:0
             usingSpringWithDamping:0.84
              initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self.coverShadowContainer.transform = targetTransform;
        } completion:nil];
    } else {
        self.coverShadowContainer.transform = targetTransform;
    }
}

@end

#pragma mark - SPNowPlayingViewController

@interface SPNowPlayingViewController () <SPPlayerObserver, UIGestureRecognizerDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) SPGradientView *backgroundGradient;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *contextSubLabel;
@property (nonatomic, strong) UILabel *contextTitleLabel;
@property (nonatomic, strong) SPScaleButton *moreButton;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIView *topBarHairline;
@property (nonatomic, strong) SPGradientView *scrollTopFadeView;
@property (nonatomic, assign) BOOL topBarShowingTrackInfo;
@property (nonatomic, strong) UIScrollView *mainScrollView;
@property (nonatomic, strong) UIView *scrollContentView;
@property (nonatomic, strong) UIView *playerStageView;

@property (nonatomic, strong) UIScrollView *trackPagerScrollView;
@property (nonatomic, strong) MASConstraint *trackPagerHeightConstraint;
@property (nonatomic, strong) SPNowPlayingTrackCardView *prevCard;
@property (nonatomic, strong) SPNowPlayingTrackCardView *centerCard;
@property (nonatomic, strong) SPNowPlayingTrackCardView *nextCard;

@property (nonatomic, strong) SPProgressSlider *progressSlider;
@property (nonatomic, strong) UIView *bufferTrackView;
@property (nonatomic, strong) UILabel *currentTimeLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) SPScaleButton *shuffleButton;
@property (nonatomic, strong) UIView *shuffleDot;
@property (nonatomic, strong) SPScaleButton *prevButton;
@property (nonatomic, strong) SPScaleButton *playPauseButton;
@property (nonatomic, strong) SPScaleButton *nextButton;
@property (nonatomic, strong) SPScaleButton *repeatButton;
@property (nonatomic, strong) UIView *repeatDot;
@property (nonatomic, strong) SPScaleButton *lyricsHintButton;
@property (nonatomic, strong) SPLyricsCardView *lyricsCardView;

@property (nonatomic, strong) UIPanGestureRecognizer *dismissPan;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, strong, nullable) UIColor *prevThemeColor;
@property (nonatomic, strong, nullable) UIColor *currentThemeColor;
@property (nonatomic, strong, nullable) UIColor *nextThemeColor;
@property (nonatomic, copy, nullable) NSString *renderedTrackId;
@property (nonatomic, copy, nullable) NSString *pagerDragStartTrackId;

@property (nonatomic, assign) BOOL ignorePagerScrollEvents;
@property (nonatomic, assign) CGFloat lastComputedPagerHeight;
@property (nonatomic, assign) CGFloat lastPagerWidth;
@property (nonatomic, assign) CGFloat lastPagerHeight;
@property (nonatomic, assign) BOOL lastHasAdjacent;
@property (nonatomic, assign) NSUInteger lyricRequestToken;
@property (nonatomic, assign, readwrite) CGFloat dismissVelocityY;
@end

@implementation SPNowPlayingViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (UIImageView *)coverView {
    return self.centerCard.coverView;
}

- (UIView *)coverShadowContainer {
    return self.centerCard.coverShadowContainer;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor sp_colorWithHex:0x121214];
    [self setupViews];
    [self setupGestures];
    [[SPPlayerService shared] addObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(libraryDidUpdate)
                                                 name:SPLibraryDidUpdateNotification
                                               object:nil];
    [self reloadAllAnimated:NO];
}

- (void)libraryDidUpdate {
    [self syncLikeButtonAnimated:NO];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.mainScrollView layoutIfNeeded];
    [self.playerStageView layoutIfNeeded];
    [self updateTrackPagerDimensionsIfNeeded];
    [self updateBufferFrame];
    [self layoutTrackPagerIfNeededForce:NO];
}

- (void)updateTrackPagerDimensionsIfNeeded {
    CGFloat w = CGRectGetWidth(self.mainScrollView.bounds);
    CGFloat viewportH = CGRectGetHeight(self.mainScrollView.bounds);
    if (w <= 0 || viewportH <= 0) return;

    CGFloat maxCoverByHeight = MAX(220.0, viewportH - 350.0);
    CGFloat coverSide = floor(MIN(MIN(w - 56.0, 336.0), maxCoverByHeight));
    self.prevCard.coverMaxHeightConstraint.mas_equalTo(coverSide);
    self.centerCard.coverMaxHeightConstraint.mas_equalTo(coverSide);
    self.nextCard.coverMaxHeightConstraint.mas_equalTo(coverSide);

    CGFloat pagerHeight = coverSide + 92.0;
    if (fabs(self.lastComputedPagerHeight - pagerHeight) > 0.5) {
        self.lastComputedPagerHeight = pagerHeight;
        self.trackPagerHeightConstraint.mas_equalTo(pagerHeight);
        [self.view layoutIfNeeded];
    }
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
    self.ignorePagerScrollEvents = YES;

    [UIView performWithoutAnimation:^{
        if (hasAdjacent) {
            self.prevCard.hidden = NO;
            self.nextCard.hidden = NO;
            self.prevCard.frame = CGRectMake(0, 0, w, h);
            self.centerCard.frame = CGRectMake(w, 0, w, h);
            self.nextCard.frame = CGRectMake(w * 2.0, 0, w, h);
            self.trackPagerScrollView.contentSize = CGSizeMake(w * 3.0, h);
            self.trackPagerScrollView.scrollEnabled = YES;
            if (!(self.trackPagerScrollView.isDragging || self.trackPagerScrollView.isDecelerating)) {
                [self.trackPagerScrollView setContentOffset:CGPointMake(w, 0) animated:NO];
            }
        } else {
            self.prevCard.hidden = YES;
            self.nextCard.hidden = YES;
            self.centerCard.frame = CGRectMake(0, 0, w, h);
            self.trackPagerScrollView.contentSize = CGSizeMake(w, h);
            self.trackPagerScrollView.scrollEnabled = NO;
            [self.trackPagerScrollView setContentOffset:CGPointZero animated:NO];
        }
        [self.prevCard layoutIfNeeded];
        [self.centerCard layoutIfNeeded];
        [self.nextCard layoutIfNeeded];
    }];
    self.ignorePagerScrollEvents = NO;
}

- (void)updateBufferFrame {
    CGRect trackRect = [self.progressSlider trackRectForBounds:self.progressSlider.bounds];
    CGRect converted = [self.progressSlider convertRect:trackRect toView:self.playerStageView];
    SPPlayerService *player = [SPPlayerService shared];
    CGFloat ratio = player.duration > 0 ? MIN(MAX(player.bufferedTime / player.duration, 0.0), 1.0) : 0.0;
    CGFloat h = MAX(CGRectGetHeight(converted), 3.0);
    self.bufferTrackView.frame = CGRectMake(CGRectGetMinX(converted),
                                            CGRectGetMidY(converted) - h * 0.5,
                                            CGRectGetWidth(converted) * ratio,
                                            h);
    self.bufferTrackView.layer.cornerRadius = h * 0.5;
}

- (void)setupViews {
    _backgroundGradient = [SPGradientView new];
    _backgroundGradient.colors = @[[UIColor sp_colorWithHex:0x28282D], [UIColor sp_colorWithHex:0x121214]];
    [self.view addSubview:_backgroundGradient];

    // 顶部提示可下拉的精致手势条（Grabber）
    UIView *grabber = [UIView new];
    grabber.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.28];
    grabber.layer.cornerRadius = 2.25;
    grabber.layer.cornerCurve = kCACornerCurveContinuous;
    grabber.userInteractionEnabled = NO;
    [self.view addSubview:grabber];

    // 顶部固定导航栏
    SPScaleButton *dismissBtn = [self iconButton:@"chevron.down" size:20 weight:UIImageSymbolWeightSemibold action:@selector(dismissTapped)];
    _moreButton = [self iconButton:@"ellipsis" size:20 weight:UIImageSymbolWeightMedium action:@selector(moreTapped)];

    _contextSubLabel = [UILabel new];
    _contextSubLabel.text = @"正在播放自";
    _contextSubLabel.font = [SPTheme fontOfSize:11 weight:UIFontWeightMedium];
    _contextSubLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    _contextSubLabel.textAlignment = NSTextAlignmentCenter;

    _contextTitleLabel = [UILabel new];
    _contextTitleLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightBold];
    _contextTitleLabel.textColor = UIColor.whiteColor;
    _contextTitleLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[_contextSubLabel, _contextTitleLabel]];
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.spacing = 2;

    UIView *topBar = [UIView new];
    _topBar = topBar;
    [topBar addSubview:dismissBtn];
    [topBar addSubview:titleStack];
    [topBar addSubview:_moreButton];
    [self.view addSubview:topBar];

    _topBarHairline = [UIView new];
    _topBarHairline.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    _topBarHairline.alpha = 0.0;
    [topBar addSubview:_topBarHairline];

    // 空白待机播放页（未播放 / 退出登录 / 首次登录 / 切换账号后默认态）
    _emptyStateView = [self buildEmptyStateView];
    _emptyStateView.hidden = YES;
    [self.view addSubview:_emptyStateView];

    // 主垂直滚动容器（上方主控舞台 + 下方歌词卡片）
    _mainScrollView = [SPPlayerScrollView new];
    _mainScrollView.delaysContentTouches = NO;
    _mainScrollView.showsVerticalScrollIndicator = NO;
    _mainScrollView.alwaysBounceVertical = YES;
    _mainScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _mainScrollView.delegate = self;
    [self.view addSubview:_mainScrollView];

    // 下滑至歌词区时柔化主滚动区顶缘，消除封面硬裁切感
    _scrollTopFadeView = [SPGradientView new];
    _scrollTopFadeView.userInteractionEnabled = NO;
    _scrollTopFadeView.alpha = 0.0;
    _scrollTopFadeView.locations = @[@0.0, @1.0];
    [self.view addSubview:_scrollTopFadeView];

    _scrollContentView = [UIView new];
    [_mainScrollView addSubview:_scrollContentView];

    _playerStageView = [UIView new];
    [_scrollContentView addSubview:_playerStageView];

    // 三槽位横向滑动切歌容器
    _trackPagerScrollView = [UIScrollView new];
    _trackPagerScrollView.pagingEnabled = YES;
    _trackPagerScrollView.showsHorizontalScrollIndicator = NO;
    _trackPagerScrollView.showsVerticalScrollIndicator = NO;
    _trackPagerScrollView.bounces = YES;
    _trackPagerScrollView.directionalLockEnabled = YES;
    _trackPagerScrollView.delegate = self;
    [_playerStageView addSubview:_trackPagerScrollView];

    __weak typeof(self) weakSelf = self;
    _prevCard = [SPNowPlayingTrackCardView new];
    _centerCard = [SPNowPlayingTrackCardView new];
    _nextCard = [SPNowPlayingTrackCardView new];
    _centerCard.likeHandler = ^{ [weakSelf likeTapped]; };
    [_trackPagerScrollView addSubview:_prevCard];
    [_trackPagerScrollView addSubview:_centerCard];
    [_trackPagerScrollView addSubview:_nextCard];

    // 进度条 + 缓冲条 + 时间
    _bufferTrackView = [UIView new];
    _bufferTrackView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.28];
    _bufferTrackView.layer.cornerRadius = 1.5;
    _bufferTrackView.userInteractionEnabled = NO;
    [_playerStageView addSubview:_bufferTrackView];

    _progressSlider = [SPProgressSlider new];
    _progressSlider.minimumTrackTintColor = UIColor.whiteColor;
    _progressSlider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.16];
    [_progressSlider setThumbImage:[self circleThumbWithDiameter:12] forState:UIControlStateNormal];
    [_progressSlider setThumbImage:[self circleThumbWithDiameter:16] forState:UIControlStateHighlighted];
    [_progressSlider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [_progressSlider addTarget:self action:@selector(sliderValueChanged) forControlEvents:UIControlEventValueChanged];
    [_progressSlider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_playerStageView addSubview:_progressSlider];

    _currentTimeLabel = [UILabel new];
    _currentTimeLabel.font = [SPTheme monospacedDigitFontOfSize:12 weight:UIFontWeightRegular];
    _currentTimeLabel.textColor = [UIColor colorWithWhite:1 alpha:0.65];

    _durationLabel = [UILabel new];
    _durationLabel.font = [SPTheme monospacedDigitFontOfSize:12 weight:UIFontWeightRegular];
    _durationLabel.textColor = [UIColor colorWithWhite:1 alpha:0.65];
    _durationLabel.textAlignment = NSTextAlignmentRight;
    [_playerStageView addSubview:_currentTimeLabel];
    [_playerStageView addSubview:_durationLabel];

    // 主控行
    _shuffleButton = [self iconButton:@"shuffle" size:20 weight:UIImageSymbolWeightMedium action:@selector(shuffleTapped)];
    _prevButton = [self iconButton:@"backward.end.fill" size:28 weight:UIImageSymbolWeightRegular action:@selector(prevTapped)];
    _nextButton = [self iconButton:@"forward.end.fill" size:28 weight:UIImageSymbolWeightRegular action:@selector(nextTapped)];
    _repeatButton = [self iconButton:@"repeat" size:20 weight:UIImageSymbolWeightMedium action:@selector(repeatTapped)];

    _playPauseButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _playPauseButton.backgroundColor = UIColor.whiteColor;
    _playPauseButton.layer.cornerRadius = 32;
    _playPauseButton.tintColor = UIColor.blackColor;
    [_playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *controlsStack = [[UIStackView alloc] initWithArrangedSubviews:@[_shuffleButton, _prevButton, _playPauseButton, _nextButton, _repeatButton]];
    controlsStack.axis = UILayoutConstraintAxisHorizontal;
    controlsStack.distribution = UIStackViewDistributionEqualSpacing;
    controlsStack.alignment = UIStackViewAlignmentCenter;
    [_playerStageView addSubview:controlsStack];

    _shuffleDot = [UIView new];
    _shuffleDot.backgroundColor = SPTheme.brandGreenColor;
    _shuffleDot.layer.cornerRadius = 2.0;
    _shuffleDot.hidden = YES;
    [_playerStageView addSubview:_shuffleDot];

    _repeatDot = [UIView new];
    _repeatDot.backgroundColor = SPTheme.brandGreenColor;
    _repeatDot.layer.cornerRadius = 2.0;
    _repeatDot.hidden = YES;
    [_playerStageView addSubview:_repeatDot];

    // 底部工具行（设备 · 歌词锚点胶囊 · 队列）
    SPScaleButton *deviceBtn = [self iconButton:@"hifispeaker" size:19 weight:UIImageSymbolWeightRegular action:@selector(deviceTapped)];
    SPScaleButton *queueBtn = [self iconButton:@"list.bullet" size:20 weight:UIImageSymbolWeightMedium action:@selector(queueTapped)];

    UIButtonConfiguration *lyricsPillCfg = [UIButtonConfiguration plainButtonConfiguration];
    lyricsPillCfg.title = @"歌词";
    lyricsPillCfg.image = [SPTheme symbol:@"quote.bubble" size:13 weight:UIImageSymbolWeightSemibold];
    lyricsPillCfg.imagePadding = 5;
    lyricsPillCfg.baseForegroundColor = [UIColor colorWithWhite:1 alpha:0.86];
    lyricsPillCfg.contentInsets = NSDirectionalEdgeInsetsMake(6, 10, 6, 12);
    lyricsPillCfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [SPTheme fontOfSize:12 weight:UIFontWeightSemibold];
        return attrs;
    };
    _lyricsHintButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _lyricsHintButton.configuration = lyricsPillCfg;
    _lyricsHintButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    _lyricsHintButton.layer.cornerRadius = 15;
    _lyricsHintButton.layer.cornerCurve = kCACornerCurveContinuous;
    [_lyricsHintButton addTarget:self action:@selector(scrollToLyricsTapped) forControlEvents:UIControlEventTouchUpInside];

    [_playerStageView addSubview:deviceBtn];
    [_playerStageView addSubview:_lyricsHintButton];
    [_playerStageView addSubview:queueBtn];

    // 下滑歌词卡片
    _lyricsCardView = [SPLyricsCardView new];
    _lyricsCardView.seekHandler = ^(NSTimeInterval time) {
        [[SPPlayerService shared] seekToTime:time];
        if (![SPPlayerService shared].isPlaying) {
            [[SPPlayerService shared] play];
        }
    };
    _lyricsCardView.expandHandler = ^{
        [weakSelf presentFullScreenLyrics];
    };
    [_scrollContentView addSubview:_lyricsCardView];

    // 约束
    [_backgroundGradient mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [grabber mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(4);
        make.centerX.equalTo(self.view);
        make.size.mas_equalTo(CGSizeMake(38, 4.5));
    }];
    [topBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(12);
        make.left.right.equalTo(self.view);
        make.height.mas_equalTo(48);
    }];
    [dismissBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(topBar).offset(12);
        make.centerY.equalTo(topBar);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [_moreButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(topBar).offset(-12);
        make.centerY.equalTo(topBar);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [titleStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(dismissBtn.mas_right).offset(8);
        make.right.equalTo(self.moreButton.mas_left).offset(-8);
        make.centerY.equalTo(topBar);
    }];
    [_topBarHairline mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(topBar);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [_emptyStateView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(topBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];

    [_mainScrollView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(topBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
    [_scrollTopFadeView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(topBar.mas_bottom);
        make.left.right.equalTo(self.view);
        make.height.mas_equalTo(26);
    }];
    [_scrollContentView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.mainScrollView);
        make.width.equalTo(self.mainScrollView);
    }];
    [_playerStageView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.scrollContentView);
    }];
    [_trackPagerScrollView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.playerStageView);
        self.trackPagerHeightConstraint = make.height.mas_equalTo(420);
    }];

    [_progressSlider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.trackPagerScrollView.mas_bottom).offset(14);
        make.left.equalTo(self.playerStageView).offset(28);
        make.right.equalTo(self.playerStageView).offset(-28);
    }];
    [_currentTimeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.progressSlider.mas_bottom).offset(4);
        make.left.equalTo(self.progressSlider);
    }];
    [_durationLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.currentTimeLabel);
        make.right.equalTo(self.progressSlider);
    }];

    [_playPauseButton mas_makeConstraints:^(MASConstraintMaker *make) { make.size.mas_equalTo(CGSizeMake(64, 64)); }];
    [_shuffleButton mas_makeConstraints:^(MASConstraintMaker *make) { make.size.mas_equalTo(CGSizeMake(40, 40)); }];
    [_prevButton mas_makeConstraints:^(MASConstraintMaker *make) { make.size.mas_equalTo(CGSizeMake(44, 44)); }];
    [_nextButton mas_makeConstraints:^(MASConstraintMaker *make) { make.size.mas_equalTo(CGSizeMake(44, 44)); }];
    [_repeatButton mas_makeConstraints:^(MASConstraintMaker *make) { make.size.mas_equalTo(CGSizeMake(40, 40)); }];
    [controlsStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.currentTimeLabel.mas_bottom).offset(14);
        make.left.equalTo(self.playerStageView).offset(24);
        make.right.equalTo(self.playerStageView).offset(-24);
    }];
    [_shuffleDot mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.shuffleButton.mas_bottom).offset(-3);
        make.centerX.equalTo(self.shuffleButton);
        make.size.mas_equalTo(CGSizeMake(4, 4));
    }];
    [_repeatDot mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.repeatButton.mas_bottom).offset(-3);
        make.centerX.equalTo(self.repeatButton);
        make.size.mas_equalTo(CGSizeMake(4, 4));
    }];

    [deviceBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(controlsStack.mas_bottom).offset(16);
        make.left.equalTo(self.playerStageView).offset(24);
        make.size.mas_equalTo(CGSizeMake(40, 40));
        make.bottom.equalTo(self.playerStageView).offset(-12);
    }];
    [_lyricsHintButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.playerStageView);
        make.centerY.equalTo(deviceBtn);
        make.height.mas_equalTo(30);
    }];
    [queueBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.playerStageView).offset(-24);
        make.centerY.equalTo(deviceBtn);
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];

    [_lyricsCardView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.playerStageView.mas_bottom).offset(10);
        make.left.equalTo(self.scrollContentView).offset(16);
        make.right.equalTo(self.scrollContentView).offset(-16);
        make.height.mas_equalTo(420);
        make.bottom.equalTo(self.scrollContentView).offset(-44);
    }];
}

- (UIView *)buildEmptyStateView {
    UIView *container = [UIView new];

    UIView *centerBox = [UIView new];
    [container addSubview:centerBox];

    // 暗夜磨砂唱片卡
    UIView *discOuter = [UIView new];
    discOuter.backgroundColor = [UIColor sp_colorWithHex:0x1C1D24];
    discOuter.layer.cornerRadius = 28;
    discOuter.layer.cornerCurve = kCACornerCurveContinuous;
    discOuter.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    discOuter.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    discOuter.layer.shadowColor = SPTheme.brandGreenColor.CGColor;
    discOuter.layer.shadowOpacity = 0.16;
    discOuter.layer.shadowRadius = 28;
    discOuter.layer.shadowOffset = CGSizeZero;
    discOuter.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 216, 216) cornerRadius:28].CGPath;
    [centerBox addSubview:discOuter];

    UIView *discRing = [UIView new];
    discRing.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
    discRing.layer.cornerRadius = 64;
    discRing.layer.cornerCurve = kCACornerCurveCircular;
    discRing.layer.borderWidth = 1.0;
    discRing.layer.borderColor = [SPTheme.brandGreenColor colorWithAlphaComponent:0.26].CGColor;
    [discOuter addSubview:discRing];

    UIImageView *discIcon = [[UIImageView alloc] initWithImage:[SPTheme symbol:@"waveform" size:42 weight:UIImageSymbolWeightMedium]];
    discIcon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    discIcon.contentMode = UIViewContentModeScaleAspectFit;
    [discRing addSubview:discIcon];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"暂无正在播放的歌曲";
    titleLabel.font = [SPTheme fontOfSize:22 weight:UIFontWeightBold];
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [centerBox addSubview:titleLabel];

    UILabel *subLabel = [UILabel new];
    subLabel.text = @"首次进入、退出登录或切换账号后已自动静音待机\n从首页或我的音乐库挑选一首歌，随时开始畅听";
    subLabel.font = [SPTheme fontOfSize:13.5 weight:UIFontWeightRegular];
    subLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
    subLabel.textAlignment = NSTextAlignmentCenter;
    subLabel.numberOfLines = 0;
    subLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
    [centerBox addSubview:subLabel];

    SPScaleButton *homeBtn = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    homeBtn.backgroundColor = SPTheme.brandGreenColor;
    homeBtn.layer.cornerRadius = 24;
    homeBtn.layer.cornerCurve = kCACornerCurveContinuous;
    [homeBtn setTitle:@"去首页发现音乐" forState:UIControlStateNormal];
    [homeBtn setTitleColor:[UIColor sp_colorWithHex:0x0B0B0C] forState:UIControlStateNormal];
    homeBtn.titleLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightBold];
    [homeBtn addTarget:self action:@selector(emptyDiscoverTapped) forControlEvents:UIControlEventTouchUpInside];
    [centerBox addSubview:homeBtn];

    SPScaleButton *libBtn = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    libBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    libBtn.layer.cornerRadius = 24;
    libBtn.layer.cornerCurve = kCACornerCurveContinuous;
    libBtn.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    libBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    [libBtn setTitle:@"前往我的音乐库" forState:UIControlStateNormal];
    [libBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    libBtn.titleLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightSemibold];
    [libBtn addTarget:self action:@selector(emptyLibraryTapped) forControlEvents:UIControlEventTouchUpInside];
    [centerBox addSubview:libBtn];

    [centerBox mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(container).offset(-18);
        make.left.equalTo(container).offset(32);
        make.right.equalTo(container).offset(-32);
    }];
    [discOuter mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.centerX.equalTo(centerBox);
        make.size.mas_equalTo(CGSizeMake(216, 216));
    }];
    [discRing mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(discOuter);
        make.size.mas_equalTo(CGSizeMake(128, 128));
    }];
    [discIcon mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(discRing);
        make.size.mas_equalTo(CGSizeMake(48, 48));
    }];
    [titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(discOuter.mas_bottom).offset(28);
        make.left.right.equalTo(centerBox);
    }];
    [subLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(titleLabel.mas_bottom).offset(10);
        make.left.right.equalTo(centerBox);
    }];
    [homeBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(subLabel.mas_bottom).offset(28);
        make.centerX.equalTo(centerBox);
        make.width.mas_equalTo(220);
        make.height.mas_equalTo(48);
    }];
    [libBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(homeBtn.mas_bottom).offset(12);
        make.centerX.equalTo(centerBox);
        make.width.mas_equalTo(220);
        make.height.mas_equalTo(48);
        make.bottom.equalTo(centerBox);
    }];
    return container;
}

- (SPScaleButton *)iconButton:(NSString *)symbol size:(CGFloat)size weight:(UIImageSymbolWeight)weight action:(SEL)action {
    SPScaleButton *btn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [btn sp_setSymbol:symbol size:size weight:weight animated:NO];
    btn.tintColor = UIColor.whiteColor;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (UIImage *)circleThumbWithDiameter:(CGFloat)diameter {
    CGSize size = CGSizeMake(diameter, diameter);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.whiteColor setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, diameter, diameter)] fill];
    }];
}

#pragma mark - Gestures

- (void)setupGestures {
    self.dismissPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.dismissPan.delegate = self;
    [self.view addGestureRecognizer:self.dismissPan];

    self.centerCard.coverShadowContainer.userInteractionEnabled = YES;
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(coverLongPressed:)];
    longPress.minimumPressDuration = 0.35;
    [self.centerCard.coverShadowContainer addGestureRecognizer:longPress];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (self.isBeingPresented || self.isBeingDismissed) return NO;
    if (!self.mainScrollView.hidden) {
        CGPoint location = [gestureRecognizer locationInView:self.playerStageView];
        CGRect sliderArea = CGRectInset(self.progressSlider.frame, -16, -18);
        if (CGRectContainsPoint(sliderArea, location)) return NO;
    }

    if (gestureRecognizer == self.dismissPan) {
        CGPoint velocity = [self.dismissPan velocityInView:self.view];
        if (!(velocity.y > 0 && fabs(velocity.y) >= fabs(velocity.x))) return NO;
        CGPoint viewLoc = [self.dismissPan locationInView:self.view];
        if (viewLoc.y <= CGRectGetMaxY(self.topBar.frame) + 8.0) {
            return YES;
        }
        return self.mainScrollView.contentOffset.y <= 2.0;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.dismissPan &&
        (otherGestureRecognizer == self.mainScrollView.panGestureRecognizer ||
         otherGestureRecognizer == self.trackPagerScrollView.panGestureRecognizer)) {
        return YES;
    }
    return NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.view];
    CGPoint velocity = [pan velocityInView:self.view];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();

    if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat dy = MAX(translation.y, 0);
        CGFloat progress = MIN(dy / 300.0, 1.0);
        // 缓出阻尼曲线，保留物理卡片跟随感且全程不淡出卡片本身（消除廉价半透明鬼影）
        CGFloat eased = 1.0 - pow(1.0 - progress, 1.6);

        self.view.clipsToBounds = YES;
        self.view.layer.cornerCurve = kCACornerCurveContinuous;
        self.view.layer.cornerRadius = reduceMotion ? 0.0 : (18.0 + 26.0 * eased);
        self.view.layer.borderWidth = reduceMotion ? 0.0 : (1.0 / UIScreen.mainScreen.scale);
        self.view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
        self.view.alpha = 1.0;

        if (!reduceMotion) {
            CGFloat scale = 1.0 - 0.065 * eased;
            CGFloat dx = MAX(-24.0, MIN(24.0, translation.x * 0.14));
            CGFloat ty = dy * 0.86;
            self.view.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale),
                                                          CGAffineTransformMakeTranslation(dx, ty));
        }
        if (self.dismissDragProgressHandler) {
            self.dismissDragProgressHandler(eased);
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (translation.y > 105 || velocity.y > 700) {
            self.dismissVelocityY = MAX(0.0, velocity.y);
            [SPHaptics light];
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            self.dismissVelocityY = 0.0;
            [UIView animateWithDuration:reduceMotion ? 0.16 : 0.34
                                  delay:0
                 usingSpringWithDamping:reduceMotion ? 1.0 : 0.88
                  initialSpringVelocity:reduceMotion ? 0.0 : 0.2
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                self.view.transform = CGAffineTransformIdentity;
                self.view.layer.cornerRadius = 0.0;
                self.view.layer.borderWidth = 0.0;
                self.view.alpha = 1.0;
                if (self.dismissDragProgressHandler) {
                    self.dismissDragProgressHandler(0.0);
                }
            } completion:^(BOOL finished) {
                if (CGAffineTransformIsIdentity(self.view.transform)) {
                    self.view.clipsToBounds = NO;
                }
            }];
        }
    }
}

#pragma mark - Reload & Theme Morphing

- (UIColor *)initialThemeColorForTrack:(nullable SPTrack *)track {
    if (!track) return [UIColor sp_colorWithHex:0x28282D];
    NSString *cacheKey = track.coverURL.length ? track.coverURL : track.identifier;
    UIColor *cached = [UIImage sp_cachedDominantColorForKey:cacheKey];
    if (cached) return cached;
    if (track.themeColor) return [track.themeColor sp_clampedForDarkBackground];
    return [UIColor sp_colorWithHex:0x28282D];
}

- (void)applyGradientWithTopColor:(UIColor *)topColor animated:(BOOL)animated {
    UIColor *darkCanvas = [UIColor sp_colorWithHex:0x121214];
    [self.backgroundGradient setColors:@[topColor, [topColor sp_darkenedBy:0.55], darkCanvas] animated:animated];
    UIColor *edgeTint = [topColor sp_darkenedBy:0.08];
    [self.scrollTopFadeView setColors:@[[edgeTint colorWithAlphaComponent:0.95], [edgeTint colorWithAlphaComponent:0.0]] animated:animated];
    [self.lyricsCardView applyThemeColor:topColor animated:animated];
}

- (void)reloadAllAnimated:(BOOL)animated {
    [self reloadTrackAnimated:animated];
    [self reloadStateAnimated:animated];
    [self reloadProgress];
    [self reloadModesAnimated:animated];
}

- (void)configureAdjacentCards {
    SPPlayerService *player = [SPPlayerService shared];
    SPTrack *prev = player.previousTrack;
    SPTrack *next = player.nextTrack;
    self.prevThemeColor = [self initialThemeColorForTrack:prev];
    self.nextThemeColor = [self initialThemeColorForTrack:next];

    __weak typeof(self) weakSelf = self;
    NSString *prevId = prev.identifier;
    [self.prevCard configureWithTrack:prev dominantColorCompletion:^(UIColor *color) {
        if ([weakSelf.prevCard.trackIdentifier isEqualToString:prevId]) {
            weakSelf.prevThemeColor = color;
        }
    }];
    NSString *nextId = next.identifier;
    [self.nextCard configureWithTrack:next dominantColorCompletion:^(UIColor *color) {
        if ([weakSelf.nextCard.trackIdentifier isEqualToString:nextId]) {
            weakSelf.nextThemeColor = color;
        }
    }];
    [self layoutTrackPagerIfNeededForce:YES];
}

- (void)reloadTrackAnimated:(BOOL)animated {
    SPPlayerService *player = [SPPlayerService shared];
    SPTrack *track = player.currentTrack;

    if (!track) {
        self.renderedTrackId = nil;
        self.topBarShowingTrackInfo = NO;
        self.topBarHairline.alpha = 0.0;
        self.scrollTopFadeView.alpha = 0.0;
        self.centerCard.coverShadowContainer.alpha = 1.0;
        self.centerCard.trackMetaStack.alpha = 1.0;
        self.centerCard.likeButton.alpha = 1.0;
        self.centerCard.likeButton.userInteractionEnabled = YES;
        self.contextSubLabel.text = @"待机模式";
        self.contextTitleLabel.text = @"空白播放页";
        self.moreButton.hidden = YES;
        self.mainScrollView.hidden = YES;
        self.emptyStateView.hidden = NO;
        UIColor *idleTop = [UIColor sp_colorWithHex:0x1E222B];
        UIColor *idleDark = [UIColor sp_colorWithHex:0x121214];
        [self.backgroundGradient setColors:@[idleTop, [UIColor sp_colorWithHex:0x15171C], idleDark] animated:animated];
        [self.centerCard configureWithTrack:nil dominantColorCompletion:nil];
        [self.lyricsCardView configureWithDocument:nil];
        return;
    }

    self.contextSubLabel.text = @"正在播放自";
    self.moreButton.hidden = NO;
    self.mainScrollView.hidden = NO;
    self.emptyStateView.hidden = YES;

    BOOL alreadyDisplayingCenter = (track.identifier.length > 0 &&
                                    [self.renderedTrackId isEqualToString:track.identifier] &&
                                    self.centerCard.coverView.image != nil);
    self.renderedTrackId = track.identifier;
    self.topBarShowingTrackInfo = NO;
    [self updateTopBarChromeForVerticalOffset:self.mainScrollView.contentOffset.y animated:NO];

    if (!alreadyDisplayingCenter) {
        UIColor *initialTop = [self initialThemeColorForTrack:track];
        self.currentThemeColor = initialTop;
        [self applyGradientWithTopColor:initialTop animated:animated];

        __weak typeof(self) weakSelf = self;
        NSString *trackId = track.identifier;
        [self.centerCard configureWithTrack:track dominantColorCompletion:^(UIColor *color) {
            if (![weakSelf.renderedTrackId isEqualToString:trackId]) return;
            weakSelf.currentThemeColor = color;
            if (!weakSelf.trackPagerScrollView.isDragging && !weakSelf.trackPagerScrollView.isDecelerating) {
                [weakSelf applyGradientWithTopColor:color animated:YES];
            }
        }];
    } else {
        [self.centerCard applyLiked:(track ? [[SPLibraryStore shared] isTrackLiked:track.identifier] : NO) animated:NO];
    }

    [self configureAdjacentCards];
    [self loadLyricsForTrack:track];
}

- (void)loadLyricsForTrack:(nullable SPTrack *)track {
    if (!track) {
        [self.lyricsCardView configureWithDocument:nil];
        return;
    }
    self.lyricRequestToken += 1;
    NSUInteger token = self.lyricRequestToken;
    [self.lyricsCardView setLoading];

    __weak typeof(self) weakSelf = self;
    [[SPMusicRepository shared] fetchLyricsForTrack:track completion:^(SPLyricDocument *lyrics, NSError *error) {
        if (!weakSelf || weakSelf.lyricRequestToken != token) return;
        [weakSelf.lyricsCardView configureWithDocument:lyrics];
        [weakSelf.lyricsCardView updateCurrentTime:[SPPlayerService shared].currentTime animated:NO];
    }];
}

- (void)syncLikeButtonAnimated:(BOOL)animated {
    SPTrack *track = [SPPlayerService shared].currentTrack;
    BOOL liked = track ? [[SPLibraryStore shared] isTrackLiked:track.identifier] : NO;
    [self.centerCard applyLiked:liked animated:animated];
}

- (void)reloadStateAnimated:(BOOL)animated {
    BOOL playing = [SPPlayerService shared].isPlaying;
    NSString *symbol = playing ? @"pause.fill" : @"play.fill";
    self.playPauseButton.opticalHorizontalOffset = playing ? 0.0 : 2.0;
    [self.playPauseButton sp_setSymbol:symbol size:24 weight:UIImageSymbolWeightBold animated:animated];
    [self.centerCard applyPlayingScale:playing animated:animated];
    [self.prevCard applyPlayingScale:YES animated:NO];
    [self.nextCard applyPlayingScale:YES animated:NO];
}

- (void)reloadProgress {
    SPPlayerService *player = [SPPlayerService shared];
    if (!self.scrubbing) {
        NSTimeInterval duration = MAX(player.duration, 1);
        self.progressSlider.maximumValue = (float)duration;
        self.progressSlider.value = (float)MIN(player.currentTime, duration);
        self.currentTimeLabel.text = [SPFormatter timeString:player.currentTime];
        self.durationLabel.text = [SPFormatter timeString:player.duration];
        [self updateBufferFrame];
    }
    [self.lyricsCardView updateCurrentTime:player.currentTime animated:YES];
}

- (void)reloadModes {
    [self reloadModesAnimated:YES];
}

- (void)reloadModesAnimated:(BOOL)animated {
    SPPlayerService *player = [SPPlayerService shared];
    self.shuffleButton.tintColor = player.isShuffleEnabled ? SPTheme.brandGreenColor : UIColor.whiteColor;
    self.shuffleDot.hidden = !player.isShuffleEnabled;

    NSString *repeatIcon = (player.repeatMode == SPRepeatModeOne) ? @"repeat.1" : @"repeat";
    [self.repeatButton sp_setSymbol:repeatIcon size:20 weight:UIImageSymbolWeightMedium animated:animated];
    BOOL repeatActive = (player.repeatMode != SPRepeatModeOff);
    self.repeatButton.tintColor = repeatActive ? SPTheme.brandGreenColor : UIColor.whiteColor;
    self.repeatDot.hidden = !repeatActive;
}

#pragma mark - UIScrollViewDelegate (Vertical Lyrics Chrome & Horizontal Track Paging)

- (void)updateTopBarChromeForVerticalOffset:(CGFloat)rawOffsetY animated:(BOOL)animated {
    SPPlayerService *player = [SPPlayerService shared];
    SPTrack *track = player.currentTrack;
    if (!track) return;

    CGFloat offsetY = MAX(0.0, rawOffsetY);
    CGFloat edgeProgress = MIN(MAX(offsetY / 28.0, 0.0), 1.0);
    self.topBarHairline.alpha = edgeProgress;
    self.scrollTopFadeView.alpha = edgeProgress;

    // 封面与曲目信息滚出视口后平滑淡隐，避免顶栏与滚动卡片出现双层重复标题
    CGFloat coverFade = 1.0 - MIN(MAX((offsetY - 120.0) / 110.0, 0.0), 1.0);
    self.centerCard.coverShadowContainer.alpha = coverFade;
    CGFloat metaFade = 1.0 - MIN(MAX((offsetY - 210.0) / 75.0, 0.0), 1.0);
    self.centerCard.trackMetaStack.alpha = metaFade;
    self.centerCard.likeButton.alpha = metaFade;
    self.centerCard.likeButton.userInteractionEnabled = (metaFade > 0.25);

    BOOL shouldShowTrack = (offsetY > 285.0);
    NSString *targetSub = shouldShowTrack ? (track.artistNames ?: @"") : @"正在播放自";
    NSString *targetTitle = shouldShowTrack ? (track.name ?: @"") : (player.contextTitle ?: track.album.name ?: @"");

    if (shouldShowTrack != self.topBarShowingTrackInfo || ![self.contextTitleLabel.text isEqualToString:targetTitle]) {
        self.topBarShowingTrackInfo = shouldShowTrack;
        if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
            [UIView transitionWithView:self.contextTitleLabel.superview
                              duration:0.18
                               options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                            animations:^{
                self.contextSubLabel.text = targetSub;
                self.contextTitleLabel.text = targetTitle;
            } completion:nil];
        } else {
            self.contextSubLabel.text = targetSub;
            self.contextTitleLabel.text = targetTitle;
        }
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == self.trackPagerScrollView) {
        self.pagerDragStartTrackId = [SPPlayerService shared].currentTrack.identifier;
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.mainScrollView) {
        [self updateTopBarChromeForVerticalOffset:scrollView.contentOffset.y animated:YES];
        return;
    }
    if (scrollView != self.trackPagerScrollView) return;
    if (self.ignorePagerScrollEvents || !self.lastHasAdjacent || self.lastPagerWidth <= 0) return;
    if (!(scrollView.isDragging || scrollView.isDecelerating)) return;

    CGFloat delta = (scrollView.contentOffset.x - self.lastPagerWidth) / self.lastPagerWidth;
    UIColor *base = self.currentThemeColor ?: [UIColor sp_colorWithHex:0x28282D];
    UIColor *morphed = base;
    if (delta > 0 && self.nextThemeColor) {
        morphed = [base sp_interpolatedToColor:self.nextThemeColor fraction:delta];
    } else if (delta < 0 && self.prevThemeColor) {
        morphed = [base sp_interpolatedToColor:self.prevThemeColor fraction:-delta];
    }
    UIColor *darkCanvas = [UIColor sp_colorWithHex:0x121214];
    self.backgroundGradient.colors = @[morphed, [morphed sp_darkenedBy:0.55], darkCanvas];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.trackPagerScrollView) {
        [self finalizeTrackPagerSettle:scrollView];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == self.trackPagerScrollView && !decelerate) {
        [self finalizeTrackPagerSettle:scrollView];
    }
}

- (void)finalizeTrackPagerSettle:(UIScrollView *)scrollView {
    if (!self.lastHasAdjacent || self.lastPagerWidth <= 0) return;
    NSInteger page = (NSInteger)llround(scrollView.contentOffset.x / self.lastPagerWidth);

    if (page == 1) {
        if (self.currentThemeColor) {
            [self applyGradientWithTopColor:self.currentThemeColor animated:YES];
        }
        return;
    }

    SPPlayerService *player = [SPPlayerService shared];
    NSString *currentId = player.currentTrack.identifier;
    if (self.pagerDragStartTrackId.length > 0 && currentId.length > 0 && ![self.pagerDragStartTrackId isEqualToString:currentId]) {
        self.pagerDragStartTrackId = nil;
        self.ignorePagerScrollEvents = YES;
        [scrollView setContentOffset:CGPointMake(self.lastPagerWidth, 0) animated:YES];
        self.ignorePagerScrollEvents = NO;
        if (self.currentThemeColor) {
            [self applyGradientWithTopColor:self.currentThemeColor animated:YES];
        }
        return;
    }
    self.pagerDragStartTrackId = nil;

    BOOL isNext = (page >= 2);
    SPTrack *targetTrack = isNext ? player.nextTrack : player.previousTrack;
    if (!targetTrack) {
        self.ignorePagerScrollEvents = YES;
        [scrollView setContentOffset:CGPointMake(self.lastPagerWidth, 0) animated:YES];
        self.ignorePagerScrollEvents = NO;
        return;
    }

    SPNowPlayingTrackCardView *sourceCard = isNext ? self.nextCard : self.prevCard;
    UIColor *targetColor = isNext ? self.nextThemeColor : self.prevThemeColor;

    self.renderedTrackId = targetTrack.identifier;
    self.centerCard.trackIdentifier = targetTrack.identifier;
    self.centerCard.coverView.image = sourceCard.coverView.image;
    [self.centerCard.coverView sp_syncCurrentURLString:targetTrack.coverURL];
    self.centerCard.trackTitleLabel.text = sourceCard.trackTitleLabel.text;
    self.centerCard.artistLabel.text = sourceCard.artistLabel.text;
    [self.centerCard applyLiked:[[SPLibraryStore shared] isTrackLiked:targetTrack.identifier] animated:NO];
    if (targetColor) {
        self.currentThemeColor = targetColor;
        [self applyGradientWithTopColor:targetColor animated:NO];
    }

    self.ignorePagerScrollEvents = YES;
    [scrollView setContentOffset:CGPointMake(self.lastPagerWidth, 0) animated:NO];
    self.ignorePagerScrollEvents = NO;

    [SPHaptics selection];
    if (isNext) {
        [player next];
    } else {
        [player skipToPreviousTrack];
    }
}

#pragma mark - Actions

- (void)dismissTapped { [SPHaptics light]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)emptyDiscoverTapped {
    [SPHaptics medium];
    void (^handler)(NSInteger) = [self.emptyActionHandler copy];
    [self dismissViewControllerAnimated:YES completion:^{
        if (handler) handler(0);
    }];
}
- (void)emptyLibraryTapped {
    [SPHaptics medium];
    void (^handler)(NSInteger) = [self.emptyActionHandler copy];
    [self dismissViewControllerAnimated:YES completion:^{
        if (handler) handler(2);
    }];
}
- (void)deviceTapped { [SPHaptics light]; [SPToast showMessage:@"当前输出：本机扬声器"]; }

- (void)scrollToLyricsTapped {
    [SPHaptics light];
    CGFloat targetY = MAX(0, CGRectGetMinY(self.lyricsCardView.frame) - 8.0);
    CGFloat maxY = MAX(0, self.mainScrollView.contentSize.height - CGRectGetHeight(self.mainScrollView.bounds));
    [self.mainScrollView setContentOffset:CGPointMake(0, MIN(targetY, maxY)) animated:!UIAccessibilityIsReduceMotionEnabled()];
}

- (void)presentFullScreenLyrics {
    SPTrack *track = [SPPlayerService shared].currentTrack;
    if (!track) return;
    SPFullScreenLyricsViewController *full = [[SPFullScreenLyricsViewController alloc] initWithTrack:track
                                                                                            document:self.lyricsCardView.document
                                                                                          themeColor:self.currentThemeColor
                                                                                     showTranslation:self.lyricsCardView.isShowingTranslation];
    __weak typeof(self) weakSelf = self;
    full.translationDidChangeHandler = ^(BOOL showTranslation) {
        weakSelf.lyricsCardView.showTranslation = showTranslation;
    };
    [self presentViewController:full animated:YES completion:nil];
}

- (void)coverLongPressed:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    if (![SPPlayerService shared].currentTrack) return;
    [SPHaptics medium];
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.12 animations:^{
            self.centerCard.coverShadowContainer.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
                BOOL playing = [SPPlayerService shared].isPlaying;
                self.centerCard.coverShadowContainer.transform = playing ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.92, 0.92);
            } completion:nil];
        }];
    }
    [self presentCoverPreview];
}

- (void)presentCoverPreview {
    SPTrack *track = [SPPlayerService shared].currentTrack;
    if (!track) return;
    SPCoverPreviewViewController *preview = [[SPCoverPreviewViewController alloc] initWithTrack:track
                                                                               placeholderImage:self.coverView.image
                                                                                     themeColor:self.currentThemeColor];
    preview.modalPresentationStyle = UIModalPresentationOverFullScreen;
    preview.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:preview animated:YES completion:nil];
}

- (void)moreTapped {
    [SPHaptics light];
    SPTrack *track = [SPPlayerService shared].currentTrack;
    if (!track) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:track.name
                                                                   message:[track artistNames]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    sheet.view.tintColor = SPTheme.brandGreenColor;

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看高清封面" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf presentCoverPreview];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"全屏实时歌词" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf presentFullScreenLyrics];
    }]];
    BOOL isLiked = [[SPLibraryStore shared] isTrackLiked:track.identifier];
    [sheet addAction:[UIAlertAction actionWithTitle:(isLiked ? @"取消喜欢" : @"喜欢这首歌")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf likeTapped];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"添加到歌单..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SPLibraryActionSheet presentAddTrack:track toPlaylistFrom:weakSelf];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"下一首播放" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[SPPlayerService shared] insertNextTrack:track];
        [SPToast showMessage:@"已添加到下一首播放"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:self.moreButton presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)likeTapped {
    SPTrack *track = [SPPlayerService shared].currentTrack;
    if (!track) return;
    [SPHaptics medium];
    BOOL likedNow = [[SPLibraryStore shared] toggleLikeTrack:track];
    [self syncLikeButtonAnimated:YES];
    [SPToast showMessage:likedNow ? @"已添加到「已点赞的歌曲」" : @"已取消点赞"];
}

- (void)sliderTouchDown {
    [SPHaptics light];
    self.scrubbing = YES;
}

- (void)sliderValueChanged {
    self.currentTimeLabel.text = [SPFormatter timeString:self.progressSlider.value];
}

- (void)sliderTouchUp {
    self.scrubbing = NO;
    [[SPPlayerService shared] seekToTime:self.progressSlider.value];
}

- (void)playPauseTapped { [SPHaptics medium]; [[SPPlayerService shared] togglePlayPause]; }
- (void)prevTapped { [SPHaptics light]; [[SPPlayerService shared] previous]; }
- (void)nextTapped { [SPHaptics light]; [[SPPlayerService shared] next]; }
- (void)shuffleTapped { [SPHaptics selection]; [[SPPlayerService shared] toggleShuffle]; }
- (void)repeatTapped { [SPHaptics selection]; [[SPPlayerService shared] cycleRepeatMode]; }

- (void)queueTapped {
    [SPHaptics light];
    SPQueueViewController *queue = [SPQueueViewController new];
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = queue.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
            sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 24.0;
        }
    }
    [self presentViewController:queue animated:YES completion:nil];
}

#pragma mark - SPPlayerObserver

- (void)playerDidChangeTrack:(SPPlayerService *)player {
    [self reloadTrackAnimated:YES];
    [self reloadProgress];
}

- (void)playerDidChangeQueue:(SPPlayerService *)player {
    [self configureAdjacentCards];
}

- (void)playerDidChangeMode:(SPPlayerService *)player {
    [self reloadModes];
    [self configureAdjacentCards];
}

- (void)playerDidChangeState:(SPPlayerService *)player { [self reloadStateAnimated:YES]; }
- (void)playerDidUpdateProgress:(SPPlayerService *)player { [self reloadProgress]; }

@end
