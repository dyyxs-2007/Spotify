//
//  SPLyricsCardView.m
//  Spotify
//

#import "SPLyricsCardView.h"
#import "SPScaleButton.h"
#import "SPHaptics.h"

#pragma mark - Lyric Line Cell

@interface SPLyricCardLineCell : UITableViewCell
@property (nonatomic, strong) UILabel *lyricLabel;
@property (nonatomic, strong) UILabel *translationLabel;
@end

@implementation SPLyricCardLineCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _lyricLabel = [UILabel new];
        _lyricLabel.numberOfLines = 0;
        _lyricLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];

        _translationLabel = [UILabel new];
        _translationLabel.numberOfLines = 0;
        _translationLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightMedium];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_lyricLabel, _translationLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        [self.contentView addSubview:stack];

        [stack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.contentView).offset(8);
            make.bottom.equalTo(self.contentView).offset(-8);
            make.left.equalTo(self.contentView).offset(18);
            make.right.equalTo(self.contentView).offset(-18);
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
        self.lyricLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightSemibold];
        self.lyricLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.86];
        self.translationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        return;
    }

    if (isActive) {
        self.lyricLabel.font = [SPTheme fontOfSize:18.5 weight:UIFontWeightBold];
        self.lyricLabel.textColor = UIColor.whiteColor;
        self.translationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    } else if (isPast) {
        self.lyricLabel.font = [SPTheme fontOfSize:16.5 weight:UIFontWeightSemibold];
        self.lyricLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
        self.translationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.30];
    } else {
        self.lyricLabel.font = [SPTheme fontOfSize:16.5 weight:UIFontWeightSemibold];
        self.lyricLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
        self.translationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.46];
    }
}

@end

#pragma mark - SPLyricsCardView

@interface SPLyricsCardView () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) SPScaleButton *translationButton;
@property (nonatomic, strong) SPScaleButton *expandButton;
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
    rightBar.spacing = 8;
    rightBar.alignment = UIStackViewAlignmentCenter;
    [headerBar addSubview:rightBar];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 44;
    _tableView.contentInset = UIEdgeInsetsMake(4, 0, 26, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPLyricCardLineCell.class forCellReuseIdentifier:[SPLyricCardLineCell reuseId]];
    [self addSubview:_tableView];

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
        make.height.mas_equalTo(48);
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
        make.right.equalTo(headerBar).offset(-14);
        make.centerY.equalTo(headerBar);
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(headerBar.mas_bottom);
        make.left.right.bottom.equalTo(self);
    }];
    [_spinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableView);
    }];
    [_emptyLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableView);
        make.left.equalTo(self).offset(24);
        make.right.equalTo(self).offset(-24);
    }];

    [self updateTranslationButtonAppearance];
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
                showTranslation:self.showTranslation];
    }
}

#pragma mark - Actions

- (void)translationTapped {
    [SPHaptics selection];
    self.showTranslation = !self.showTranslation;
    [self updateTranslationButtonAppearance];
    [self.tableView reloadData];
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
            showTranslation:self.showTranslation];
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
