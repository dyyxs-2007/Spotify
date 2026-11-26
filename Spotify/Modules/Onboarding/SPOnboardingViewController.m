//
//  SPOnboardingViewController.m
//  Spotify
//

#import "SPOnboardingViewController.h"
#import "SPAuthWelcomeViewController.h"
#import "SPBrandMarkView.h"
#import "SPScaleButton.h"
#import "SPGradientView.h"
#import "SceneDelegate.h"
#import "SPHaptics.h"
#import <SDWebImage/SDWebImage.h>

#pragma mark - Slide Model

@interface SPOnboardingSlide : NSObject
@property (nonatomic, copy) NSString *eyebrow;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *imageURL;
@property (nonatomic, strong) UIColor *topColor;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, copy) NSString *symbolName;
@end

@implementation SPOnboardingSlide
@end

#pragma mark - Onboarding Slide Cell

@interface SPOnboardingSlideCell : UICollectionViewCell
@property (nonatomic, strong) SPGradientView *ambientBackground;
@property (nonatomic, strong) UIView *artworkContainer;
@property (nonatomic, strong) UIImageView *heroImageView;
@property (nonatomic, strong) SPGradientView *vignetteOverlay;
@property (nonatomic, strong) UIView *decorRingOuter;
@property (nonatomic, strong) UIView *decorRingInner;
@property (nonatomic, strong) UIView *decorBadge;
@property (nonatomic, strong) UIImageView *decorIcon;
@property (nonatomic, strong) UILabel *eyebrowLabel;
@property (nonatomic, strong) UIView *eyebrowPill;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *textStackContainer;
@end

@implementation SPOnboardingSlideCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.clipsToBounds = YES;
        self.contentView.backgroundColor = [UIColor sp_colorWithHex:0x0E0E10];

        _ambientBackground = [SPGradientView new];
        [self.contentView addSubview:_ambientBackground];

        _artworkContainer = [UIView new];
        _artworkContainer.clipsToBounds = YES;
        [self.contentView addSubview:_artworkContainer];

        _heroImageView = [UIImageView new];
        _heroImageView.contentMode = UIViewContentModeScaleAspectFill;
        _heroImageView.alpha = 0.56;
        _heroImageView.clipsToBounds = YES;
        [_artworkContainer addSubview:_heroImageView];

        // 柔和视觉焦点环（图片未完成加载或无网时也呈现极高辨识度的层次）
        _decorRingOuter = [UIView new];
        _decorRingOuter.layer.borderWidth = 1.0;
        _decorRingOuter.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
        _decorRingOuter.userInteractionEnabled = NO;
        [_artworkContainer addSubview:_decorRingOuter];

        _decorRingInner = [UIView new];
        _decorRingInner.layer.borderWidth = 1.0;
        _decorRingInner.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
        _decorRingInner.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.03];
        _decorRingInner.userInteractionEnabled = NO;
        [_artworkContainer addSubview:_decorRingInner];

        _decorBadge = [UIView new];
        _decorBadge.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        _decorBadge.layer.borderWidth = 1.0;
        _decorBadge.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
        [_artworkContainer addSubview:_decorBadge];

        _decorIcon = [UIImageView new];
        _decorIcon.contentMode = UIViewContentModeScaleAspectFit;
        _decorIcon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.92];
        [_decorBadge addSubview:_decorIcon];

        _vignetteOverlay = [SPGradientView new];
        _vignetteOverlay.colors = @[
            [UIColor colorWithWhite:0.055 alpha:0.25],
            [UIColor colorWithWhite:0.055 alpha:0.10],
            [UIColor colorWithWhite:0.055 alpha:0.78],
            [UIColor sp_colorWithHex:0x0E0E10],
        ];
        _vignetteOverlay.locations = @[@0.0, @0.32, @0.66, @0.88];
        [self.contentView addSubview:_vignetteOverlay];

        _textStackContainer = [UIView new];
        [self.contentView addSubview:_textStackContainer];

        _eyebrowPill = [UIView new];
        _eyebrowPill.layer.cornerRadius = 12;
        _eyebrowPill.layer.cornerCurve = kCACornerCurveContinuous;
        _eyebrowPill.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        [_textStackContainer addSubview:_eyebrowPill];

        _eyebrowLabel = [UILabel new];
        _eyebrowLabel.font = [SPTheme fontOfSize:11 weight:UIFontWeightSemibold];
        [_eyebrowPill addSubview:_eyebrowLabel];

        _titleLabel = [UILabel new];
        _titleLabel.font = [SPTheme fontOfSize:30 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.numberOfLines = 0;
        _titleLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
        [_textStackContainer addSubview:_titleLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightRegular];
        _subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.74];
        _subtitleLabel.numberOfLines = 0;
        _subtitleLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
        [_textStackContainer addSubview:_subtitleLabel];

        [_ambientBackground mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.contentView);
        }];
        [_artworkContainer mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.contentView);
        }];
        [_heroImageView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.bottom.equalTo(self.artworkContainer);
            make.left.equalTo(self.artworkContainer).offset(-32);
            make.right.equalTo(self.artworkContainer).offset(32);
        }];
        [_decorRingOuter mas_makeConstraints:^(MASConstraintMaker *make) {
            make.centerX.equalTo(self.artworkContainer);
            make.centerY.equalTo(self.artworkContainer).multipliedBy(0.72);
            make.size.mas_equalTo(CGSizeMake(248, 248));
        }];
        [_decorRingInner mas_makeConstraints:^(MASConstraintMaker *make) {
            make.center.equalTo(self.decorRingOuter);
            make.size.mas_equalTo(CGSizeMake(176, 176));
        }];
        [_decorBadge mas_makeConstraints:^(MASConstraintMaker *make) {
            make.center.equalTo(self.decorRingOuter);
            make.size.mas_equalTo(CGSizeMake(92, 92));
        }];
        [_decorIcon mas_makeConstraints:^(MASConstraintMaker *make) {
            make.center.equalTo(self.decorBadge);
            make.size.mas_equalTo(CGSizeMake(38, 38));
        }];
        [_vignetteOverlay mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.contentView);
        }];
        [_textStackContainer mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self.contentView).offset(28);
            make.right.equalTo(self.contentView).offset(-28);
            make.bottom.equalTo(self.contentView.mas_safeAreaLayoutGuideBottom).offset(-128);
        }];
        [_eyebrowPill mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.left.equalTo(self.textStackContainer);
            make.height.mas_equalTo(24);
        }];
        [_eyebrowLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self.eyebrowPill).offset(10);
            make.right.equalTo(self.eyebrowPill).offset(-10);
            make.centerY.equalTo(self.eyebrowPill);
        }];
        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.eyebrowPill.mas_bottom).offset(14);
            make.left.right.equalTo(self.textStackContainer);
        }];
        [_subtitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.titleLabel.mas_bottom).offset(12);
            make.left.right.bottom.equalTo(self.textStackContainer);
        }];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.decorRingOuter.layer.cornerRadius = 124;
    self.decorRingInner.layer.cornerRadius = 88;
    self.decorBadge.layer.cornerRadius = 46;
}

- (void)configureWithSlide:(SPOnboardingSlide *)slide {
    self.ambientBackground.colors = @[
        slide.topColor,
        [slide.topColor colorWithAlphaComponent:0.55],
        [UIColor sp_colorWithHex:0x0E0E10]
    ];
    self.ambientBackground.locations = @[@0.0, @0.48, @0.92];

    self.eyebrowPill.backgroundColor = [slide.accentColor colorWithAlphaComponent:0.16];
    self.eyebrowPill.layer.borderColor = [slide.accentColor colorWithAlphaComponent:0.35].CGColor;
    self.eyebrowLabel.text = slide.eyebrow;
    self.eyebrowLabel.textColor = slide.accentColor;

    self.decorIcon.image = [SPTheme symbol:slide.symbolName size:36 weight:UIImageSymbolWeightMedium];
    self.decorBadge.layer.borderColor = [slide.accentColor colorWithAlphaComponent:0.28].CGColor;

    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineSpacing = 4;
    self.titleLabel.attributedText = [[NSAttributedString alloc] initWithString:slide.title attributes:@{
        NSParagraphStyleAttributeName: style,
        NSFontAttributeName: [SPTheme fontOfSize:30 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: UIColor.whiteColor,
    }];

    NSMutableParagraphStyle *subStyle = [NSMutableParagraphStyle new];
    subStyle.lineSpacing = 4;
    self.subtitleLabel.attributedText = [[NSAttributedString alloc] initWithString:slide.subtitle attributes:@{
        NSParagraphStyleAttributeName: subStyle,
        NSFontAttributeName: [SPTheme fontOfSize:15 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.74],
    }];

    NSURL *url = [NSURL URLWithString:slide.imageURL];
    [self.heroImageView sd_setImageWithURL:url
                          placeholderImage:nil
                                   options:SDWebImageScaleDownLargeImages | SDWebImageRetryFailed];
}

- (void)applyParallaxOffset:(CGFloat)normalizedOffset {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.heroImageView.transform = CGAffineTransformIdentity;
        self.decorRingOuter.transform = CGAffineTransformIdentity;
        return;
    }
    self.heroImageView.transform = CGAffineTransformMakeTranslation(normalizedOffset * 28.0, 0);
    self.decorRingOuter.transform = CGAffineTransformMakeTranslation(normalizedOffset * -14.0, 0);
}

@end

#pragma mark - SPOnboardingViewController

@interface SPOnboardingViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate>
@property (nonatomic, copy) NSArray<SPOnboardingSlide *> *slides;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIView *topChromeBar;
@property (nonatomic, strong) SPBrandMarkView *brandMark;
@property (nonatomic, strong) SPScaleButton *skipButton;
@property (nonatomic, strong) UIStackView *dotsStack;
@property (nonatomic, copy) NSArray<UIView *> *dotViews;
@property (nonatomic, copy) NSArray<MASConstraint *> *dotWidthConstraints;
@property (nonatomic, strong) UILabel *swipeHintLabel;
@property (nonatomic, strong) SPScaleButton *nextRoundButton;
@property (nonatomic, strong) SPScaleButton *finalCTAButton;
@property (nonatomic, assign) NSInteger currentPage;
@property (nonatomic, assign) BOOL didProceed;
@end

@implementation SPOnboardingViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (NSInteger)slideCount { return (NSInteger)self.slides.count; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor sp_colorWithHex:0x0E0E10];
    [self buildSlides];
    [self setupViews];
    [self updateControlsForPage:0 animated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.didProceed = NO;
}

- (void)buildSlides {
    SPOnboardingSlide *s1 = [SPOnboardingSlide new];
    s1.eyebrow = @"IMMERSIVE SOUND";
    s1.title = @"每一首歌，\n都有专属氛围";
    s1.subtitle = @"封面实时取色与流体渐变背景，让每次播放都拥有细腻高级的沉浸质感。";
    s1.imageURL = @"https://picsum.photos/seed/sp-onboard-1/900/1600";
    s1.topColor = [UIColor sp_colorWithHex:0x143828];
    s1.accentColor = SPTheme.brandGreenColor;
    s1.symbolName = @"waveform";

    SPOnboardingSlide *s2 = [SPOnboardingSlide new];
    s2.eyebrow = @"ZERO LATENCY";
    s2.title = @"极速缓存，\n切歌零等待";
    s2.subtitle = @"三级 LRU 缓存与上下首自动预加载，切换上一首、下一首瞬间响应不卡顿。";
    s2.imageURL = @"https://picsum.photos/seed/sp-onboard-2/900/1600";
    s2.topColor = [UIColor sp_colorWithHex:0x271D46];
    s2.accentColor = [UIColor sp_colorWithHex:0xA78BFA];
    s2.symbolName = @"bolt.fill";

    SPOnboardingSlide *s3 = [SPOnboardingSlide new];
    s3.eyebrow = @"ALWAYS WITH YOU";
    s3.title = @"后台随行，\n灵动岛常伴";
    s3.subtitle = @"完整适配后台连续播放、锁屏控制中心进度拖动与灵动岛实时状态。";
    s3.imageURL = @"https://picsum.photos/seed/sp-onboard-3/900/1600";
    s3.topColor = [UIColor sp_colorWithHex:0x132B42];
    s3.accentColor = [UIColor sp_colorWithHex:0x38BDF8];
    s3.symbolName = @"hifispeaker.2.fill";

    SPOnboardingSlide *s4 = [SPOnboardingSlide new];
    s4.eyebrow = @"YOUR SOUNDTRACK";
    s4.title = @"开启你的\n私人音乐空间";
    s4.subtitle = @"登录或免费注册，同步你的喜爱歌单与收听足迹。继续滑动即可进入。";
    s4.imageURL = @"https://picsum.photos/seed/sp-onboard-4/900/1600";
    s4.topColor = [UIColor sp_colorWithHex:0x2F2217];
    s4.accentColor = SPTheme.brandGreenColor;
    s4.symbolName = @"music.note.list";

    self.slides = @[s1, s2, s3, s4];
}

- (void)setupViews {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 0;
    layout.minimumInteritemSpacing = 0;

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.backgroundColor = [UIColor sp_colorWithHex:0x0E0E10];
    _collectionView.pagingEnabled = YES;
    _collectionView.bounces = YES;
    _collectionView.alwaysBounceHorizontal = YES;
    _collectionView.showsHorizontalScrollIndicator = NO;
    _collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    [_collectionView registerClass:SPOnboardingSlideCell.class forCellWithReuseIdentifier:[SPOnboardingSlideCell reuseId]];
    [self.view addSubview:_collectionView];

    // 顶部品牌徽章 + 跳过按钮
    _topChromeBar = [UIView new];
    [self.view addSubview:_topChromeBar];

    _brandMark = [[SPBrandMarkView alloc] initWithCircleColor:SPTheme.brandGreenColor
                                                    waveColor:[UIColor sp_colorWithHex:0x0B0B0C]];
    [_topChromeBar addSubview:_brandMark];

    UILabel *brandTitle = [UILabel new];
    brandTitle.text = @"Spotify";
    brandTitle.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    brandTitle.textColor = UIColor.whiteColor;
    [_topChromeBar addSubview:brandTitle];

    _skipButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    [_skipButton setTitle:self.replayMode ? @"完成" : @"跳过" forState:UIControlStateNormal];
    [_skipButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.9] forState:UIControlStateNormal];
    _skipButton.titleLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightSemibold];
    _skipButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    _skipButton.layer.cornerRadius = 16;
    _skipButton.layer.cornerCurve = kCACornerCurveContinuous;
    _skipButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _skipButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    [_skipButton addTarget:self action:@selector(skipTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topChromeBar addSubview:_skipButton];

    // 底部指示器与按钮
    UIView *bottomBar = [UIView new];
    [self.view addSubview:bottomBar];

    NSMutableArray<UIView *> *dots = [NSMutableArray arrayWithCapacity:self.slides.count];
    NSMutableArray<MASConstraint *> *widths = [NSMutableArray arrayWithCapacity:self.slides.count];
    for (NSInteger i = 0; i < (NSInteger)self.slides.count; i++) {
        UIView *dot = [UIView new];
        dot.layer.cornerRadius = 3;
        dot.layer.cornerCurve = kCACornerCurveContinuous;
        dot.backgroundColor = (i == 0) ? SPTheme.brandGreenColor : [UIColor colorWithWhite:1.0 alpha:0.30];
        [dots addObject:dot];
        [dot mas_makeConstraints:^(MASConstraintMaker *make) {
            make.height.mas_equalTo(6);
            [widths addObject:make.width.mas_equalTo(i == 0 ? 24.0 : 6.0)];
        }];
    }
    _dotViews = dots;
    _dotWidthConstraints = widths;

    _dotsStack = [[UIStackView alloc] initWithArrangedSubviews:dots];
    _dotsStack.axis = UILayoutConstraintAxisHorizontal;
    _dotsStack.spacing = 6;
    _dotsStack.alignment = UIStackViewAlignmentCenter;
    [bottomBar addSubview:_dotsStack];

    _swipeHintLabel = [UILabel new];
    _swipeHintLabel.text = @"左右滑动浏览";
    _swipeHintLabel.font = [SPTheme fontOfSize:12 weight:UIFontWeightMedium];
    _swipeHintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.48];
    [bottomBar addSubview:_swipeHintLabel];

    _nextRoundButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _nextRoundButton.backgroundColor = UIColor.whiteColor;
    _nextRoundButton.tintColor = [UIColor sp_colorWithHex:0x0B0B0C];
    _nextRoundButton.layer.cornerRadius = 26;
    _nextRoundButton.layer.cornerCurve = kCACornerCurveCircular;
    [_nextRoundButton sp_setSymbol:@"arrow.right" size:19 weight:UIImageSymbolWeightBold animated:NO];
    [_nextRoundButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:_nextRoundButton];

    _finalCTAButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _finalCTAButton.backgroundColor = SPTheme.brandGreenColor;
    _finalCTAButton.layer.cornerRadius = 25;
    _finalCTAButton.layer.cornerCurve = kCACornerCurveContinuous;
    [_finalCTAButton setTitle:self.replayMode ? @"回到设置" : @"进入登录 / 注册" forState:UIControlStateNormal];
    [_finalCTAButton setTitleColor:[UIColor sp_colorWithHex:0x0B0B0C] forState:UIControlStateNormal];
    _finalCTAButton.titleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
    _finalCTAButton.alpha = 0;
    _finalCTAButton.hidden = YES;
    [_finalCTAButton addTarget:self action:@selector(proceedToNextStep) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:_finalCTAButton];

    [_collectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [_topChromeBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(8);
        make.left.right.equalTo(self.view);
        make.height.mas_equalTo(44);
    }];
    [_brandMark mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.topChromeBar).offset(24);
        make.centerY.equalTo(self.topChromeBar);
        make.size.mas_equalTo(CGSizeMake(28, 28));
    }];
    [brandTitle mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.brandMark.mas_right).offset(8);
        make.centerY.equalTo(self.brandMark);
    }];
    [_skipButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.topChromeBar).offset(-20);
        make.centerY.equalTo(self.topChromeBar);
        make.width.mas_greaterThanOrEqualTo(64);
        make.height.mas_equalTo(32);
    }];
    [bottomBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.view).offset(28);
        make.right.equalTo(self.view).offset(-28);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideBottom).offset(-24);
        make.height.mas_equalTo(86);
    }];
    [_dotsStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(bottomBar);
        make.left.equalTo(bottomBar);
    }];
    [_swipeHintLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(bottomBar);
        make.centerY.equalTo(self.nextRoundButton);
    }];
    [_nextRoundButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(bottomBar);
        make.bottom.equalTo(bottomBar);
        make.size.mas_equalTo(CGSizeMake(52, 52));
    }];
    [_finalCTAButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(bottomBar);
        make.height.mas_equalTo(50);
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
    CGSize target = self.collectionView.bounds.size;
    if (target.width > 0 && !CGSizeEqualToSize(layout.itemSize, target)) {
        layout.itemSize = target;
        [layout invalidateLayout];
    }
}

#pragma mark - Page Updates

- (void)updateControlsForPage:(NSInteger)page animated:(BOOL)animated {
    self.currentPage = page;
    BOOL isLast = (page >= (NSInteger)self.slides.count - 1);

    for (NSInteger i = 0; i < (NSInteger)self.dotViews.count; i++) {
        BOOL active = (i == page);
        self.dotViews[i].backgroundColor = active ? SPTheme.brandGreenColor : [UIColor colorWithWhite:1.0 alpha:0.30];
        self.dotWidthConstraints[i].mas_equalTo(active ? 24.0 : 6.0);
    }

    self.swipeHintLabel.text = isLast ? @"继续向右滑动或点击按钮" : @"左右滑动浏览";
    self.swipeHintLabel.hidden = isLast;
    self.finalCTAButton.hidden = NO;
    self.nextRoundButton.hidden = NO;

    void (^changes)(void) = ^{
        [self.view layoutIfNeeded];
        self.nextRoundButton.alpha = isLast ? 0.0 : 1.0;
        self.nextRoundButton.transform = isLast ? CGAffineTransformMakeScale(0.85, 0.85) : CGAffineTransformIdentity;
        self.finalCTAButton.alpha = isLast ? 1.0 : 0.0;
        self.finalCTAButton.transform = isLast ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, 10);
    };

    void (^completion)(BOOL) = ^(BOOL finished) {
        self.nextRoundButton.hidden = isLast;
        self.finalCTAButton.hidden = !isLast;
    };

    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.26
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:changes
                         completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

#pragma mark - Actions

- (void)skipTapped {
    [SPHaptics light];
    [self proceedToNextStep];
}

- (void)nextTapped {
    [SPHaptics light];
    NSInteger next = self.currentPage + 1;
    if (next < (NSInteger)self.slides.count) {
        CGFloat x = next * CGRectGetWidth(self.collectionView.bounds);
        [self.collectionView setContentOffset:CGPointMake(x, 0) animated:!UIAccessibilityIsReduceMotionEnabled()];
        [self updateControlsForPage:next animated:YES];
    } else {
        [self proceedToNextStep];
    }
}

- (void)proceedToNextStep {
    if (self.didProceed) return;
    self.didProceed = YES;
    [SPHaptics medium];

    if (self.replayMode) {
        if (self.presentingViewController) {
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            [self.navigationController popViewControllerAnimated:YES];
        }
        return;
    }

    [SceneDelegate setHasCompletedOnboarding:YES];
    [[SceneDelegate shared] transitionToAuthWelcomeAnimated:YES];
}

#pragma mark - UICollectionViewDataSource / UIScrollViewDelegate

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.slides.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SPOnboardingSlideCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[SPOnboardingSlideCell reuseId] forIndexPath:indexPath];
    [cell configureWithSlide:self.slides[indexPath.item]];
    return cell;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat w = CGRectGetWidth(scrollView.bounds);
    if (w <= 0) return;

    for (UICollectionViewCell *cell in self.collectionView.visibleCells) {
        if (![cell isKindOfClass:SPOnboardingSlideCell.class]) continue;
        NSIndexPath *indexPath = [self.collectionView indexPathForCell:cell];
        if (!indexPath) continue;
        CGFloat pageOrigin = indexPath.item * w;
        CGFloat normalized = (scrollView.contentOffset.x - pageOrigin) / w;
        [(SPOnboardingSlideCell *)cell applyParallaxOffset:normalized];
    }

    NSInteger targetPage = (NSInteger)llround(scrollView.contentOffset.x / w);
    targetPage = MIN(MAX(targetPage, 0), (NSInteger)self.slides.count - 1);
    if (targetPage != self.currentPage) {
        [SPHaptics selection];
        [self updateControlsForPage:targetPage animated:YES];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    CGFloat maxOffsetX = MAX(0, scrollView.contentSize.width - CGRectGetWidth(scrollView.bounds));
    if (self.currentPage == (NSInteger)self.slides.count - 1 && scrollView.contentOffset.x > maxOffsetX + 36.0) {
        [self proceedToNextStep];
    }
}

@end
