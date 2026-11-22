//
//  SPDetailHeaderView.m
//  Spotify
//

#import "SPDetailHeaderView.h"
#import "SPScaleButton.h"
#import "SPPlaylist.h"
#import "SPAlbum.h"
#import "SPArtist.h"
#import "SPFormatter.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPDetailHeaderView ()
@property (nonatomic, strong) UIView *shadowContainer;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) SPScaleButton *followButton;
@property (nonatomic, strong) SPScaleButton *likeButton;
@property (nonatomic, strong) SPScaleButton *shareButton;
@property (nonatomic, strong) SPScaleButton *moreButton;
@property (nonatomic, strong) SPScaleButton *shuffleButton;
@property (nonatomic, strong) SPScaleButton *playButton;
@property (nonatomic, assign) BOOL liked;
@property (nonatomic, assign) BOOL followed;
@property (nonatomic, assign) BOOL circularCover;
@property (nonatomic, copy, nullable) NSString *currentItemId;
@end

@implementation SPDetailHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupViews];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGRectIsEmpty(self.shadowContainer.bounds)) {
        CGFloat radius = self.circularCover ? CGRectGetWidth(self.shadowContainer.bounds) / 2.0 : 6.0;
        self.shadowContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.shadowContainer.bounds
                                                                            cornerRadius:radius].CGPath;
    }
}

- (void)setupViews {
    _shadowContainer = [UIView new];
    _shadowContainer.layer.shadowColor = UIColor.blackColor.CGColor;
    _shadowContainer.layer.shadowOpacity = 0.55;
    _shadowContainer.layer.shadowRadius = 18;
    _shadowContainer.layer.shadowOffset = CGSizeMake(0, 10);
    [self addSubview:_shadowContainer];

    _coverView = [UIImageView new];
    _coverView.contentMode = UIViewContentModeScaleAspectFill;
    _coverView.clipsToBounds = YES;
    _coverView.layer.cornerRadius = 6;
    [_shadowContainer addSubview:_coverView];

    _titleLabel = [UILabel new];
    _titleLabel.font = [SPTheme fontOfSize:22 weight:UIFontWeightBold];
    _titleLabel.textColor = SPTheme.textPrimaryColor;
    _titleLabel.numberOfLines = 2;
    [self addSubview:_titleLabel];

    _descLabel = [UILabel new];
    _descLabel.font = SPTheme.captionFont;
    _descLabel.textColor = SPTheme.textSecondaryColor;
    _descLabel.numberOfLines = 2;
    [self addSubview:_descLabel];

    _metaLabel = [UILabel new];
    _metaLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightMedium];
    _metaLabel.textColor = SPTheme.textSecondaryColor;
    _metaLabel.numberOfLines = 2;
    [self addSubview:_metaLabel];

    UIButtonConfiguration *followConfig = [UIButtonConfiguration plainButtonConfiguration];
    followConfig.contentInsets = NSDirectionalEdgeInsetsMake(0, 14, 0, 14);
    followConfig.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [SPTheme fontOfSize:13 weight:UIFontWeightBold];
        return attrs;
    };
    _followButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _followButton.configuration = followConfig;
    [_followButton setTitle:@"关注" forState:UIControlStateNormal];
    _followButton.layer.cornerRadius = 16;
    _followButton.layer.cornerCurve = kCACornerCurveContinuous;
    _followButton.layer.borderWidth = 1.0;
    [_followButton addTarget:self action:@selector(followTapped) forControlEvents:UIControlEventTouchUpInside];
    _followButton.hidden = YES;

    _likeButton = [self iconButton:@"heart" size:21 action:@selector(likeTapped)];
    _shareButton = [self iconButton:@"square.and.arrow.up" size:20 action:@selector(shareTapped)];
    _moreButton = [self iconButton:@"ellipsis" size:20 action:@selector(moreTapped)];
    _shuffleButton = [self iconButton:@"shuffle" size:20 action:@selector(shuffleTapped)];

    _playButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _playButton.backgroundColor = SPTheme.accentColor;
    _playButton.layer.cornerRadius = 28;
    _playButton.tintColor = UIColor.blackColor;
    _playButton.opticalHorizontalOffset = 2.0;
    [_playButton sp_setSymbol:@"play.fill" size:22 weight:UIImageSymbolWeightBold animated:NO];
    [_playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *leftActions = [[UIStackView alloc] initWithArrangedSubviews:@[_followButton, _likeButton, _shareButton, _moreButton]];
    leftActions.axis = UILayoutConstraintAxisHorizontal;
    leftActions.alignment = UIStackViewAlignmentCenter;
    leftActions.spacing = 4;

    [self addSubview:leftActions];
    [self addSubview:_shuffleButton];
    [self addSubview:_playButton];

    [_shadowContainer mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self).offset(12);
        make.centerX.equalTo(self);
        make.size.mas_equalTo(CGSizeMake(200, 200));
    }];
    [_coverView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.shadowContainer);
    }];
    [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.shadowContainer.mas_bottom).offset(20);
        make.left.equalTo(self).offset(SPMarginHorizontal);
        make.right.equalTo(self).offset(-SPMarginHorizontal);
    }];
    [_descLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.titleLabel.mas_bottom).offset(6);
        make.left.right.equalTo(self.titleLabel);
    }];
    [_metaLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.descLabel.mas_bottom).offset(6);
        make.left.right.equalTo(self.titleLabel);
    }];
    [_playButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.metaLabel.mas_bottom).offset(12);
        make.right.equalTo(self).offset(-SPMarginHorizontal);
        make.size.mas_equalTo(CGSizeMake(56, 56));
        make.bottom.equalTo(self).offset(-12);
    }];
    [_shuffleButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.playButton.mas_left).offset(-12);
        make.centerY.equalTo(self.playButton);
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    [_followButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(32);
        make.width.mas_greaterThanOrEqualTo(72);
    }];
    [_likeButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    [_shareButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    [_moreButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    [leftActions mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self).offset(SPMarginHorizontal - 4);
        make.right.lessThanOrEqualTo(self.shuffleButton.mas_left).offset(-8);
        make.centerY.equalTo(self.playButton);
    }];
    [self updateFollowState:NO animated:NO];
}

- (SPScaleButton *)iconButton:(NSString *)symbol size:(CGFloat)size action:(SEL)action {
    SPScaleButton *btn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [btn sp_setSymbol:symbol size:size weight:UIImageSymbolWeightMedium animated:NO];
    btn.tintColor = SPTheme.textSecondaryColor;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)configureWithItem:(id<SPMediaItem>)item
                   tracks:(NSArray<SPTrack *> *)tracks
                isPlaying:(BOOL)isPlaying
           shuffleEnabled:(BOOL)shuffleEnabled {
    self.currentItemId = item.identifier;
    self.titleLabel.text = item.title;
    BOOL isArtist = (item.mediaType == SPMediaTypeArtist);
    self.circularCover = isArtist;
    self.followButton.hidden = !isArtist;
    self.likeButton.hidden = isArtist;
    self.coverView.layer.cornerRadius = self.circularCover ? 100 : 6;
    [self setNeedsLayout];

    __weak typeof(self) weakSelf = self;
    NSString *itemId = item.identifier;
    [self.coverView sp_setCoverWithItem:item dominantColorCompletion:^(UIColor *color) {
        if (![weakSelf.currentItemId isEqualToString:itemId]) return;
        if (weakSelf.dominantColorHandler) weakSelf.dominantColorHandler(color);
    }];

    NSString *desc = nil;
    NSString *owner = nil;
    BOOL isPodcast = NO;
    if ([item isKindOfClass:SPPlaylist.class]) {
        SPPlaylist *pl = (SPPlaylist *)item;
        isPodcast = pl.isPodcast;
        desc = pl.desc;
        if (pl.followerCount > 0) {
            NSString *unit = isPodcast ? @"人订阅" : @"次点赞";
            owner = [NSString stringWithFormat:@"%@ · %@ %@", pl.creatorName ?: @"Spotify", [SPFormatter countString:pl.followerCount], unit];
        } else {
            owner = pl.creatorName ?: @"你";
        }
    } else if ([item isKindOfClass:SPAlbum.class]) {
        SPAlbum *al = (SPAlbum *)item;
        owner = [NSString stringWithFormat:@"%@ · %@ · %ld", [al artistNames], al.albumType ?: @"专辑", (long)al.releaseYear];
    } else {
        owner = @"艺人热门歌曲";
    }

    self.descLabel.text = desc;
    self.descLabel.hidden = (desc.length == 0);

    NSTimeInterval totalDuration = 0;
    for (SPTrack *t in tracks) totalDuration += t.duration;

    if (tracks.count > 0) {
        NSString *countUnit = isPodcast ? @"期节目" : @"首歌曲";
        self.metaLabel.text = [NSString stringWithFormat:@"%@ · %lu %@ · %@",
                               owner, (unsigned long)tracks.count, countUnit, [SPFormatter totalDurationString:totalDuration]];
    } else {
        self.metaLabel.text = owner;
    }

    [self updatePlaying:isPlaying shuffleEnabled:shuffleEnabled animated:NO];
}

- (void)updatePlaying:(BOOL)isPlaying shuffleEnabled:(BOOL)shuffleEnabled animated:(BOOL)animated {
    NSString *symbol = isPlaying ? @"pause.fill" : @"play.fill";
    self.playButton.opticalHorizontalOffset = isPlaying ? 0.0 : 2.0;
    [self.playButton sp_setSymbol:symbol size:22 weight:UIImageSymbolWeightBold animated:animated];
    self.shuffleButton.tintColor = shuffleEnabled ? SPTheme.accentColor : SPTheme.textSecondaryColor;
}

- (void)updateFollowState:(BOOL)followed animated:(BOOL)animated {
    self.followed = followed;
    UIButtonConfiguration *cfg = [self.followButton.configuration copy];
    cfg.title = followed ? @"已关注" : @"关注";
    cfg.baseForegroundColor = followed ? SPTheme.accentColor : SPTheme.textPrimaryColor;
    self.followButton.configuration = cfg;
    void (^apply)(void) = ^{
        if (followed) {
            self.followButton.backgroundColor = [SPTheme.accentColor colorWithAlphaComponent:0.16];
            self.followButton.layer.borderColor = [SPTheme.accentColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        } else {
            self.followButton.backgroundColor = UIColor.clearColor;
            self.followButton.layer.borderColor = [[SPTheme.textPrimaryColor colorWithAlphaComponent:0.32] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        }
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.2 animations:apply];
    } else {
        apply();
    }
}

- (void)updateLikeState:(BOOL)liked animated:(BOOL)animated {
    self.liked = liked;
    NSString *symbol = liked ? @"heart.fill" : @"heart";
    self.likeButton.tintColor = liked ? SPTheme.accentColor : SPTheme.textSecondaryColor;
    [self.likeButton sp_setSymbol:symbol size:21 weight:UIImageSymbolWeightMedium animated:animated];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateFollowState:self.followed animated:NO];
    }
}

#pragma mark - Actions

- (void)followTapped {
    [SPHaptics medium];
    if (self.followHandler) {
        self.followHandler();
    } else {
        [self updateFollowState:!self.followed animated:YES];
    }
}

- (void)likeTapped {
    [SPHaptics medium];
    if (self.likeHandler) {
        self.likeHandler();
    } else {
        [self updateLikeState:!self.liked animated:YES];
        [SPToast showMessage:self.liked ? @"已添加到你的音乐库" : @"已从音乐库移除"];
    }
}

- (void)shareTapped {
    [SPHaptics light];
    [SPToast showMessage:@"已复制分享信息"];
}

- (void)moreTapped {
    [SPHaptics light];
    if (self.moreHandler) {
        self.moreHandler();
    } else {
        [SPToast showMessage:@"更多操作敬请期待"];
    }
}

- (void)shuffleTapped {
    [SPHaptics selection];
    if (self.shuffleHandler) self.shuffleHandler();
}

- (void)playTapped {
    [SPHaptics medium];
    if (self.playHandler) self.playHandler();
}

@end
