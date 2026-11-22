//
//  SPCoverPreviewViewController.m
//  Spotify
//
//  Spotify
//

#import "SPCoverPreviewViewController.h"
#import "SPGradientView.h"
#import "SPScaleButton.h"
#import "SPAlbum.h"
#import "SPHaptics.h"
#import "SPToast.h"
#import <Photos/Photos.h>

@interface SPCoverPreviewViewController () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) SPTrack *track;
@property (nonatomic, strong, nullable) UIImage *placeholderImage;
@property (nonatomic, strong) UIColor *themeColor;

@property (nonatomic, strong) SPGradientView *ambientBackground;
@property (nonatomic, strong) UIVisualEffectView *blurOverlay;
@property (nonatomic, strong) UIScrollView *zoomScrollView;
@property (nonatomic, strong) UIView *coverShadowContainer;
@property (nonatomic, strong) UIImageView *coverImageView;
@property (nonatomic, strong) UIView *topChromeBar;
@property (nonatomic, strong) SPScaleButton *closeButton;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *resolutionBadgeLabel;
@property (nonatomic, strong) SPScaleButton *saveButton;
@property (nonatomic, strong) SPScaleButton *shareButton;
@property (nonatomic, strong) UIActivityIndicatorView *hdSpinner;
@property (nonatomic, strong) UIPanGestureRecognizer *dismissPan;
@end

@implementation SPCoverPreviewViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (instancetype)initWithTrack:(SPTrack *)track
             placeholderImage:(nullable UIImage *)placeholderImage
                   themeColor:(nullable UIColor *)themeColor {
    if (self = [super init]) {
        _track = track;
        _placeholderImage = placeholderImage;
        _themeColor = themeColor ?: [UIColor sp_colorWithHex:0x23252C];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor sp_colorWithHex:0x09090B];
    [self setupViews];
    [self setupGestures];
    [self loadHighResArtwork];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutInitialCoverFrameIfNeeded];
    if (!CGRectIsEmpty(self.coverShadowContainer.bounds)) {
        self.coverShadowContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.coverShadowContainer.bounds
                                                                                 cornerRadius:14].CGPath;
    }
}

- (void)setupViews {
    _ambientBackground = [SPGradientView new];
    _ambientBackground.colors = @[
        [self.themeColor colorWithAlphaComponent:0.85],
        [self.themeColor sp_darkenedBy:0.45],
        [UIColor sp_colorWithHex:0x070709],
    ];
    _ambientBackground.locations = @[@0.0, @0.45, @1.0];
    [self.view addSubview:_ambientBackground];

    _blurOverlay = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    _blurOverlay.alpha = 0.72;
    [self.view addSubview:_blurOverlay];

    _zoomScrollView = [UIScrollView new];
    _zoomScrollView.delegate = self;
    _zoomScrollView.minimumZoomScale = 1.0;
    _zoomScrollView.maximumZoomScale = 3.0;
    _zoomScrollView.showsHorizontalScrollIndicator = NO;
    _zoomScrollView.showsVerticalScrollIndicator = NO;
    _zoomScrollView.bouncesZoom = YES;
    _zoomScrollView.clipsToBounds = NO;
    [self.view addSubview:_zoomScrollView];

    _coverShadowContainer = [UIView new];
    _coverShadowContainer.layer.shadowColor = UIColor.blackColor.CGColor;
    _coverShadowContainer.layer.shadowOpacity = 0.65;
    _coverShadowContainer.layer.shadowRadius = 28;
    _coverShadowContainer.layer.shadowOffset = CGSizeMake(0, 16);
    [_zoomScrollView addSubview:_coverShadowContainer];

    _coverImageView = [UIImageView new];
    _coverImageView.contentMode = UIViewContentModeScaleAspectFill;
    _coverImageView.clipsToBounds = YES;
    _coverImageView.layer.cornerRadius = 14;
    _coverImageView.layer.cornerCurve = kCACornerCurveContinuous;
    _coverImageView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _coverImageView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    _coverImageView.backgroundColor = [UIColor sp_colorWithHex:0x1C1C20];
    _coverImageView.image = self.placeholderImage;
    [_coverShadowContainer addSubview:_coverImageView];

    // 顶部条：封面大图徽标 + 关闭按钮
    _topChromeBar = [UIView new];
    [self.view addSubview:_topChromeBar];

    UIView *badgePill = [UIView new];
    badgePill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    badgePill.layer.cornerRadius = 14;
    badgePill.layer.cornerCurve = kCACornerCurveContinuous;
    badgePill.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    badgePill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    [_topChromeBar addSubview:badgePill];

    UILabel *badgeLabel = [UILabel new];
    badgeLabel.text = @"高清封面预览";
    badgeLabel.font = [SPTheme fontOfSize:12 weight:UIFontWeightSemibold];
    badgeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.88];
    [badgePill addSubview:badgeLabel];

    _hdSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _hdSpinner.color = UIColor.whiteColor;
    _hdSpinner.transform = CGAffineTransformMakeScale(0.75, 0.75);
    _hdSpinner.hidesWhenStopped = YES;
    [_topChromeBar addSubview:_hdSpinner];

    _closeButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_closeButton sp_setSymbol:@"xmark" size:15 weight:UIImageSymbolWeightBold animated:NO];
    _closeButton.tintColor = UIColor.whiteColor;
    _closeButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    _closeButton.layer.cornerRadius = 18;
    _closeButton.layer.cornerCurve = kCACornerCurveCircular;
    _closeButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _closeButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topChromeBar addSubview:_closeButton];

    // 底部 QQ 音乐风格歌曲信息与保存/分享操作栏
    _bottomBar = [UIView new];
    [self.view addSubview:_bottomBar];

    _titleLabel = [UILabel new];
    _titleLabel.text = self.track.name ?: @"未知曲目";
    _titleLabel.font = [SPTheme fontOfSize:19 weight:UIFontWeightBold];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 1;
    [_bottomBar addSubview:_titleLabel];

    NSString *albumPart = self.track.album.name.length ? [NSString stringWithFormat:@" · 《%@》", self.track.album.name] : @"";
    _subtitleLabel = [UILabel new];
    _subtitleLabel.text = [NSString stringWithFormat:@"%@%@", [self.track artistNames], albumPart];
    _subtitleLabel.font = [SPTheme fontOfSize:13.5 weight:UIFontWeightRegular];
    _subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.68];
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    _subtitleLabel.numberOfLines = 1;
    [_bottomBar addSubview:_subtitleLabel];

    _resolutionBadgeLabel = [UILabel new];
    _resolutionBadgeLabel.font = [SPTheme monospacedDigitFontOfSize:11 weight:UIFontWeightMedium];
    _resolutionBadgeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.46];
    _resolutionBadgeLabel.textAlignment = NSTextAlignmentCenter;
    [self updateResolutionBadgeWithImage:self.placeholderImage];
    [_bottomBar addSubview:_resolutionBadgeLabel];

    _saveButton = [self pillActionButtonWithTitle:@"保存封面"
                                            symbol:@"square.and.arrow.down"
                                        isPrimary:YES
                                            action:@selector(saveTapped)];
    _shareButton = [self pillActionButtonWithTitle:@"分享"
                                             symbol:@"square.and.arrow.up"
                                         isPrimary:NO
                                             action:@selector(shareTapped)];

    UIStackView *actionRow = [[UIStackView alloc] initWithArrangedSubviews:@[_saveButton, _shareButton]];
    actionRow.axis = UILayoutConstraintAxisHorizontal;
    actionRow.spacing = 12;
    actionRow.alignment = UIStackViewAlignmentCenter;
    [_bottomBar addSubview:actionRow];

    [_ambientBackground mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [_blurOverlay mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [_topChromeBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(8);
        make.left.right.equalTo(self.view);
        make.height.mas_equalTo(44);
    }];
    [badgePill mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.topChromeBar).offset(20);
        make.centerY.equalTo(self.topChromeBar);
        make.height.mas_equalTo(28);
    }];
    [badgeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(badgePill).offset(12);
        make.right.equalTo(badgePill).offset(-12);
        make.centerY.equalTo(badgePill);
    }];
    [_hdSpinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(badgePill.mas_right).offset(10);
        make.centerY.equalTo(self.topChromeBar);
    }];
    [_closeButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.topChromeBar).offset(-20);
        make.centerY.equalTo(self.topChromeBar);
        make.size.mas_equalTo(CGSizeMake(36, 36));
    }];
    [_bottomBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.view).offset(24);
        make.right.equalTo(self.view).offset(-24);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideBottom).offset(-20);
    }];
    [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.bottomBar);
    }];
    [_subtitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.titleLabel.mas_bottom).offset(5);
        make.left.right.equalTo(self.bottomBar);
    }];
    [_resolutionBadgeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.subtitleLabel.mas_bottom).offset(6);
        make.left.right.equalTo(self.bottomBar);
    }];
    [actionRow mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.resolutionBadgeLabel.mas_bottom).offset(18);
        make.centerX.equalTo(self.bottomBar);
        make.bottom.equalTo(self.bottomBar);
        make.height.mas_equalTo(46);
    }];
    [_saveButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(46);
        make.width.mas_greaterThanOrEqualTo(148);
    }];
    [_shareButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(46);
        make.width.mas_greaterThanOrEqualTo(104);
    }];
    [_zoomScrollView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.topChromeBar.mas_bottom).offset(12);
        make.bottom.equalTo(self.bottomBar.mas_top).offset(-16);
        make.left.right.equalTo(self.view);
    }];
}

- (SPScaleButton *)pillActionButtonWithTitle:(NSString *)title symbol:(NSString *)symbol isPrimary:(BOOL)isPrimary action:(SEL)action {
    SPScaleButton *btn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = title;
    config.image = [SPTheme symbol:symbol size:15 weight:UIImageSymbolWeightSemibold];
    config.imagePadding = 8;
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.contentInsets = NSDirectionalEdgeInsetsMake(0, 20, 0, 22);
    config.baseBackgroundColor = isPrimary ? SPTheme.brandGreenColor : [UIColor colorWithWhite:1.0 alpha:0.14];
    config.baseForegroundColor = isPrimary ? [UIColor sp_colorWithHex:0x0A0B0D] : UIColor.whiteColor;
    config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [SPTheme fontOfSize:14.5 weight:UIFontWeightBold];
        return attrs;
    };
    btn.configuration = config;
    if (!isPrimary) {
        btn.layer.cornerRadius = 23;
        btn.layer.cornerCurve = kCACornerCurveContinuous;
        btn.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    }
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)layoutInitialCoverFrameIfNeeded {
    if (self.zoomScrollView.zoomScale > 1.01) return;
    CGSize boundsSize = self.zoomScrollView.bounds.size;
    if (boundsSize.width <= 0 || boundsSize.height <= 0) return;

    CGFloat side = MIN(boundsSize.width - 40.0, boundsSize.height - 20.0);
    side = MAX(side, 180.0);
    CGRect frame = CGRectMake((boundsSize.width - side) * 0.5,
                              (boundsSize.height - side) * 0.5,
                              side,
                              side);
    if (!CGRectEqualToRect(self.coverShadowContainer.frame, frame)) {
        self.coverShadowContainer.frame = frame;
        self.coverImageView.frame = self.coverShadowContainer.bounds;
        self.zoomScrollView.contentSize = boundsSize;
    }
}

#pragma mark - HD Cover Loading

- (nullable NSURL *)hdCoverURLForTrack:(SPTrack *)track {
    NSString *raw = track.coverURL;
    if (raw.length == 0) return nil;
    if ([raw hasPrefix:@"http://"]) {
        raw = [@"https://" stringByAppendingString:[raw substringFromIndex:7]];
    }
    if ([raw containsString:@"music.126.net"]) {
        NSRange range = [raw rangeOfString:@"([?&])param=[^&]+" options:NSRegularExpressionSearch];
        if (range.location != NSNotFound) {
            NSString *prefix = [raw substringWithRange:NSMakeRange(range.location, 1)];
            raw = [raw stringByReplacingCharactersInRange:range withString:[prefix stringByAppendingString:@"param=1200y1200"]];
        } else {
            NSString *sep = [raw containsString:@"?"] ? @"&" : @"?";
            raw = [raw stringByAppendingFormat:@"%@param=1200y1200", sep];
        }
    }
    return [NSURL URLWithString:raw];
}

- (void)loadHighResArtwork {
    NSURL *hdURL = [self hdCoverURLForTrack:self.track];
    if (!hdURL) return;
    [self.hdSpinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [[SDWebImageManager sharedManager] loadImageWithURL:hdURL
                                                options:SDWebImageRetryFailed | SDWebImageHighPriority
                                               progress:nil
                                              completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        if (!weakSelf) return;
        [weakSelf.hdSpinner stopAnimating];
        if (image) {
            [UIView transitionWithView:weakSelf.coverImageView
                              duration:0.24
                               options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                            animations:^{
                weakSelf.coverImageView.image = image;
            } completion:nil];
            [weakSelf updateResolutionBadgeWithImage:image];
        }
    }];
}

- (void)updateResolutionBadgeWithImage:(nullable UIImage *)image {
    if (!image) {
        self.resolutionBadgeLabel.text = @"双指缩放 · 长按或点击下方保存原图";
        return;
    }
    NSInteger pxW = (NSInteger)llround(image.size.width * image.scale);
    NSInteger pxH = (NSInteger)llround(image.size.height * image.scale);
    self.resolutionBadgeLabel.text = [NSString stringWithFormat:@"HD · %ld × %ld · 双击放大 / 下滑关闭", (long)pxW, (long)pxH];
}

#pragma mark - Gestures & UIScrollViewDelegate

- (void)setupGestures {
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.zoomScrollView addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [self.view addGestureRecognizer:singleTap];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.4;
    [self.coverShadowContainer addGestureRecognizer:longPress];

    _dismissPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissPan:)];
    _dismissPan.delegate = self;
    [self.view addGestureRecognizer:_dismissPan];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.dismissPan) {
        if (self.zoomScrollView.zoomScale > 1.02) return NO;
        CGPoint v = [self.dismissPan velocityInView:self.view];
        return v.y > 0 && fabs(v.y) > fabs(v.x);
    }
    return YES;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)tap {
    [SPHaptics light];
    if (self.zoomScrollView.zoomScale > 1.05) {
        [self.zoomScrollView setZoomScale:1.0 animated:YES];
    } else {
        CGPoint point = [tap locationInView:self.coverShadowContainer];
        CGSize scrollSize = self.zoomScrollView.bounds.size;
        CGFloat scale = 2.2;
        CGFloat w = scrollSize.width / scale;
        CGFloat h = scrollSize.height / scale;
        CGRect zoomRect = CGRectMake(point.x - w * 0.5, point.y - h * 0.5, w, h);
        [self.zoomScrollView zoomToRect:zoomRect animated:YES];
    }
}

- (void)handleSingleTap:(UITapGestureRecognizer *)tap {
    CGPoint pt = [tap locationInView:self.coverShadowContainer];
    if (CGRectContainsPoint(self.coverShadowContainer.bounds, pt)) {
        return; // 点在封面上不误关，点空白处关闭
    }
    [self closeTapped];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    [SPHaptics medium];
    [self presentActionMenu];
}

- (void)handleDismissPan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.view];
    CGPoint v = [pan velocityInView:self.view];

    if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat dy = MAX(t.y, 0);
        CGFloat progress = MIN(dy / 280.0, 1.0);
        CGFloat scale = 1.0 - 0.14 * progress;
        self.coverShadowContainer.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale),
                                                                        CGAffineTransformMakeTranslation(0, dy));
        self.ambientBackground.alpha = 1.0 - 0.55 * progress;
        self.blurOverlay.alpha = 0.72 * (1.0 - 0.55 * progress);
        self.topChromeBar.alpha = 1.0 - progress;
        self.bottomBar.alpha = 1.0 - progress;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (t.y > 110 || v.y > 750) {
            [SPHaptics light];
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            [UIView animateWithDuration:0.32
                                  delay:0
                 usingSpringWithDamping:0.86
                  initialSpringVelocity:0
                                options:UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                self.coverShadowContainer.transform = CGAffineTransformIdentity;
                self.ambientBackground.alpha = 1.0;
                self.blurOverlay.alpha = 0.72;
                self.topChromeBar.alpha = 1.0;
                self.bottomBar.alpha = 1.0;
            } completion:nil];
        }
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.coverShadowContainer;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    CGSize boundsSize = scrollView.bounds.size;
    CGRect contentsFrame = self.coverShadowContainer.frame;
    contentsFrame.origin.x = (contentsFrame.size.width < boundsSize.width)
        ? (boundsSize.width - contentsFrame.size.width) * 0.5 : 0.0;
    contentsFrame.origin.y = (contentsFrame.size.height < boundsSize.height)
        ? (boundsSize.height - contentsFrame.size.height) * 0.5 : 0.0;
    self.coverShadowContainer.frame = contentsFrame;
}

#pragma mark - Actions

- (void)closeTapped {
    [SPHaptics light];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)presentActionMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:self.track.name
                                                                   message:@"专辑高清封面选项"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    sheet.view.tintColor = SPTheme.brandGreenColor;
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"保存高清封面到相册" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf saveTapped];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享歌曲封面" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf shareTapped];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)saveTapped {
    [SPHaptics medium];
    UIImage *imageToSave = self.coverImageView.image ?: self.placeholderImage;
    if (!imageToSave) {
        [SPToast showMessage:@"封面仍在加载中，请稍候"];
        return;
    }

    __weak typeof(self) weakSelf = self;
    void (^performSave)(void) = ^{
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:imageToSave];
        } completionHandler:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    [SPToast showMessage:@"高清封面已保存到系统相册"];
                } else {
                    [SPToast showMessage:@"保存失败，请检查相册写入权限"];
                }
                (void)weakSelf;
            });
        }];
    };

    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
        performSave();
    } else if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus newStatus) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (newStatus == PHAuthorizationStatusAuthorized || newStatus == PHAuthorizationStatusLimited) {
                    performSave();
                } else {
                    [SPToast showMessage:@"未获得相册写入权限，请在系统设置中开启"];
                }
            });
        }];
    } else {
        [SPToast showMessage:@"未获得相册写入权限，请在系统设置中开启"];
    }
}

- (void)shareTapped {
    [SPHaptics light];
    NSMutableArray *items = [NSMutableArray array];
    NSString *text = [NSString stringWithFormat:@"正在听：%@ - %@", self.track.name ?: @"", [self.track artistNames]];
    [items addObject:text];
    if (self.coverImageView.image) [items addObject:self.coverImageView.image];

    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    activity.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self presentViewController:activity animated:YES completion:nil];
}

@end
