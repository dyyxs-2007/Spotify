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
@property (nonatomic, strong) UILabel *lyricLabel;
@property (nonatomic, strong) UILabel *translationLabel;
@end

@implementation SPFullLyricLineCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _lyricLabel = [UILabel new];
        _lyricLabel.numberOfLines = 0;

        _translationLabel = [UILabel new];
        _translationLabel.numberOfLines = 0;
        _translationLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightMedium];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_lyricLabel, _translationLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 6;
        [self.contentView addSubview:stack];

        [stack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.contentView).offset(12);
            make.bottom.equalTo(self.contentView).offset(-12);
            make.left.equalTo(self.contentView).offset(24);
            make.right.equalTo(self.contentView).offset(-24);
        }];
    }
    return self;
}

- (void)configureWithLine:(SPLyricLine *)line
                 isSynced:(BOOL)isSynced
                 isActive:(BOOL)isActive
                   isPast:(BOOL)isPast
          showTranslation:(BOOL)showTranslation {
    self.lyricLabel.text = line.text;
    BOOL hasTrans = (showTranslation && line.translation.length > 0);
    self.translationLabel.hidden = !hasTrans;
    self.translationLabel.text = line.translation;

    if (!isSynced) {
        self.lyricLabel.font = [SPTheme fontOfSize:20 weight:UIFontWeightSemibold];
        self.lyricLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.88];
        self.translationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        return;
    }

    if (isActive) {
        self.lyricLabel.font = [SPTheme fontOfSize:24 weight:UIFontWeightBold];
        self.lyricLabel.textColor = UIColor.whiteColor;
        self.translationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.88];
    } else if (isPast) {
        self.lyricLabel.font = [SPTheme fontOfSize:21 weight:UIFontWeightSemibold];
        self.lyricLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.36];
        self.translationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.26];
    } else {
        self.lyricLabel.font = [SPTheme fontOfSize:21 weight:UIFontWeightSemibold];
        self.lyricLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.58];
        self.translationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    }
}

@end

@interface SPFullScreenLyricsViewController () <UITableViewDataSource, UITableViewDelegate, SPPlayerObserver>
@property (nonatomic, strong, nullable) SPTrack *track;
@property (nonatomic, strong, nullable) SPLyricDocument *document;
@property (nonatomic, strong) UIColor *themeColor;
@property (nonatomic, assign) BOOL showTranslation;

@property (nonatomic, strong) SPGradientView *backgroundGradient;
@property (nonatomic, strong) UIImageView *miniCoverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) SPScaleButton *translationButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UILabel *currentTimeLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) SPScaleButton *playPauseButton;

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
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor sp_colorWithHex:0x101114];
    [self setupViews];
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

    UIView *topBar = [UIView new];
    [self.view addSubview:topBar];

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
    topRight.spacing = 10;
    topRight.alignment = UIStackViewAlignmentCenter;
    [topBar addSubview:topRight];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60;
    _tableView.contentInset = UIEdgeInsetsMake(20, 0, 44, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPFullLyricLineCell.class forCellReuseIdentifier:[SPFullLyricLineCell reuseId]];
    [self.view addSubview:_tableView];

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

    _progressSlider = [UISlider new];
    _progressSlider.minimumTrackTintColor = UIColor.whiteColor;
    _progressSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    [_progressSlider setThumbImage:[self circleThumbWithDiameter:10] forState:UIControlStateNormal];
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
    [topBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(8);
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

    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(topBar.mas_bottom).offset(4);
        make.left.right.equalTo(self.view);
        make.bottom.equalTo(bottomDock.mas_top).offset(-8);
    }];
    [_spinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableView);
    }];
    [_emptyLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableView);
        make.left.equalTo(self.view).offset(24);
        make.right.equalTo(self.view).offset(-24);
    }];
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
                showTranslation:self.showTranslation];
    }
    if (idx >= 0 && idx < (NSInteger)self.document.lines.count &&
        CFAbsoluteTimeGetCurrent() >= self.pauseAutoScrollUntil) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0]
                              atScrollPosition:UITableViewScrollPositionMiddle
                                      animated:(animated && !UIAccessibilityIsReduceMotionEnabled())];
    }
}

#pragma mark - Actions

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
            showTranslation:self.showTranslation];
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
