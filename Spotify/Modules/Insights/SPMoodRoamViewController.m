//
//  SPMoodRoamViewController.m
//  Spotify
//

#import "SPMoodRoamViewController.h"
#import "SPGradientView.h"
#import "SPScaleButton.h"
#import "SPMediaCells.h"
#import "SPAuthService.h"
#import "SPMusicRepository.h"
#import "SPLibraryStore.h"
#import "SPLibraryActionSheet.h"
#import "SPPlayerService.h"
#import "SPPlaylist.h"
#import "SPAlbum.h"
#import "SPHaptics.h"
#import "SPToast.h"

#pragma mark - Station Model

@interface SPMoodStation : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *tagline;
@property (nonatomic, assign) CGFloat frequencyMHz;
@property (nonatomic, copy) NSArray<NSString *> *keywords;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, strong) UIColor *lightTextAccentColor;
@property (nonatomic, copy) NSString *symbolName;
@end

@implementation SPMoodStation
@end

#pragma mark - Precision Analog Frequency Scale View

@interface SPFrequencyDialView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSArray<SPMoodStation *> *stations;
@property (nonatomic, assign) CGFloat currentFrequency;
@property (nonatomic, strong) UIColor *needleColor;
@property (nonatomic, copy, nullable) void (^stationScrubbedHandler)(NSInteger stationIndex);

@property (nonatomic, strong) UIView *scaleStripView;
@property (nonatomic, strong) CAShapeLayer *ticksLayer;
@property (nonatomic, strong) UIView *centerNeedle;
@property (nonatomic, strong) UIView *needleGlowDot;
@property (nonatomic, strong) CAGradientLayer *edgeMaskLayer;
@property (nonatomic, assign) CGFloat panStartFrequency;
@end

@implementation SPFrequencyDialView

static const CGFloat SPDialMinFreq = 88.0;
static const CGFloat SPDialMaxFreq = 112.0;
static const CGFloat SPDialPixelsPerMHz = 36.0;

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.clipsToBounds = YES;
        self.backgroundColor = SPTheme.highlightColor;
        self.layer.cornerRadius = 12;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _needleColor = SPTheme.accentColor;
        _currentFrequency = 92.4;

        _scaleStripView = [UIView new];
        _scaleStripView.userInteractionEnabled = NO;
        [self addSubview:_scaleStripView];

        _ticksLayer = [CAShapeLayer layer];
        _ticksLayer.fillColor = UIColor.clearColor.CGColor;
        _ticksLayer.lineWidth = 1.2;
        _ticksLayer.lineCap = kCALineCapRound;
        [_scaleStripView.layer addSublayer:_ticksLayer];

        _centerNeedle = [UIView new];
        _centerNeedle.layer.cornerRadius = 1.25;
        _centerNeedle.userInteractionEnabled = NO;
        [self addSubview:_centerNeedle];

        _needleGlowDot = [UIView new];
        _needleGlowDot.layer.cornerRadius = 3.5;
        _needleGlowDot.userInteractionEnabled = NO;
        [self addSubview:_needleGlowDot];

        _edgeMaskLayer = [CAGradientLayer layer];
        _edgeMaskLayer.startPoint = CGPointMake(0.0, 0.5);
        _edgeMaskLayer.endPoint = CGPointMake(1.0, 0.5);
        _edgeMaskLayer.colors = @[
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor,
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor,
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
        ];
        _edgeMaskLayer.locations = @[@0.0, @0.10, @0.90, @1.0];
        _scaleStripView.layer.mask = _edgeMaskLayer;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self;
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];

        [self rebuildScaleTicks];
        [self updateColors];
    }
    return self;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class]) {
        CGPoint v = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
        return fabs(v.x) >= fabs(v.y) * 0.7;
    }
    return YES;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateColors];
    }
}

- (void)updateColors {
    UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self];
    BOOL isLight = (tc.userInterfaceStyle == UIUserInterfaceStyleLight);
    UIColor *tickColor = isLight ? [UIColor colorWithWhite:0.0 alpha:0.26] : [UIColor colorWithWhite:1.0 alpha:0.32];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.ticksLayer.strokeColor = tickColor.CGColor;
    [CATransaction commit];

    UIColor *resolvedNeedle = [self.needleColor resolvedColorWithTraitCollection:tc];
    self.centerNeedle.backgroundColor = resolvedNeedle;
    self.needleGlowDot.backgroundColor = resolvedNeedle;
    self.centerNeedle.layer.shadowColor = resolvedNeedle.CGColor;
    self.centerNeedle.layer.shadowOpacity = isLight ? 0.35 : 0.55;
    self.centerNeedle.layer.shadowRadius = 6.0;
    self.centerNeedle.layer.shadowOffset = CGSizeZero;
}

- (void)rebuildScaleTicks {
    for (UIView *sub in self.scaleStripView.subviews) [sub removeFromSuperview];

    CGFloat stripWidth = (SPDialMaxFreq - SPDialMinFreq) * SPDialPixelsPerMHz + 400.0;
    CGFloat stripHeight = 56.0;
    self.scaleStripView.bounds = CGRectMake(0, 0, stripWidth, stripHeight);

    UIBezierPath *path = [UIBezierPath bezierPath];
    NSInteger totalSteps = (NSInteger)llround((SPDialMaxFreq - SPDialMinFreq) * 5.0); // 每 0.2 MHz 一格
    for (NSInteger step = 0; step <= totalSteps; step++) {
        CGFloat freq = SPDialMinFreq + step * 0.2;
        CGFloat x = 200.0 + (freq - SPDialMinFreq) * SPDialPixelsPerMHz;
        BOOL isMajor = (step % 10 == 0); // 每 2.0 MHz 主刻度
        BOOL isMid = (step % 5 == 0);    // 每 1.0 MHz 中刻度
        CGFloat tickH = isMajor ? 18.0 : (isMid ? 12.0 : 7.0);
        CGFloat yTop = (stripHeight - tickH) * 0.5 - 5.0;
        [path moveToPoint:CGPointMake(x, yTop)];
        [path addLineToPoint:CGPointMake(x, yTop + tickH)];

        if (isMajor) {
            UILabel *lbl = [UILabel new];
            lbl.text = [NSString stringWithFormat:@"%.0f", freq];
            lbl.font = [SPTheme monospacedDigitFontOfSize:9.5 weight:UIFontWeightSemibold];
            lbl.textColor = SPTheme.textTertiaryColor;
            [lbl sizeToFit];
            lbl.center = CGPointMake(x, stripHeight - 10.0);
            [self.scaleStripView addSubview:lbl];
        }
    }
    self.ticksLayer.path = path.CGPath;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    if (w <= 0 || h <= 0) return;

    self.centerNeedle.frame = CGRectMake((w - 2.5) * 0.5, 6.0, 2.5, h - 12.0);
    self.needleGlowDot.frame = CGRectMake((w - 7.0) * 0.5, 4.0, 7.0, 7.0);
    [self positionStripForFrequency:self.currentFrequency];
}

- (void)positionStripForFrequency:(CGFloat)freq {
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    if (w <= 0) return;
    CGFloat targetTickX = 200.0 + (freq - SPDialMinFreq) * SPDialPixelsPerMHz;
    CGFloat originX = w * 0.5 - targetTickX;
    self.scaleStripView.frame = CGRectMake(originX, 0, CGRectGetWidth(self.scaleStripView.bounds), h);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.edgeMaskLayer.frame = CGRectMake(-originX, 0, w, h);
    [CATransaction commit];
}

- (void)setFrequency:(CGFloat)frequency accentColor:(UIColor *)accent animated:(BOOL)animated {
    self.currentFrequency = frequency;
    self.needleColor = accent ?: SPTheme.brandGreenColor;
    [self updateColors];
    if (animated && !UIAccessibilityIsReduceMotionEnabled() && CGRectGetWidth(self.bounds) > 0) {
        [UIView animateWithDuration:0.36
                              delay:0
             usingSpringWithDamping:0.86
              initialSpringVelocity:0.2
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            [self positionStripForFrequency:frequency];
        } completion:nil];
    } else {
        [self positionStripForFrequency:frequency];
    }
}

- (NSInteger)nearestStationIndexForFrequency:(CGFloat)freq {
    NSInteger best = 0;
    CGFloat minDiff = CGFLOAT_MAX;
    for (NSInteger i = 0; i < (NSInteger)self.stations.count; i++) {
        CGFloat d = fabs(self.stations[i].frequencyMHz - freq);
        if (d < minDiff) {
            minDiff = d;
            best = i;
        }
    }
    return best;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (self.stations.count == 0) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.panStartFrequency = self.currentFrequency;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = [pan translationInView:self].x;
        CGFloat rawFreq = self.panStartFrequency - dx / SPDialPixelsPerMHz;
        rawFreq = MIN(MAX(rawFreq, 90.0), 110.0);
        self.currentFrequency = rawFreq;
        [self positionStripForFrequency:rawFreq];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        NSInteger snapped = [self nearestStationIndexForFrequency:self.currentFrequency];
        [SPHaptics selection];
        SPMoodStation *st = self.stations[snapped];
        [self setFrequency:st.frequencyMHz accentColor:st.accentColor animated:YES];
        if (self.stationScrubbedHandler) self.stationScrubbedHandler(snapped);
    }
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.stations.count == 0) return;
    CGFloat locX = [tap locationInView:self].x;
    CGFloat deltaX = locX - CGRectGetWidth(self.bounds) * 0.5;
    CGFloat tappedFreq = self.currentFrequency + deltaX / SPDialPixelsPerMHz;
    NSInteger snapped = [self nearestStationIndexForFrequency:tappedFreq];
    [SPHaptics selection];
    SPMoodStation *st = self.stations[snapped];
    [self setFrequency:st.frequencyMHz accentColor:st.accentColor animated:YES];
    if (self.stationScrubbedHandler) self.stationScrubbedHandler(snapped);
}

@end

#pragma mark - SPMoodRoamViewController

@interface SPMoodRoamViewController () <UITableViewDataSource, UITableViewDelegate, SPPlayerObserver, SPAuthObserver>
@property (nonatomic, copy) NSArray<SPMoodStation *> *stations;
@property (nonatomic, assign, readwrite) NSInteger selectedStationIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<SPTrack *> *> *stationTracksCache;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *stationKeywordCursor;
@property (nonatomic, copy) NSArray<SPTrack *> *currentTracks;
@property (nonatomic, assign) NSUInteger fetchToken;

@property (nonatomic, strong) SPGradientView *ambientGradient;
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UIView *navDivider;
@property (nonatomic, strong) UIView *onAirDot;
@property (nonatomic, strong) UILabel *onAirLabel;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *tunerCard;
@property (nonatomic, strong) UILabel *freqNumberLabel;
@property (nonatomic, strong) UILabel *stationTitleLabel;
@property (nonatomic, strong) UILabel *stationTaglineLabel;
@property (nonatomic, strong) SPFrequencyDialView *dialView;
@property (nonatomic, strong) UIView *chipClipHost;
@property (nonatomic, strong) CAGradientLayer *chipEdgeMaskLayer;
@property (nonatomic, copy) NSArray<SPScaleButton *> *stationChipButtons;

@property (nonatomic, strong) UIView *showcaseBox;
@property (nonatomic, strong) UIImageView *showcaseCover;
@property (nonatomic, strong) UILabel *showcaseTitleLabel;
@property (nonatomic, strong) UILabel *showcaseArtistLabel;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, strong) SPScaleButton *roamPlayButton;
@property (nonatomic, strong) SPScaleButton *shuffleBatchButton;
@end

@implementation SPMoodRoamViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (NSUInteger)currentTrackCount { return self.currentTracks.count; }

- (void)dealloc {
    [[SPAuthService shared] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    self.stations = [self buildCuratedStations];
    self.stationTracksCache = [NSMutableDictionary dictionary];
    self.stationKeywordCursor = [NSMutableDictionary dictionary];
    self.currentTracks = @[];

    [self setupViews];
    [[SPPlayerService shared] addObserver:self];
    [[SPAuthService shared] addObserver:self];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(themeDidChange) name:SPThemeDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(musicSourceDidChange) name:SPMusicSourceDidChangeNotification object:nil];

    [self selectStationAtIndex:0 autoPlay:NO];
}

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    [self syncVisibleTrackRows];
}

- (void)musicSourceDidChange {
    [self.stationTracksCache removeAllObjects];
    [self.stationKeywordCursor removeAllObjects];
    self.currentTracks = @[];
    [self.tableView reloadData];
    [self selectStationAtIndex:self.selectedStationIndex autoPlay:NO];
}

- (NSArray<SPMoodStation *> *)buildCuratedStations {
    NSArray<NSDictionary *> *specs = @[
        @{@"name": @"深夜独处", @"freq": @92.4, @"symbol": @"moon.stars.fill", @"hex": @0x6366F1, @"lightHex": @0x4338CA,
          @"tag": @"静谧民谣与温柔人声，陪你潜入安静夜色",
          @"kw": @[@"民谣 温柔", @"独立 抒情", @"安静 夜晚"]},
        @{@"name": @"专注心流", @"freq": @96.8, @"symbol": @"sparkles", @"hex": @0x10B981, @"lightHex": @0x047857,
          @"tag": @"纯净器乐与轻柔钢琴，过滤外界纷扰",
          @"kw": @[@"纯音乐 钢琴", @"轻音乐 治愈", @"古典 弦乐"]},
        @{@"name": @"落日兜风", @"freq": @101.2, @"symbol": @"sun.haze.fill", @"hex": @0xF59B23, @"lightHex": @0xB45309,
          @"tag": @"松弛律动与都市流行，迎着晚风出发",
          @"kw": @[@"流行 律动", @"华语 精选", @"R&B 浪漫"]},
        @{@"name": @"雨夜爵士", @"freq": @104.6, @"symbol": @"cloud.drizzle.fill", @"hex": @0xEC4899, @"lightHex": @0xBE185D,
          @"tag": @"慵懒萨克斯与复古蓝调，微醺松弛时刻",
          @"kw": @[@"爵士 蓝调", @"复古 慵懒", @"灵魂乐 经典"]},
        @{@"name": @"元气律动", @"freq": @108.0, @"symbol": @"bolt.heart.fill", @"hex": @0x1ED760, @"lightHex": @0x15803D,
          @"tag": @"鲜活节拍与摇滚电音，瞬间唤醒多巴胺",
          @"kw": @[@"摇滚 乐队", @"电子 节奏", @"运动 活力"]},
    ];
    NSMutableArray<SPMoodStation *> *arr = [NSMutableArray arrayWithCapacity:specs.count];
    for (NSDictionary *d in specs) {
        SPMoodStation *s = [SPMoodStation new];
        s.name = d[@"name"];
        s.frequencyMHz = [d[@"freq"] doubleValue];
        s.symbolName = d[@"symbol"];
        s.accentColor = [UIColor sp_colorWithHex:(uint32_t)[d[@"hex"] unsignedIntValue]];
        s.lightTextAccentColor = [UIColor sp_colorWithHex:(uint32_t)[d[@"lightHex"] unsignedIntValue]];
        s.tagline = d[@"tag"];
        s.keywords = d[@"kw"];
        [arr addObject:s];
    }
    return arr;
}

- (UIColor *)displayAccentForStation:(SPMoodStation *)station traitCollection:(UITraitCollection *)tc {
    BOOL isLight = (tc.userInterfaceStyle == UIUserInterfaceStyleLight);
    return isLight ? (station.lightTextAccentColor ?: station.accentColor) : station.accentColor;
}

#pragma mark - UI Construction

- (void)setupViews {
    _ambientGradient = [SPGradientView new];
    [self.view addSubview:_ambientGradient];

    _navBar = [UIView new];
    [self.view addSubview:_navBar];

    SPScaleButton *backBtn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [backBtn sp_setSymbol:@"chevron.left" size:18 weight:UIImageSymbolWeightSemibold animated:NO];
    backBtn.tintColor = SPTheme.textPrimaryColor;
    [backBtn addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBar addSubview:backBtn];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"漫游调频";
    titleLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor = SPTheme.textPrimaryColor;
    [_navBar addSubview:titleLabel];

    UIView *onAirPill = [UIView new];
    onAirPill.backgroundColor = SPTheme.highlightColor;
    onAirPill.layer.cornerRadius = 12;
    onAirPill.layer.cornerCurve = kCACornerCurveContinuous;
    [_navBar addSubview:onAirPill];

    _onAirDot = [UIView new];
    _onAirDot.layer.cornerRadius = 3.5;
    [onAirPill addSubview:_onAirDot];

    _onAirLabel = [UILabel new];
    _onAirLabel.font = [SPTheme monospacedDigitFontOfSize:10.5 weight:UIFontWeightBold];
    _onAirLabel.textColor = SPTheme.textSecondaryColor;
    _onAirLabel.text = @"FM READY";
    [onAirPill addSubview:_onAirLabel];

    [_onAirDot mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(onAirPill).offset(9);
        make.centerY.equalTo(onAirPill);
        make.size.mas_equalTo(CGSizeMake(7, 7));
    }];
    [_onAirLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.onAirDot.mas_right).offset(5);
        make.right.equalTo(onAirPill).offset(-9);
        make.centerY.equalTo(onAirPill);
    }];

    _navDivider = [UIView new];
    _navDivider.backgroundColor = SPTheme.separatorColor;
    _navDivider.alpha = 0.0;
    [_navBar addSubview:_navDivider];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.contentInset = UIEdgeInsetsMake(8, 0, 28, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPMediaRowCell.class forCellReuseIdentifier:[SPMediaRowCell reuseId]];
    [self.view addSubview:_tableView];

    UIView *headerWrap = [self buildTableHeaderView];
    _tableView.tableHeaderView = headerWrap;

    [_ambientGradient mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.height.mas_equalTo(300);
    }];
    [_navBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(48);
    }];
    [backBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.navBar).offset(8);
        make.bottom.equalTo(self.navBar).offset(-2);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.navBar);
        make.centerY.equalTo(backBtn);
    }];
    [onAirPill mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.navBar).offset(-14);
        make.centerY.equalTo(backBtn);
        make.height.mas_equalTo(24);
    }];
    [_navDivider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.navBar);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.navBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
}

- (UIView *)buildTableHeaderView {
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 410)];

    // 外层调频主机卡（外圆角 26 = 内部 dial/showcase 圆角 12 + 内边距 14）
    _tunerCard = [UIView new];
    _tunerCard.backgroundColor = SPTheme.elevatedColor;
    _tunerCard.layer.cornerRadius = 26;
    _tunerCard.layer.cornerCurve = kCACornerCurveContinuous;
    _tunerCard.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    [wrap addSubview:_tunerCard];

    _freqNumberLabel = [UILabel new];
    _freqNumberLabel.font = [SPTheme monospacedDigitFontOfSize:34 weight:UIFontWeightBold];
    _freqNumberLabel.textColor = SPTheme.textPrimaryColor;
    [_tunerCard addSubview:_freqNumberLabel];

    UILabel *mhzUnit = [UILabel new];
    mhzUnit.text = @"MHz";
    mhzUnit.font = [SPTheme monospacedDigitFontOfSize:13 weight:UIFontWeightSemibold];
    mhzUnit.textColor = SPTheme.textSecondaryColor;
    [_tunerCard addSubview:mhzUnit];

    _stationTitleLabel = [UILabel new];
    _stationTitleLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    _stationTitleLabel.textColor = SPTheme.textPrimaryColor;
    _stationTitleLabel.textAlignment = NSTextAlignmentRight;
    [_tunerCard addSubview:_stationTitleLabel];

    _stationTaglineLabel = [UILabel new];
    _stationTaglineLabel.font = [SPTheme fontOfSize:12.5 weight:UIFontWeightRegular];
    _stationTaglineLabel.textColor = SPTheme.textSecondaryColor;
    _stationTaglineLabel.numberOfLines = 2;
    [_tunerCard addSubview:_stationTaglineLabel];

    __weak typeof(self) weakSelf = self;
    _dialView = [SPFrequencyDialView new];
    _dialView.stations = self.stations;
    _dialView.stationScrubbedHandler = ^(NSInteger stationIndex) {
        [weakSelf selectStationAtIndex:stationIndex autoPlay:NO];
    };
    [_tunerCard addSubview:_dialView];

    // 横向频段快选胶囊栏（内缩 14pt 并加右侧柔化羽化遮罩，消除生硬截断）
    _chipClipHost = [UIView new];
    _chipClipHost.backgroundColor = UIColor.clearColor;
    _chipClipHost.clipsToBounds = YES;
    [_tunerCard addSubview:_chipClipHost];

    _chipEdgeMaskLayer = [CAGradientLayer layer];
    _chipEdgeMaskLayer.startPoint = CGPointMake(0.0, 0.5);
    _chipEdgeMaskLayer.endPoint = CGPointMake(1.0, 0.5);
    _chipEdgeMaskLayer.colors = @[
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
    ];
    _chipEdgeMaskLayer.locations = @[@0.0, @0.88, @1.0];
    _chipClipHost.layer.mask = _chipEdgeMaskLayer;

    UIScrollView *chipScroll = [UIScrollView new];
    chipScroll.showsHorizontalScrollIndicator = NO;
    chipScroll.clipsToBounds = NO;
    [_chipClipHost addSubview:chipScroll];

    NSMutableArray<SPScaleButton *> *chips = [NSMutableArray arrayWithCapacity:self.stations.count];
    for (NSInteger i = 0; i < (NSInteger)self.stations.count; i++) {
        SPMoodStation *st = self.stations[i];
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.title = st.name;
        cfg.image = [SPTheme symbol:st.symbolName size:11.5 weight:UIImageSymbolWeightSemibold];
        cfg.imagePadding = 5;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(6, 11, 6, 12);
        SPScaleButton *btn = [SPScaleButton buttonWithType:UIButtonTypeCustom];
        btn.configuration = cfg;
        btn.tag = i;
        btn.layer.cornerRadius = 15;
        btn.layer.cornerCurve = kCACornerCurveContinuous;
        btn.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        [btn addTarget:self action:@selector(stationChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [chips addObject:btn];
    }
    _stationChipButtons = chips;
    UIStackView *chipStack = [[UIStackView alloc] initWithArrangedSubviews:chips];
    chipStack.axis = UILayoutConstraintAxisHorizontal;
    chipStack.spacing = 8;
    [chipScroll addSubview:chipStack];

    // 当前频段主打曲目与漫游主控区（12pt 容器圆角与 6pt 内封面圆角 + 8pt 边距同心）
    _showcaseBox = [UIView new];
    _showcaseBox.backgroundColor = SPTheme.highlightColor;
    _showcaseBox.layer.cornerRadius = 12;
    _showcaseBox.layer.cornerCurve = kCACornerCurveContinuous;
    [_tunerCard addSubview:_showcaseBox];

    _showcaseCover = [UIImageView new];
    _showcaseCover.contentMode = UIViewContentModeScaleAspectFill;
    _showcaseCover.clipsToBounds = YES;
    _showcaseCover.layer.cornerRadius = 6;
    [_showcaseBox addSubview:_showcaseCover];

    _showcaseTitleLabel = [UILabel new];
    _showcaseTitleLabel.font = [SPTheme fontOfSize:14.5 weight:UIFontWeightBold];
    _showcaseTitleLabel.textColor = SPTheme.textPrimaryColor;

    _showcaseArtistLabel = [UILabel new];
    _showcaseArtistLabel.font = [SPTheme fontOfSize:12 weight:UIFontWeightRegular];
    _showcaseArtistLabel.textColor = SPTheme.textSecondaryColor;

    UIStackView *showcaseText = [[UIStackView alloc] initWithArrangedSubviews:@[_showcaseTitleLabel, _showcaseArtistLabel]];
    showcaseText.axis = UILayoutConstraintAxisVertical;
    showcaseText.spacing = 2;
    [_showcaseBox addSubview:showcaseText];

    _loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingSpinner.color = SPTheme.accentColor;
    _loadingSpinner.hidesWhenStopped = YES;
    [_showcaseBox addSubview:_loadingSpinner];

    _roamPlayButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _roamPlayButton.layer.cornerRadius = 21;
    _roamPlayButton.layer.cornerCurve = kCACornerCurveContinuous;
    _roamPlayButton.titleLabel.font = [SPTheme fontOfSize:14.5 weight:UIFontWeightBold];
    [_roamPlayButton addTarget:self action:@selector(roamPlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [_tunerCard addSubview:_roamPlayButton];

    UIButtonConfiguration *shufCfg = [UIButtonConfiguration plainButtonConfiguration];
    shufCfg.title = @"换一批";
    shufCfg.image = [SPTheme symbol:@"arrow.triangle.2.circlepath" size:13 weight:UIImageSymbolWeightSemibold];
    shufCfg.imagePadding = 5;
    shufCfg.baseForegroundColor = SPTheme.textPrimaryColor;
    shufCfg.contentInsets = NSDirectionalEdgeInsetsMake(0, 14, 0, 14);
    shufCfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [SPTheme fontOfSize:13.5 weight:UIFontWeightSemibold];
        return attrs;
    };
    _shuffleBatchButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _shuffleBatchButton.configuration = shufCfg;
    _shuffleBatchButton.backgroundColor = SPTheme.highlightColor;
    _shuffleBatchButton.layer.cornerRadius = 21;
    _shuffleBatchButton.layer.cornerCurve = kCACornerCurveContinuous;
    [_shuffleBatchButton addTarget:self action:@selector(shuffleBatchTapped) forControlEvents:UIControlEventTouchUpInside];
    [_tunerCard addSubview:_shuffleBatchButton];

    UILabel *sectionHeader = [UILabel new];
    sectionHeader.text = @"本频段漫游曲目";
    sectionHeader.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    sectionHeader.textColor = SPTheme.textPrimaryColor;
    [wrap addSubview:sectionHeader];

    [_tunerCard mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(wrap).offset(4);
        make.left.equalTo(wrap).offset(SPMarginHorizontal);
        make.right.equalTo(wrap).offset(-SPMarginHorizontal);
    }];
    [_freqNumberLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.tunerCard).offset(16);
        make.left.equalTo(self.tunerCard).offset(16);
    }];
    [mhzUnit mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.freqNumberLabel.mas_right).offset(5);
        make.lastBaseline.equalTo(self.freqNumberLabel).offset(-2);
    }];
    [_stationTitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.tunerCard).offset(-16);
        make.centerY.equalTo(self.freqNumberLabel);
        make.left.greaterThanOrEqualTo(mhzUnit.mas_right).offset(8);
    }];
    [_stationTaglineLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.freqNumberLabel.mas_bottom).offset(4);
        make.left.equalTo(self.tunerCard).offset(16);
        make.right.equalTo(self.tunerCard).offset(-16);
    }];
    [_dialView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.stationTaglineLabel.mas_bottom).offset(14);
        make.left.equalTo(self.tunerCard).offset(14);
        make.right.equalTo(self.tunerCard).offset(-14);
        make.height.mas_equalTo(56);
    }];
    [_chipClipHost mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.dialView.mas_bottom).offset(7);
        make.left.equalTo(self.tunerCard).offset(14);
        make.right.equalTo(self.tunerCard).offset(-14);
        make.height.mas_equalTo(40);
    }];
    [chipScroll mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.chipClipHost);
    }];
    [chipStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(chipScroll);
        make.left.equalTo(chipScroll);
        make.right.equalTo(chipScroll).offset(-16);
        make.height.mas_equalTo(30);
    }];
    [_showcaseBox mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.chipClipHost.mas_bottom).offset(7);
        make.left.equalTo(self.tunerCard).offset(14);
        make.right.equalTo(self.tunerCard).offset(-14);
        make.height.mas_equalTo(66);
    }];
    [_showcaseCover mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.showcaseBox).offset(8);
        make.centerY.equalTo(self.showcaseBox);
        make.size.mas_equalTo(CGSizeMake(48, 48));
    }];
    [_loadingSpinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.showcaseBox).offset(-14);
        make.centerY.equalTo(self.showcaseBox);
    }];
    [showcaseText mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.showcaseCover.mas_right).offset(12);
        make.right.equalTo(self.showcaseBox).offset(-40);
        make.centerY.equalTo(self.showcaseBox);
    }];
    [_roamPlayButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.showcaseBox.mas_bottom).offset(12);
        make.left.equalTo(self.tunerCard).offset(14);
        make.right.equalTo(self.shuffleBatchButton.mas_left).offset(-10);
        make.height.mas_equalTo(42);
        make.bottom.equalTo(self.tunerCard).offset(-14);
    }];
    [_shuffleBatchButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(self.roamPlayButton);
        make.right.equalTo(self.tunerCard).offset(-14);
        make.height.mas_equalTo(42);
        make.width.mas_greaterThanOrEqualTo(98);
    }];
    [sectionHeader mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.tunerCard.mas_bottom).offset(20);
        make.left.equalTo(wrap).offset(SPMarginHorizontal);
        make.bottom.equalTo(wrap).offset(-8);
    }];

    return wrap;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.chipEdgeMaskLayer.frame = self.chipClipHost.bounds;
    [CATransaction commit];

    UIView *header = self.tableView.tableHeaderView;
    CGFloat w = CGRectGetWidth(self.tableView.bounds);
    if (header && w > 0) {
        if (fabs(CGRectGetWidth(header.frame) - w) > 0.5) {
            header.frame = CGRectMake(0, 0, w, CGRectGetHeight(header.frame));
        }
        [header setNeedsLayout];
        [header layoutIfNeeded];
        CGSize target = CGSizeMake(w, UILayoutFittingCompressedSize.height);
        CGFloat h = [header systemLayoutSizeFittingSize:target
                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
        if (fabs(CGRectGetHeight(header.frame) - h) > 0.5 || fabs(CGRectGetWidth(header.frame) - w) > 0.5) {
            header.frame = CGRectMake(0, 0, w, h);
            self.tableView.tableHeaderView = header;
        }
    }
}

#pragma mark - Station Switching & Data

- (NSString *)contextTitleForStation:(SPMoodStation *)station {
    return [NSString stringWithFormat:@"漫游 · %@", station.name ?: @""];
}

- (BOOL)isPlayingSelectedStation {
    SPMoodStation *st = self.stations[self.selectedStationIndex];
    SPPlayerService *player = [SPPlayerService shared];
    return player.isPlaying && player.currentTrack && [player.contextTitle isEqualToString:[self contextTitleForStation:st]];
}

- (void)selectStationAtIndex:(NSInteger)index autoPlay:(BOOL)autoPlay {
    if (index < 0 || index >= (NSInteger)self.stations.count) return;
    self.selectedStationIndex = index;
    SPMoodStation *station = self.stations[index];
    UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self.view];
    UIColor *displayAccent = [self displayAccentForStation:station traitCollection:tc];

    self.freqNumberLabel.text = [NSString stringWithFormat:@"%.1f", station.frequencyMHz];
    self.stationTitleLabel.text = station.name;
    self.stationTitleLabel.textColor = displayAccent;
    self.stationTaglineLabel.text = station.tagline;
    [self.dialView setFrequency:station.frequencyMHz accentColor:displayAccent animated:YES];
    [self updateStationVisualsAnimated:YES];

    NSArray<SPTrack *> *cached = self.stationTracksCache[@(index)];
    if (cached.count > 0) {
        self.currentTracks = cached;
        [self.tableView reloadData];
        [self refreshShowcaseAndPlayButton];
        if (autoPlay) {
            [[SPPlayerService shared] playTracks:cached startIndex:0 contextTitle:[self contextTitleForStation:station]];
        }
        return;
    }

    [self fetchTracksForStationIndex:index forceNextKeyword:NO autoPlay:autoPlay];
}

- (void)fetchTracksForStationIndex:(NSInteger)stationIdx forceNextKeyword:(BOOL)nextKw autoPlay:(BOOL)autoPlay {
    SPMoodStation *station = self.stations[stationIdx];
    NSUInteger kwIdx = [self.stationKeywordCursor[@(stationIdx)] unsignedIntegerValue];
    if (nextKw) {
        kwIdx = (kwIdx + 1) % MAX((NSUInteger)1, station.keywords.count);
        self.stationKeywordCursor[@(stationIdx)] = @(kwIdx);
    }
    NSString *keyword = station.keywords[kwIdx % station.keywords.count];

    self.fetchToken += 1;
    NSUInteger token = self.fetchToken;
    [self.loadingSpinner startAnimating];
    [self.showcaseCover sp_cancelCoverLoadAndReset];
    self.showcaseTitleLabel.text = [NSString stringWithFormat:@"正在调谐 %.1f MHz...", station.frequencyMHz];
    self.showcaseArtistLabel.text = station.name;

    __weak typeof(self) weakSelf = self;
    SPMusicRepository *repo = [SPMusicRepository shared];
    [repo searchWithKeyword:keyword completion:^(SPSearchResult *result, NSError *error) {
        if (!weakSelf) return;
        if (!error && result.tracks.count > 0) {
            NSArray<SPTrack *> *slice = result.tracks.count > 12
                ? [result.tracks subarrayWithRange:NSMakeRange(0, 12)]
                : result.tracks;
            [weakSelf applyLoadedTracks:slice forStationIndex:stationIdx token:token autoPlay:autoPlay notifyIfEmpty:(nextKw || autoPlay)];
        } else {
            // Mock 或无结果兜底：从首页精选提取真实可播曲目
            [repo fetchHomeSectionsWithCompletion:^(NSArray<SPHomeSection *> *sections, NSError *homeErr) {
                if (!weakSelf) return;
                NSMutableArray<SPTrack *> *fallback = [NSMutableArray array];
                SPPlaylist *firstLazyPlaylist = nil;
                for (SPHomeSection *sec in sections) {
                    for (id<SPMediaItem> item in sec.items) {
                        if ([item isKindOfClass:SPPlaylist.class]) {
                            SPPlaylist *pl = (SPPlaylist *)item;
                            if (!firstLazyPlaylist && pl.identifier.length > 0 && !pl.isPodcast) {
                                firstLazyPlaylist = pl;
                            }
                            [fallback addObjectsFromArray:pl.tracks ?: @[]];
                        } else if ([item isKindOfClass:SPAlbum.class]) {
                            [fallback addObjectsFromArray:((SPAlbum *)item).tracks ?: @[]];
                        }
                    }
                }
                if (fallback.count > 0) {
                    NSMutableArray<SPTrack *> *picked = [NSMutableArray array];
                    NSUInteger start = ((NSUInteger)stationIdx * 3 + kwIdx) % fallback.count;
                    for (NSUInteger k = 0; k < MIN((NSUInteger)10, fallback.count); k++) {
                        [picked addObject:fallback[(start + k) % fallback.count]];
                    }
                    [weakSelf applyLoadedTracks:picked forStationIndex:stationIdx token:token autoPlay:autoPlay notifyIfEmpty:(nextKw || autoPlay)];
                    return;
                }
                if (firstLazyPlaylist) {
                    [repo fetchPlaylistWithId:firstLazyPlaylist.identifier completion:^(SPPlaylist *pl, NSError *plErr) {
                        if (!weakSelf) return;
                        NSArray<SPTrack *> *plTracks = pl.tracks ?: @[];
                        NSMutableArray<SPTrack *> *picked = [NSMutableArray array];
                        if (plTracks.count > 0) {
                            NSUInteger start = ((NSUInteger)stationIdx * 3 + kwIdx) % plTracks.count;
                            for (NSUInteger k = 0; k < MIN((NSUInteger)10, plTracks.count); k++) {
                                [picked addObject:plTracks[(start + k) % plTracks.count]];
                            }
                        }
                        [weakSelf applyLoadedTracks:picked forStationIndex:stationIdx token:token autoPlay:autoPlay notifyIfEmpty:(nextKw || autoPlay)];
                    }];
                    return;
                }
                [weakSelf applyLoadedTracks:@[] forStationIndex:stationIdx token:token autoPlay:autoPlay notifyIfEmpty:(nextKw || autoPlay)];
            }];
        }
    }];
}

- (void)applyLoadedTracks:(NSArray<SPTrack *> *)tracks
          forStationIndex:(NSInteger)stationIdx
                    token:(NSUInteger)token
                 autoPlay:(BOOL)autoPlay
            notifyIfEmpty:(BOOL)notifyIfEmpty {
    if (tracks.count > 0) {
        self.stationTracksCache[@(stationIdx)] = tracks;
    }
    if (token != self.fetchToken || stationIdx != self.selectedStationIndex) return;

    [self.loadingSpinner stopAnimating];
    self.currentTracks = tracks ?: @[];
    [self.tableView reloadData];
    [self refreshShowcaseAndPlayButton];

    if (tracks.count == 0 && notifyIfEmpty) {
        [SPToast showMessage:@"暂未获取到该频段曲目，可轻触「换一批」重试"];
    }
    if (autoPlay && tracks.count > 0) {
        SPMoodStation *st = self.stations[stationIdx];
        [[SPPlayerService shared] playTracks:tracks startIndex:0 contextTitle:[self contextTitleForStation:st]];
    }
}

- (void)updateStationVisualsAnimated:(BOOL)animated {
    UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self.view];
    BOOL isLight = (tc.userInterfaceStyle == UIUserInterfaceStyleLight);
    SPMoodStation *st = self.stations[self.selectedStationIndex];
    UIColor *displayAccent = [self displayAccentForStation:st traitCollection:tc];

    self.stationTitleLabel.textColor = displayAccent;
    self.dialView.needleColor = displayAccent;
    [self.dialView updateColors];

    UIColor *topGlow = [st.accentColor colorWithAlphaComponent:(isLight ? 0.12 : 0.24)];
    [self.ambientGradient setColors:@[topGlow, SPTheme.backgroundColor] animated:animated];
    self.tunerCard.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:tc].CGColor;

    for (SPScaleButton *btn in self.stationChipButtons) {
        BOOL sel = (btn.tag == self.selectedStationIndex);
        SPMoodStation *itemSt = self.stations[btn.tag];
        UIColor *chipAccent = [self displayAccentForStation:itemSt traitCollection:tc];
        UIButtonConfiguration *cfg = [btn.configuration copy];
        cfg.baseForegroundColor = sel ? chipAccent : SPTheme.textSecondaryColor;
        cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
            NSMutableDictionary *attrs = [incoming mutableCopy];
            attrs[NSFontAttributeName] = [SPTheme fontOfSize:12 weight:(sel ? UIFontWeightBold : UIFontWeightMedium)];
            return attrs;
        };
        btn.configuration = cfg;
        btn.backgroundColor = sel ? [chipAccent colorWithAlphaComponent:(isLight ? 0.12 : 0.18)] : SPTheme.highlightColor;
        btn.layer.borderColor = sel
            ? [chipAccent colorWithAlphaComponent:0.45].CGColor
            : [SPTheme.separatorColor resolvedColorWithTraitCollection:tc].CGColor;
    }
    [self refreshShowcaseAndPlayButton];
}

- (void)refreshShowcaseAndPlayButton {
    UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self.view];
    BOOL isLight = (tc.userInterfaceStyle == UIUserInterfaceStyleLight);
    SPMoodStation *st = self.stations[self.selectedStationIndex];
    UIColor *displayAccent = [self displayAccentForStation:st traitCollection:tc];
    SPPlayerService *player = [SPPlayerService shared];
    BOOL stationActive = [player.contextTitle isEqualToString:[self contextTitleForStation:st]] && player.currentTrack != nil;
    BOOL playingNow = stationActive && player.isPlaying;

    self.onAirDot.backgroundColor = playingNow ? displayAccent : SPTheme.textTertiaryColor;
    self.onAirLabel.text = playingNow ? [NSString stringWithFormat:@"ON AIR · %.1f", st.frequencyMHz] : @"FM READY";
    self.onAirLabel.textColor = playingNow ? displayAccent : SPTheme.textSecondaryColor;

    SPTrack *heroTrack = stationActive ? player.currentTrack : self.currentTracks.firstObject;
    if (heroTrack) {
        self.showcaseTitleLabel.text = heroTrack.name;
        self.showcaseArtistLabel.text = [heroTrack artistNames];
        [self.showcaseCover sp_setCoverWithItem:heroTrack];
    } else if (!self.loadingSpinner.isAnimating) {
        self.showcaseTitleLabel.text = @"暂无曲目，可轻触「换一批」重试";
        self.showcaseArtistLabel.text = st.tagline;
    }

    UIColor *buttonFill = isLight ? displayAccent : st.accentColor;
    self.roamPlayButton.backgroundColor = buttonFill;
    // 根据按钮底色亮度选择高对比文字色
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [buttonFill getRed:&r green:&g blue:&b alpha:&a];
    CGFloat lum = 0.299 * r + 0.587 * g + 0.114 * b;
    UIColor *fg = (lum > 0.62) ? [UIColor sp_colorWithHex:0x0B0B0C] : UIColor.whiteColor;
    [self.roamPlayButton setTitleColor:fg forState:UIControlStateNormal];
    [self.roamPlayButton setTitle:(playingNow ? @"暂停漫游" : @"立即漫游播放") forState:UIControlStateNormal];
}

- (void)themeDidChange {
    self.view.backgroundColor = SPTheme.backgroundColor;
    [self updateStationVisualsAnimated:NO];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateStationVisualsAnimated:NO];
    }
}

#pragma mark - Actions

- (void)backTapped {
    [SPHaptics light];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)stationChipTapped:(SPScaleButton *)sender {
    if (sender.tag == self.selectedStationIndex) return;
    [SPHaptics selection];
    [self selectStationAtIndex:sender.tag autoPlay:NO];
}

- (void)roamPlayTapped {
    [SPHaptics medium];
    SPMoodStation *st = self.stations[self.selectedStationIndex];
    SPPlayerService *player = [SPPlayerService shared];
    if ([player.contextTitle isEqualToString:[self contextTitleForStation:st]] && player.currentTrack) {
        [player togglePlayPause];
        return;
    }
    if (self.currentTracks.count > 0) {
        [player playTracks:self.currentTracks startIndex:0 contextTitle:[self contextTitleForStation:st]];
    } else {
        [self fetchTracksForStationIndex:self.selectedStationIndex forceNextKeyword:NO autoPlay:YES];
    }
}

- (void)shuffleBatchTapped {
    [SPHaptics light];
    [self.stationTracksCache removeObjectForKey:@(self.selectedStationIndex)];
    [self fetchTracksForStationIndex:self.selectedStationIndex forceNextKeyword:YES autoPlay:[self isPlayingSelectedStation]];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.currentTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPMediaRowCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPMediaRowCell reuseId] forIndexPath:indexPath];
    SPTrack *track = self.currentTracks[indexPath.row];
    SPPlayerService *player = [SPPlayerService shared];
    cell.rowView.coverSize = 50;
    [cell.rowView configureWithItem:track];
    [cell.rowView setActive:[track isEqual:player.currentTrack] isPlaying:player.isPlaying];
    cell.showsMoreButton = YES;
    __weak typeof(self) weakSelf = self;
    cell.moreHandler = ^{
        [weakSelf presentActionSheetForTrack:track atIndex:indexPath.row];
    };
    return cell;
}

- (void)presentActionSheetForTrack:(SPTrack *)track atIndex:(NSInteger)index {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:track.name
                                                                   message:[track artistNames]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;

    SPLibraryStore *store = [SPLibraryStore shared];
    BOOL isLiked = [store isTrackLiked:track.identifier];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:(isLiked ? @"取消喜欢" : @"喜欢这首歌")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        BOOL likedNow = [store toggleLikeTrack:track];
        [SPHaptics medium];
        [SPToast showMessage:likedNow ? @"已添加到「已点赞的歌曲」" : @"已取消点赞"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"添加到歌单..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SPLibraryActionSheet presentAddTrack:track toPlaylistFrom:weakSelf];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"下一首播放" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[SPPlayerService shared] insertNextTrack:track];
        [SPToast showMessage:@"已添加到下一首播放"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [SPHaptics light];
    SPMoodStation *st = self.stations[self.selectedStationIndex];
    [[SPPlayerService shared] playTracks:self.currentTracks
                              startIndex:indexPath.row
                            contextTitle:[self contextTitleForStation:st]];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offsetY = MAX(0.0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top);
    self.navDivider.alpha = MIN(MAX(offsetY / 18.0, 0.0), 1.0);
}

#pragma mark - SPPlayerObserver

- (void)syncVisibleTrackRows {
    SPPlayerService *player = [SPPlayerService shared];
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        if (ip.row >= (NSInteger)self.currentTracks.count) continue;
        SPMediaRowCell *cell = [self.tableView cellForRowAtIndexPath:ip];
        if ([cell isKindOfClass:SPMediaRowCell.class]) {
            [cell.rowView setActive:[self.currentTracks[ip.row] isEqual:player.currentTrack] isPlaying:player.isPlaying];
        }
    }
    [self refreshShowcaseAndPlayButton];
}

- (void)playerDidChangeTrack:(SPPlayerService *)player { [self syncVisibleTrackRows]; }
- (void)playerDidChangeState:(SPPlayerService *)player { [self syncVisibleTrackRows]; }

@end
