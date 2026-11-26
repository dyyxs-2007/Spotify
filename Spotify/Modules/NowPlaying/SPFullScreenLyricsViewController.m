//
//  SPFullScreenLyricsViewController.m
//  Spotify
//

#import "SPFullScreenLyricsViewController.h"
#import "SPGradientView.h"
#import "SPScaleButton.h"
#import "SPPlayerService.h"
#import "SPMusicRepository.h"
#import "UIImage+SPDominantColor.h"
#import "SPFormatter.h"
#import "SPHaptics.h"

@interface SPFullLyricLineCell : UITableViewCell
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *lyricLabel;
@property (nonatomic, strong) UILabel *translationLabel;
@property (nonatomic, assign) BOOL activeScale;
@end

@implementation SPFullLyricLineCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _lyricLabel = [UILabel new];
        _lyricLabel.numberOfLines = 0;
        _lyricLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
        _lyricLabel.font = [SPTheme fontOfSize:24 weight:UIFontWeightBold];

        _translationLabel = [UILabel new];
        _translationLabel.numberOfLines = 0;
        _translationLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
        _translationLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightMedium];

        _contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[_lyricLabel, _translationLabel]];
        _contentStack.axis = UILayoutConstraintAxisVertical;
        _contentStack.spacing = 6;
        [self.contentView addSubview:_contentStack];

        [_contentStack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.contentView).offset(12);
            make.bottom.equalTo(self.contentView).offset(-12);
            make.left.equalTo(self.contentView).offset(24);
            make.right.equalTo(self.contentView).offset(-24);
        }];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    UIColor *target = nil;
    (void)target;
    CGFloat alpha = highlighted ? 0.62 : 1.0;
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.12
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self.contentStack.alpha = alpha;
        } completion:nil];
    } else {
        self.contentStack.alpha = alpha;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.contentView layoutIfNeeded];
    [self applyScaleTransform];
}

- (void)applyScaleTransform {
    CGFloat w = CGRectGetWidth(self.contentStack.bounds);
    if (self.activeScale || UIAccessibilityIsReduceMotionEnabled() || w <= 0) {
        self.contentStack.transform = CGAffineTransformIdentity;
        return;
    }
    CGFloat s = 0.92;
    CGFloat tx = -w * (1.0 - s) * 0.5;
    self.contentStack.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(s, s),
                                                          CGAffineTransformMakeTranslation(tx, 0));
}

- (void)configureWithLine:(SPLyricLine *)line
                 isSynced:(BOOL)isSynced
                 isActive:(BOOL)isActive
                   isPast:(BOOL)isPast
          showTranslation:(BOOL)showTranslation
                 animated:(BOOL)animated {
    self.lyricLabel.text = line.text;
    BOOL hasTrans = (showTranslation && line.translation.length > 0);
    self.translationLabel.hidden = !hasTrans;
    self.translationLabel.text = line.translation;

    self.activeScale = (!isSynced || isActive);
    UIColor *lyricColor = nil;
    UIColor *transColor = nil;
    if (!isSynced) {
        lyricColor = [UIColor colorWithWhite:1.0 alpha:0.88];
        transColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    } else if (isActive) {
        lyricColor = UIColor.whiteColor;
        transColor = [UIColor colorWithWhite:1.0 alpha:0.88];
    } else if (isPast) {
        lyricColor = [UIColor colorWithWhite:1.0 alpha:0.36];
        transColor = [UIColor colorWithWhite:1.0 alpha:0.26];
    } else {
        lyricColor = [UIColor colorWithWhite:1.0 alpha:0.58];
        transColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    }

    void (^apply)(void) = ^{
        self.lyricLabel.textColor = lyricColor;
        self.translationLabel.textColor = transColor;
        [self applyScaleTransform];
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.22
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:apply
                         completion:nil];
    } else {
        apply();
    }
}

@end

@interface _SPFullScreenLyricsTransitionAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic, assign) BOOL presenting;
@end

@implementation _SPFullScreenLyricsTransitionAnimator

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext {
    return self.presenting ? 0.34 : 0.24;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIView *container = transitionContext.containerView;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();

    if (self.presenting) {
        UIViewController *toVC = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
        CGRect finalFrame = [transitionContext finalFrameForViewController:toVC];
        toVC.view.frame = finalFrame;
        [container addSubview:toVC.view];
        [toVC.view layoutIfNeeded];

        if (reduceMotion) {
            toVC.view.alpha = 0.0;
            [UIView animateWithDuration:0.18 animations:^{
                toVC.view.alpha = 1.0;
            } completion:^(BOOL finished) {
                [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
            }];
            return;
        }

        toVC.view.transform = CGAffineTransformMakeTranslation(0, CGRectGetHeight(container.bounds));
        [UIView animateWithDuration:[self transitionDuration:transitionContext]
                              delay:0
             usingSpringWithDamping:0.92
              initialSpringVelocity:0.15
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            toVC.view.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
        }];
    } else {
        UIViewController *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
        if (reduceMotion) {
            [UIView animateWithDuration:0.16 animations:^{
                fromVC.view.alpha = 0.0;
            } completion:^(BOOL finished) {
                fromVC.view.transform = CGAffineTransformIdentity;
                fromVC.view.layer.cornerRadius = 0.0;
                fromVC.view.clipsToBounds = NO;
                [fromVC.view removeFromSuperview];
                [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
            }];
            return;
        }

        CGFloat height = MAX(CGRectGetHeight(container.bounds), 600.0);
        CGAffineTransform endTransform = CGAffineTransformMakeTranslation(0, height * 0.42);
        [UIView animateWithDuration:[self transitionDuration:transitionContext]
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            fromVC.view.transform = endTransform;
            fromVC.view.alpha = 0.0;
        } completion:^(BOOL finished) {
            fromVC.view.transform = CGAffineTransformIdentity;
            fromVC.view.layer.cornerRadius = 0.0;
            fromVC.view.clipsToBounds = NO;
            [fromVC.view removeFromSuperview];
            [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
        }];
    }
}

@end

@interface SPFullScreenLyricsViewController () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate, SPPlayerObserver, UIViewControllerTransitioningDelegate>
@property (nonatomic, strong, nullable) SPTrack *track;
@property (nonatomic, strong, nullable) SPLyricDocument *document;
@property (nonatomic, strong) UIColor *themeColor;
@property (nonatomic, assign) BOOL showTranslation;

@property (nonatomic, strong) SPGradientView *backgroundGradient;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIImageView *miniCoverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) SPScaleButton *translationButton;
@property (nonatomic, strong) UIView *tableContainer;
@property (nonatomic, strong) CAGradientLayer *fadeMaskLayer;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) SPProgressSlider *progressSlider;
@property (nonatomic, strong) UILabel *currentTimeLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) SPScaleButton *playPauseButton;
@property (nonatomic, strong) UIPanGestureRecognizer *dismissPan;

@property (nonatomic, assign) NSInteger activeLineIndex;
@property (nonatomic, assign) CFTimeInterval pauseAutoScrollUntil;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) NSUInteger lyricRequestToken;
@end

@implementation SPFullScreenLyricsViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (instancetype)initWithTrack:(SPTrack *)track
                     document:(nullable SPLyricDocument *)document
                   themeColor:(nullable UIColor *)themeColor
              showTranslation:(BOOL)showTranslation {
    if (self = [super init]) {
        _track = track;
        _document = document;
        _themeColor = themeColor ?: [UIColor sp_colorWithHex:0x23262E];
        _showTranslation = showTranslation;
        _activeLineIndex = -1;
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.transitioningDelegate = self;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source {
    _SPFullScreenLyricsTransitionAnimator *anim = [_SPFullScreenLyricsTransitionAnimator new];
    anim.presenting = YES;
    return anim;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    _SPFullScreenLyricsTransitionAnimator *anim = [_SPFullScreenLyricsTransitionAnimator new];
    anim.presenting = NO;
    return anim;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor sp_colorWithHex:0x101114];
    [self setupViews];
    [self setupDismissGesture];
    [[SPPlayerService shared] addObserver:self];
    [self syncWithCurrentPlayerAnimated:NO];
    if (!self.document) {
        [self loadLyricsForTrack:self.track];
    } else {
        [self applyDocument:self.document];
    }
}

- (void)setupViews {
    _backgroundGradient = [SPGradientView new];
    [self applyGradientAnimated:NO];
    [self.view addSubview:_backgroundGradient];

    UIView *grabber = [UIView new];
    grabber.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.26];
    grabber.layer.cornerRadius = 2.0;
    grabber.layer.cornerCurve = kCACornerCurveContinuous;
    grabber.userInteractionEnabled = NO;
    [self.view addSubview:grabber];

    _topBar = [UIView new];
    [self.view addSubview:_topBar];
    UIView *topBar = _topBar;

    _miniCoverView = [UIImageView new];
    _miniCoverView.contentMode = UIViewContentModeScaleAspectFill;
    _miniCoverView.clipsToBounds = YES;
    _miniCoverView.layer.cornerRadius = 6;
    [topBar addSubview:_miniCoverView];

    _titleLabel = [UILabel new];
    _titleLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightBold];
    _titleLabel.textColor = UIColor.whiteColor;

    _artistLabel = [UILabel new];
    _artistLabel.font = [SPTheme fontOfSize:12.5 weight:UIFontWeightRegular];
    _artistLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];

    UIStackView *metaStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _artistLabel]];
    metaStack.axis = UILayoutConstraintAxisVertical;
    metaStack.spacing = 2;
    [topBar addSubview:metaStack];

    UIButtonConfiguration *transCfg = [UIButtonConfiguration plainButtonConfiguration];
    transCfg.contentInsets = NSDirectionalEdgeInsetsMake(0, 9, 0, 9);
    transCfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [SPTheme fontOfSize:12 weight:UIFontWeightBold];
        return attrs;
    };
    _translationButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _translationButton.configuration = transCfg;
    [_translationButton setTitle:@"译" forState:UIControlStateNormal];
    _translationButton.layer.cornerRadius = 13;
    _translationButton.layer.cornerCurve = kCACornerCurveContinuous;
    [_translationButton addTarget:self action:@selector(translationTapped) forControlEvents:UIControlEventTouchUpInside];

    SPScaleButton *closeBtn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [closeBtn sp_setSymbol:@"xmark" size:15 weight:UIImageSymbolWeightBold animated:NO];
    closeBtn.tintColor = UIColor.whiteColor;
    closeBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
    closeBtn.layer.cornerRadius = 17;
    closeBtn.layer.cornerCurve = kCACornerCurveCircular;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *topRight = [[UIStackView alloc] initWithArrangedSubviews:@[_translationButton, closeBtn]];
    topRight.axis = UILayoutConstraintAxisHorizontal;
    topRight.spacing = 12;
    topRight.alignment = UIStackViewAlignmentCenter;
    [topBar addSubview:topRight];

    _tableContainer = [UIView new];
    _tableContainer.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_tableContainer];

    _fadeMaskLayer = [CAGradientLayer layer];
    _fadeMaskLayer.colors = @[
        (__bridge id)[UIColor colorWithWhite:0 alpha:0.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0 alpha:0.0].CGColor,
    ];
    _fadeMaskLayer.locations = @[@0.0, @0.07, @0.88, @1.0];
    _tableContainer.layer.mask = _fadeMaskLayer;

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60;
    _tableView.contentInset = UIEdgeInsetsMake(28, 0, 52, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPFullLyricLineCell.class forCellReuseIdentifier:[SPFullLyricLineCell reuseId]];
    [_tableContainer addSubview:_tableView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.color = UIColor.whiteColor;
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    _emptyLabel = [UILabel new];
    _emptyLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightSemibold];
    _emptyLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    UIView *bottomDock = [UIView new];
    [self.view addSubview:bottomDock];

    _progressSlider = [SPProgressSlider new];
    _progressSlider.minimumTrackTintColor = UIColor.whiteColor;
    _progressSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    [_progressSlider setThumbImage:[self circleThumbWithDiameter:10] forState:UIControlStateNormal];
    [_progressSlider setThumbImage:[self circleThumbWithDiameter:14] forState:UIControlStateHighlighted];
    [_progressSlider addTarget:self action:@selector(sliderDown) forControlEvents:UIControlEventTouchDown];
    [_progressSlider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [_progressSlider addTarget:self action:@selector(sliderUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [bottomDock addSubview:_progressSlider];

    _currentTimeLabel = [UILabel new];
    _currentTimeLabel.font = [SPTheme monospacedDigitFontOfSize:11.5 weight:UIFontWeightRegular];
    _currentTimeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];

    _durationLabel = [UILabel new];
    _durationLabel.font = [SPTheme monospacedDigitFontOfSize:11.5 weight:UIFontWeightRegular];
    _durationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    _durationLabel.textAlignment = NSTextAlignmentRight;
    [bottomDock addSubview:_currentTimeLabel];
    [bottomDock addSubview:_durationLabel];

    SPScaleButton *prevBtn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [prevBtn sp_setSymbol:@"backward.end.fill" size:24 weight:UIImageSymbolWeightRegular animated:NO];
    prevBtn.tintColor = UIColor.whiteColor;
    [prevBtn addTarget:self action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];

    _playPauseButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _playPauseButton.backgroundColor = UIColor.whiteColor;
    _playPauseButton.tintColor = UIColor.blackColor;
    _playPauseButton.layer.cornerRadius = 27;
    [_playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];

    SPScaleButton *nextBtn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [nextBtn sp_setSymbol:@"forward.end.fill" size:24 weight:UIImageSymbolWeightRegular animated:NO];
    nextBtn.tintColor = UIColor.whiteColor;
    [nextBtn addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *controlsRow = [[UIStackView alloc] initWithArrangedSubviews:@[prevBtn, _playPauseButton, nextBtn]];
    controlsRow.axis = UILayoutConstraintAxisHorizontal;
    controlsRow.spacing = 36;
    controlsRow.alignment = UIStackViewAlignmentCenter;
    [bottomDock addSubview:controlsRow];

    [_backgroundGradient mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [grabber mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(3);
        make.centerX.equalTo(self.view);
        make.size.mas_equalTo(CGSizeMake(36, 4));
    }];
    [topBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(10);
        make.left.right.equalTo(self.view);
        make.height.mas_equalTo(52);
    }];
    [_miniCoverView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(topBar).offset(20);
        make.centerY.equalTo(topBar);
        make.size.mas_equalTo(CGSizeMake(38, 38));
    }];
    [metaStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.miniCoverView.mas_right).offset(12);
        make.right.lessThanOrEqualTo(topRight.mas_left).offset(-12);
        make.centerY.equalTo(topBar);
    }];
    [_translationButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(26);
        make.width.mas_greaterThanOrEqualTo(32);
    }];
    [closeBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(34, 34));
    }];
    [topRight mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(topBar).offset(-20);
        make.centerY.equalTo(topBar);
    }];

    [bottomDock mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.view).offset(24);
        make.right.equalTo(self.view).offset(-24);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideBottom).offset(-12);
    }];
    [_progressSlider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(bottomDock);
    }];
    [_currentTimeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.progressSlider.mas_bottom).offset(4);
        make.left.equalTo(self.progressSlider);
    }];
    [_durationLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.currentTimeLabel);
        make.right.equalTo(self.progressSlider);
    }];
    [prevBtn mas_makeConstraints:^(MASConstraintMaker *make) { make.size.mas_equalTo(CGSizeMake(44, 44)); }];
    [_playPauseButton mas_makeConstraints:^(MASConstraintMaker *make) { make.size.mas_equalTo(CGSizeMake(54, 54)); }];
    [nextBtn mas_makeConstraints:^(MASConstraintMaker *make) { make.size.mas_equalTo(CGSizeMake(44, 44)); }];
    [controlsRow mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.currentTimeLabel.mas_bottom).offset(10);
        make.centerX.equalTo(bottomDock);
        make.bottom.equalTo(bottomDock);
    }];

    [_tableContainer mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(topBar.mas_bottom).offset(4);
        make.left.right.equalTo(self.view);
        make.bottom.equalTo(bottomDock.mas_top).offset(-8);
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.tableContainer);
    }];
    [_spinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableContainer);
    }];
    [_emptyLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableContainer);
        make.left.equalTo(self.view).offset(24);
        make.right.equalTo(self.view).offset(-24);
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.fadeMaskLayer.frame = self.tableContainer.bounds;
    [CATransaction commit];
}

- (UIImage *)circleThumbWithDiameter:(CGFloat)diameter {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(diameter, diameter)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.whiteColor setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, diameter, diameter)] fill];
    }];
}

- (void)applyGradientAnimated:(BOOL)animated {
    UIColor *top = [self.themeColor sp_clampedForDarkBackground];
    [self.backgroundGradient setColors:@[top, [top sp_darkenedBy:0.55], [UIColor sp_colorWithHex:0x0E0E11]] animated:animated];
}

- (void)syncWithCurrentPlayerAnimated:(BOOL)animated {
    SPPlayerService *player = [SPPlayerService shared];
    SPTrack *track = player.currentTrack ?: self.track;
    self.track = track;
    self.titleLabel.text = track.name ?: @"";
    self.artistLabel.text = [track artistNames];

    __weak typeof(self) weakSelf = self;
    NSString *trackId = track.identifier;
    [self.miniCoverView sp_setCoverWithItem:track dominantColorCompletion:^(UIColor *color) {
        if (![weakSelf.track.identifier isEqualToString:trackId]) return;
        weakSelf.themeColor = color;
        [weakSelf applyGradientAnimated:YES];
    }];

    [self reloadStateAnimated:animated];
    [self reloadProgress];
}

- (void)loadLyricsForTrack:(nullable SPTrack *)track {
    if (!track) return;
    self.lyricRequestToken += 1;
    NSUInteger token = self.lyricRequestToken;
    self.document = nil;
    self.activeLineIndex = -1;
    self.emptyLabel.hidden = YES;
    self.translationButton.hidden = YES;
    [self.spinner startAnimating];
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    [[SPMusicRepository shared] fetchLyricsForTrack:track completion:^(SPLyricDocument *lyrics, NSError *error) {
        if (!weakSelf || weakSelf.lyricRequestToken != token) return;
        [weakSelf.spinner stopAnimating];
        [weakSelf applyDocument:lyrics];
    }];
}

- (void)applyDocument:(nullable SPLyricDocument *)document {
    self.document = document;
    self.activeLineIndex = -1;
    self.translationButton.hidden = !document.hasTranslation;
    [self updateTranslationButtonAppearance];
    if (!document || document.lines.count == 0) {
        self.emptyLabel.hidden = NO;
        self.emptyLabel.text = document.isInstrumental ? @"纯音乐，请尽情欣赏" : @"这首歌暂未收录歌词";
    } else {
        self.emptyLabel.hidden = YES;
    }
    [self.tableView reloadData];
    [self syncActiveLineAnimated:NO];
}

- (void)updateTranslationButtonAppearance {
    UIButtonConfiguration *cfg = [self.translationButton.configuration copy];
    cfg.baseForegroundColor = self.showTranslation ? [UIColor sp_colorWithHex:0x111214] : [UIColor colorWithWhite:1.0 alpha:0.85];
    self.translationButton.configuration = cfg;
    self.translationButton.backgroundColor = self.showTranslation
        ? [UIColor colorWithWhite:1.0 alpha:0.92]
        : [UIColor colorWithWhite:1.0 alpha:0.14];
}

- (void)reloadStateAnimated:(BOOL)animated {
    BOOL playing = [SPPlayerService shared].isPlaying;
    self.playPauseButton.opticalHorizontalOffset = playing ? 0.0 : 2.0;
    [self.playPauseButton sp_setSymbol:(playing ? @"pause.fill" : @"play.fill") size:21 weight:UIImageSymbolWeightBold animated:animated];
}

- (void)reloadProgress {
    SPPlayerService *player = [SPPlayerService shared];
    if (!self.scrubbing) {
        NSTimeInterval dur = MAX(player.duration, 1);
        self.progressSlider.maximumValue = (float)dur;
        self.progressSlider.value = (float)MIN(player.currentTime, dur);
        self.currentTimeLabel.text = [SPFormatter timeString:player.currentTime];
        self.durationLabel.text = [SPFormatter timeString:player.duration];
    }
    [self syncActiveLineAnimated:YES];
}

- (void)syncActiveLineAnimated:(BOOL)animated {
    if (!self.document.isSynced || self.document.lines.count == 0) return;
    NSInteger idx = [self.document activeLineIndexForTime:[SPPlayerService shared].currentTime];
    if (idx == self.activeLineIndex) return;
    self.activeLineIndex = idx;

    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        SPFullLyricLineCell *cell = [self.tableView cellForRowAtIndexPath:ip];
        if (![cell isKindOfClass:SPFullLyricLineCell.class]) continue;
        [cell configureWithLine:self.document.lines[ip.row]
                       isSynced:YES
                       isActive:(ip.row == idx)
                         isPast:(idx >= 0 && ip.row < idx)
                showTranslation:self.showTranslation
                       animated:animated];
    }
    if (idx >= 0 && idx < (NSInteger)self.document.lines.count &&
        CFAbsoluteTimeGetCurrent() >= self.pauseAutoScrollUntil) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0]
                              atScrollPosition:UITableViewScrollPositionMiddle
                                      animated:(animated && !UIAccessibilityIsReduceMotionEnabled())];
    }
}

#pragma mark - Actions

- (void)setupDismissGesture {
    _dismissPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissPan:)];
    _dismissPan.delegate = self;
    [self.view addGestureRecognizer:_dismissPan];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.dismissPan) return YES;
    UIView *sliderHost = self.progressSlider.superview;
    if (sliderHost) {
        CGPoint loc = [gestureRecognizer locationInView:sliderHost];
        if (CGRectContainsPoint(CGRectInset(self.progressSlider.frame, -16, -18), loc)) {
            return NO;
        }
    }
    CGPoint v = [self.dismissPan velocityInView:self.view];
    if (!(v.y > 0 && fabs(v.y) > fabs(v.x))) return NO;

    CGPoint topLoc = [gestureRecognizer locationInView:self.view];
    if (CGRectContainsPoint(CGRectInset(self.topBar.frame, 0, -14), topLoc)) return YES;
    return (self.tableView.contentOffset.y <= -self.tableView.adjustedContentInset.top + 4.0);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.dismissPan && otherGestureRecognizer == self.tableView.panGestureRecognizer) {
        return YES;
    }
    return NO;
}

- (void)handleDismissPan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.view];
    CGPoint v = [pan velocityInView:self.view];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();

    if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat dy = MAX(t.y, 0);
        CGFloat progress = MIN(dy / 280.0, 1.0);
        CGFloat eased = 1.0 - pow(1.0 - progress, 1.5);
        self.view.clipsToBounds = YES;
        self.view.layer.cornerCurve = kCACornerCurveContinuous;
        self.view.layer.cornerRadius = reduceMotion ? 0.0 : (16.0 + 22.0 * eased);
        self.view.alpha = 1.0;
        if (!reduceMotion) {
            CGFloat scale = 1.0 - 0.055 * eased;
            self.view.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale),
                                                          CGAffineTransformMakeTranslation(0, dy * 0.85));
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (t.y > 105 || v.y > 700) {
            [SPHaptics light];
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            [UIView animateWithDuration:reduceMotion ? 0.16 : 0.32
                                  delay:0
                 usingSpringWithDamping:reduceMotion ? 1.0 : 0.88
                  initialSpringVelocity:reduceMotion ? 0.0 : 0.2
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                self.view.transform = CGAffineTransformIdentity;
                self.view.layer.cornerRadius = 0.0;
                self.view.alpha = 1.0;
            } completion:^(BOOL finished) {
                if (CGAffineTransformIsIdentity(self.view.transform)) {
                    self.view.clipsToBounds = NO;
                }
            }];
        }
    }
}

- (void)closeTapped { [SPHaptics light]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)playPauseTapped { [SPHaptics medium]; [[SPPlayerService shared] togglePlayPause]; }
- (void)prevTapped { [SPHaptics light]; [[SPPlayerService shared] previous]; }
- (void)nextTapped { [SPHaptics light]; [[SPPlayerService shared] next]; }
- (void)sliderDown { [SPHaptics light]; self.scrubbing = YES; }
- (void)sliderChanged { self.currentTimeLabel.text = [SPFormatter timeString:self.progressSlider.value]; }
- (void)sliderUp { self.scrubbing = NO; [[SPPlayerService shared] seekToTime:self.progressSlider.value]; }

- (void)translationTapped {
    [SPHaptics selection];
    self.showTranslation = !self.showTranslation;
    [self updateTranslationButtonAppearance];
    [self.tableView reloadData];
    if (self.activeLineIndex >= 0 && self.activeLineIndex < (NSInteger)self.document.lines.count) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.activeLineIndex inSection:0]
                              atScrollPosition:UITableViewScrollPositionMiddle
                                      animated:NO];
    }
    if (self.translationDidChangeHandler) {
        self.translationDidChangeHandler(self.showTranslation);
    }
}

#pragma mark - SPPlayerObserver

- (void)playerDidChangeTrack:(SPPlayerService *)player {
    [self syncWithCurrentPlayerAnimated:YES];
    [self loadLyricsForTrack:player.currentTrack];
}

- (void)playerDidChangeState:(SPPlayerService *)player { [self reloadStateAnimated:YES]; }
- (void)playerDidUpdateProgress:(SPPlayerService *)player { [self reloadProgress]; }

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.document.lines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPFullLyricLineCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPFullLyricLineCell reuseId] forIndexPath:indexPath];
    [cell configureWithLine:self.document.lines[indexPath.row]
                   isSynced:self.document.isSynced
                   isActive:(indexPath.row == self.activeLineIndex)
                     isPast:(self.activeLineIndex >= 0 && indexPath.row < self.activeLineIndex)
            showTranslation:self.showTranslation
                   animated:NO];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.document.isSynced || indexPath.row >= (NSInteger)self.document.lines.count) return;
    [SPHaptics selection];
    self.pauseAutoScrollUntil = 0;
    SPLyricLine *line = self.document.lines[indexPath.row];
    [[SPPlayerService shared] seekToTime:line.time];
    if (![SPPlayerService shared].isPlaying) [[SPPlayerService shared] play];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.pauseAutoScrollUntil = CFAbsoluteTimeGetCurrent() + 4.0;
}

@end
