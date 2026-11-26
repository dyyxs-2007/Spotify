//
//  SPLyricsCardView.m
//  Spotify
//

#import "SPLyricsCardView.h"
#import "SPScaleButton.h"
#import "SPHaptics.h"

#pragma mark - Lyric Line Cell

@interface SPLyricCardLineCell : UITableViewCell
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *lyricLabel;
@property (nonatomic, strong) UILabel *translationLabel;
@property (nonatomic, assign) BOOL activeScale;
@end

@implementation SPLyricCardLineCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _lyricLabel = [UILabel new];
        _lyricLabel.numberOfLines = 0;
        _lyricLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
        // 固定使用高亮最大字号以确保 AutoLayout 行高始终完整预留，避免切行变大时截断长歌词
        _lyricLabel.font = [SPTheme fontOfSize:18.5 weight:UIFontWeightBold];

        _translationLabel = [UILabel new];
        _translationLabel.numberOfLines = 0;
        _translationLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
        _translationLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightMedium];

        _contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[_lyricLabel, _translationLabel]];
        _contentStack.axis = UILayoutConstraintAxisVertical;
        _contentStack.spacing = 4;
        [self.contentView addSubview:_contentStack];

        [_contentStack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.contentView).offset(8);
            make.bottom.equalTo(self.contentView).offset(-8);
            make.left.equalTo(self.contentView).offset(18);
            make.right.equalTo(self.contentView).offset(-18);
        }];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
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
    CGFloat s = 0.94;
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
        lyricColor = [UIColor colorWithWhite:1.0 alpha:0.86];
        transColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    } else if (isActive) {
        lyricColor = UIColor.whiteColor;
        transColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    } else if (isPast) {
        lyricColor = [UIColor colorWithWhite:1.0 alpha:0.42];
        transColor = [UIColor colorWithWhite:1.0 alpha:0.30];
    } else {
        lyricColor = [UIColor colorWithWhite:1.0 alpha:0.65];
        transColor = [UIColor colorWithWhite:1.0 alpha:0.46];
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

#pragma mark - SPLyricsCardView

@interface SPLyricsCardView () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) SPScaleButton *translationButton;
@property (nonatomic, strong) SPScaleButton *expandButton;
@property (nonatomic, strong) UIView *tableContainer;
@property (nonatomic, strong) CAGradientLayer *fadeMaskLayer;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong, nullable) SPLyricDocument *document;
@property (nonatomic, assign) NSInteger activeLineIndex;
@property (nonatomic, assign) CFTimeInterval pauseAutoScrollUntil;
@end

@implementation SPLyricsCardView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _showTranslation = YES;
        _activeLineIndex = -1;
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.backgroundColor = [UIColor sp_colorWithHex:0x23262E];
    self.layer.cornerRadius = 18;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    self.clipsToBounds = YES;

    UIView *headerBar = [UIView new];
    [self addSubview:headerBar];

    _headerLabel = [UILabel new];
    _headerLabel.text = @"歌词";
    _headerLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
    _headerLabel.textColor = UIColor.whiteColor;
    [headerBar addSubview:_headerLabel];

    UIButtonConfiguration *transConfig = [UIButtonConfiguration plainButtonConfiguration];
    transConfig.contentInsets = NSDirectionalEdgeInsetsMake(0, 8, 0, 8);
    transConfig.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [SPTheme fontOfSize:12 weight:UIFontWeightBold];
        return attrs;
    };
    _translationButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _translationButton.configuration = transConfig;
    [_translationButton setTitle:@"译" forState:UIControlStateNormal];
    _translationButton.layer.cornerRadius = 12;
    _translationButton.layer.cornerCurve = kCACornerCurveContinuous;
    _translationButton.hidden = YES;
    [_translationButton addTarget:self action:@selector(translationTapped) forControlEvents:UIControlEventTouchUpInside];

    _expandButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_expandButton sp_setSymbol:@"arrow.up.left.and.arrow.down.right" size:13 weight:UIImageSymbolWeightSemibold animated:NO];
    _expandButton.tintColor = UIColor.whiteColor;
    _expandButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.26];
    _expandButton.layer.cornerRadius = 15;
    _expandButton.layer.cornerCurve = kCACornerCurveCircular;
    [_expandButton addTarget:self action:@selector(expandTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *rightBar = [[UIStackView alloc] initWithArrangedSubviews:@[_translationButton, _expandButton]];
    rightBar.axis = UILayoutConstraintAxisHorizontal;
    rightBar.spacing = 14;
    rightBar.alignment = UIStackViewAlignmentCenter;
    [headerBar addSubview:rightBar];

    _tableContainer = [UIView new];
    _tableContainer.backgroundColor = UIColor.clearColor;
    [self addSubview:_tableContainer];

    _fadeMaskLayer = [CAGradientLayer layer];
    _fadeMaskLayer.colors = @[
        (__bridge id)[UIColor colorWithWhite:0 alpha:0.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0 alpha:0.0].CGColor,
    ];
    _fadeMaskLayer.locations = @[@0.0, @0.08, @0.86, @1.0];
    _tableContainer.layer.mask = _fadeMaskLayer;

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.bounces = NO;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 46;
    _tableView.contentInset = UIEdgeInsetsMake(18, 0, 32, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPLyricCardLineCell.class forCellReuseIdentifier:[SPLyricCardLineCell reuseId]];
    [_tableContainer addSubview:_tableView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [UIColor colorWithWhite:1.0 alpha:0.85];
    _spinner.hidesWhenStopped = YES;
    [self addSubview:_spinner];

    _emptyLabel = [UILabel new];
    _emptyLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightSemibold];
    _emptyLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;
    [self addSubview:_emptyLabel];

    [headerBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self);
        make.height.mas_equalTo(54);
    }];
    [_headerLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(headerBar).offset(18);
        make.centerY.equalTo(headerBar);
    }];
    [_translationButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(24);
        make.width.mas_greaterThanOrEqualTo(30);
    }];
    [_expandButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(30, 30));
    }];
    [rightBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(headerBar).offset(-12);
        make.centerY.equalTo(headerBar);
    }];
    [_tableContainer mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(headerBar.mas_bottom);
        make.left.right.bottom.equalTo(self);
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.tableContainer);
    }];
    [_spinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableContainer);
    }];
    [_emptyLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableContainer);
        make.left.equalTo(self).offset(24);
        make.right.equalTo(self).offset(-24);
    }];

    [self updateTranslationButtonAppearance];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.fadeMaskLayer.frame = self.tableContainer.bounds;
    [CATransaction commit];
}

#pragma mark - Public API

- (void)setLoading {
    self.document = nil;
    self.activeLineIndex = -1;
    self.pauseAutoScrollUntil = 0;
    self.translationButton.hidden = YES;
    self.emptyLabel.hidden = YES;
    [self.spinner startAnimating];
    [self.tableView reloadData];
}

- (void)configureWithDocument:(nullable SPLyricDocument *)document {
    [self.spinner stopAnimating];
    self.document = document;
    self.activeLineIndex = -1;
    self.pauseAutoScrollUntil = 0;
    self.translationButton.hidden = !document.hasTranslation;
    [self updateTranslationButtonAppearance];

    if (!document || document.lines.count == 0) {
        self.emptyLabel.hidden = NO;
        self.emptyLabel.text = document.isInstrumental ? @"纯音乐，请尽情欣赏" : @"这首歌暂未收录歌词";
    } else {
        self.emptyLabel.hidden = YES;
    }

    [self.tableView reloadData];
    if (document.lines.count > 0) {
        [self.tableView setContentOffset:CGPointMake(0, -self.tableView.contentInset.top) animated:NO];
    }
}

- (void)updateCurrentTime:(NSTimeInterval)currentTime animated:(BOOL)animated {
    if (!self.document.isSynced || self.document.lines.count == 0) return;
    NSInteger nextIndex = [self.document activeLineIndexForTime:currentTime];
    if (nextIndex == self.activeLineIndex) return;

    self.activeLineIndex = nextIndex;
    [self refreshVisibleCellsState];

    if (nextIndex >= 0 && nextIndex < (NSInteger)self.document.lines.count &&
        CFAbsoluteTimeGetCurrent() >= self.pauseAutoScrollUntil) {
        NSIndexPath *target = [NSIndexPath indexPathForRow:nextIndex inSection:0];
        [self.tableView scrollToRowAtIndexPath:target
                              atScrollPosition:UITableViewScrollPositionMiddle
                                      animated:(animated && !UIAccessibilityIsReduceMotionEnabled())];
    }
}

- (void)applyThemeColor:(nullable UIColor *)color animated:(BOOL)animated {
    UIColor *base = color ? [[color sp_clampedForDarkBackground] sp_darkenedBy:0.28] : [UIColor sp_colorWithHex:0x23262E];
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.35 animations:^{
            self.backgroundColor = base;
        }];
    } else {
        self.backgroundColor = base;
    }
}

#pragma mark - Helpers

- (void)updateTranslationButtonAppearance {
    UIButtonConfiguration *cfg = [self.translationButton.configuration copy];
    cfg.baseForegroundColor = self.showTranslation ? [UIColor sp_colorWithHex:0x111214] : [UIColor colorWithWhite:1.0 alpha:0.85];
    self.translationButton.configuration = cfg;
    self.translationButton.backgroundColor = self.showTranslation
        ? [UIColor colorWithWhite:1.0 alpha:0.92]
        : [UIColor colorWithWhite:0.0 alpha:0.28];
}

- (void)refreshVisibleCellsState {
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        SPLyricCardLineCell *cell = [self.tableView cellForRowAtIndexPath:ip];
        if (![cell isKindOfClass:SPLyricCardLineCell.class]) continue;
        SPLyricLine *line = self.document.lines[ip.row];
        BOOL active = (ip.row == self.activeLineIndex);
        BOOL past = (self.activeLineIndex >= 0 && ip.row < self.activeLineIndex);
        [cell configureWithLine:line
                       isSynced:self.document.isSynced
                       isActive:active
                         isPast:past
                showTranslation:self.showTranslation
                       animated:YES];
    }
}

#pragma mark - Actions

- (void)setShowTranslation:(BOOL)showTranslation {
    if (_showTranslation == showTranslation) return;
    _showTranslation = showTranslation;
    [self updateTranslationButtonAppearance];
    [self.tableView reloadData];
    if (self.activeLineIndex >= 0 && self.activeLineIndex < (NSInteger)self.document.lines.count) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.activeLineIndex inSection:0]
                              atScrollPosition:UITableViewScrollPositionMiddle
                                      animated:NO];
    }
}

- (void)translationTapped {
    [SPHaptics selection];
    self.showTranslation = !self.showTranslation;
}

- (void)expandTapped {
    [SPHaptics light];
    if (self.expandHandler) self.expandHandler();
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.document.lines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPLyricCardLineCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPLyricCardLineCell reuseId] forIndexPath:indexPath];
    SPLyricLine *line = self.document.lines[indexPath.row];
    BOOL active = (indexPath.row == self.activeLineIndex);
    BOOL past = (self.activeLineIndex >= 0 && indexPath.row < self.activeLineIndex);
    [cell configureWithLine:line
                   isSynced:self.document.isSynced
                   isActive:active
                     isPast:past
            showTranslation:self.showTranslation
                   animated:NO];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.document.isSynced || indexPath.row >= (NSInteger)self.document.lines.count) return;
    [SPHaptics selection];
    self.pauseAutoScrollUntil = 0;
    SPLyricLine *line = self.document.lines[indexPath.row];
    if (self.seekHandler) self.seekHandler(line.time);
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.pauseAutoScrollUntil = CFAbsoluteTimeGetCurrent() + 4.0;
}

@end
