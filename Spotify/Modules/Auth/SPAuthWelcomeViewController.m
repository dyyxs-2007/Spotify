//
//  SPAuthWelcomeViewController.m
//  Spotify
//

#import "SPAuthWelcomeViewController.h"
#import "SPAuthViewController.h"
#import "SPNeteaseQRLoginViewController.h"
#import "SPBrandMarkView.h"
#import "SPGradientView.h"
#import "SPScaleButton.h"
#import "SPAuthService.h"
#import "SceneDelegate.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPAuthWelcomeViewController ()
@property (nonatomic, assign) SPAuthPresentationContext context;
@property (nonatomic, strong) SPScaleButton *backButton;
@property (nonatomic, strong) SPScaleButton *closeButton;
@property (nonatomic, strong) SPScaleButton *demoButton;
@property (nonatomic, strong) UIActivityIndicatorView *demoSpinner;
@property (nonatomic, assign) BOOL demoLoading;
@end

@implementation SPAuthWelcomeViewController

- (instancetype)init {
    return [self initWithContext:SPAuthPresentationContextGate];
}

- (instancetype)initWithContext:(SPAuthPresentationContext)context {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _context = context;
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor sp_colorWithHex:0x0E0E10];
    [self setupViews];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    BOOL canPop = (self.navigationController.viewControllers.count > 1);
    self.backButton.hidden = !canPop;
    self.closeButton.hidden = (self.context != SPAuthPresentationContextModal);
}

- (void)setupViews {
    // 顶部极淡柔和光晕，避免喧宾夺主
    SPGradientView *ambientGlow = [SPGradientView new];
    ambientGlow.colors = @[
        [SPTheme.brandGreenColor colorWithAlphaComponent:0.09],
        [[UIColor sp_colorWithHex:0x132A1F] colorWithAlphaComponent:0.06],
        [UIColor sp_colorWithHex:0x0E0E10],
    ];
    ambientGlow.locations = @[@0.0, @0.22, @0.48];
    [self.view addSubview:ambientGlow];

    // 顶部导航操作
    _backButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_backButton sp_setSymbol:@"chevron.left" size:19 weight:UIImageSymbolWeightSemibold animated:NO];
    _backButton.tintColor = UIColor.whiteColor;
    [_backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_backButton];

    _closeButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    _closeButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    _closeButton.layer.cornerRadius = 18;
    _closeButton.layer.cornerCurve = kCACornerCurveCircular;
    [_closeButton sp_setSymbol:@"xmark" size:15 weight:UIImageSymbolWeightSemibold animated:NO];
    _closeButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_closeButton];

    // 中央品牌与口号 Hero 区
    UIView *heroContainer = [UIView new];
    [self.view addSubview:heroContainer];

    SPBrandMarkView *brandMark = [[SPBrandMarkView alloc] initWithCircleColor:UIColor.whiteColor
                                                                    waveColor:[UIColor sp_colorWithHex:0x0E0E10]];
    brandMark.layer.shadowColor = SPTheme.brandGreenColor.CGColor;
    brandMark.layer.shadowOpacity = 0.22;
    brandMark.layer.shadowRadius = 24;
    brandMark.layer.shadowOffset = CGSizeZero;
    [heroContainer addSubview:brandMark];

    UILabel *headlineLabel = [UILabel new];
    NSMutableParagraphStyle *pStyle = [NSMutableParagraphStyle new];
    pStyle.alignment = NSTextAlignmentCenter;
    pStyle.lineSpacing = 4;
    headlineLabel.attributedText = [[NSAttributedString alloc] initWithString:@"数百万首歌曲。\n随时随地畅听。" attributes:@{
        NSParagraphStyleAttributeName: pStyle,
        NSFontAttributeName: [SPTheme fontOfSize:29 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: UIColor.whiteColor,
    }];
    headlineLabel.numberOfLines = 2;
    [heroContainer addSubview:headlineLabel];

    UILabel *subLabel = [UILabel new];
    subLabel.text = @"登录或免费注册，延续你的专属音乐品味";
    subLabel.font = [SPTheme fontOfSize:14 weight:UIFontWeightRegular];
    subLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.58];
    subLabel.textAlignment = NSTextAlignmentCenter;
    subLabel.numberOfLines = 2;
    [heroContainer addSubview:subLabel];

    // 底部柔和胶囊按钮区
    SPScaleButton *registerBtn = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    registerBtn.backgroundColor = SPTheme.brandGreenColor;
    registerBtn.layer.cornerRadius = 25;
    registerBtn.layer.cornerCurve = kCACornerCurveContinuous;
    [registerBtn setTitle:@"免费注册" forState:UIControlStateNormal];
    [registerBtn setTitleColor:[UIColor sp_colorWithHex:0x0B0B0C] forState:UIControlStateNormal];
    registerBtn.titleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
    [registerBtn addTarget:self action:@selector(registerTapped) forControlEvents:UIControlEventTouchUpInside];

    SPScaleButton *qrLoginBtn = [self makeOutlinePillWithTitle:@"网易云 App 扫码登录"
                                                         symbol:@"qrcode"
                                                         action:@selector(qrLoginTapped)];

    SPScaleButton *codeLoginBtn = [self makeOutlinePillWithTitle:@"验证码快速登录"
                                                           symbol:@"envelope.badge.shield.half.filled"
                                                           action:@selector(codeLoginTapped)];

    _demoButton = [self makeOutlinePillWithTitle:@"演示账号一键体验"
                                          symbol:@"sparkles"
                                          action:@selector(demoLoginTapped)];
    _demoSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _demoSpinner.color = UIColor.whiteColor;
    _demoSpinner.hidesWhenStopped = YES;
    _demoSpinner.userInteractionEnabled = NO;
    [_demoButton addSubview:_demoSpinner];

    SPScaleButton *passwordLoginBtn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [passwordLoginBtn setTitle:@"登录" forState:UIControlStateNormal];
    [passwordLoginBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    passwordLoginBtn.titleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
    [passwordLoginBtn addTarget:self action:@selector(passwordLoginTapped) forControlEvents:UIControlEventTouchUpInside];

    NSMutableArray<UIView *> *buttonViews = [@[registerBtn, qrLoginBtn, codeLoginBtn, _demoButton, passwordLoginBtn] mutableCopy];
    if (self.context == SPAuthPresentationContextGate) {
        UIButton *guestBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [guestBtn setTitle:@"先以游客身份逛逛" forState:UIControlStateNormal];
        [guestBtn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.48] forState:UIControlStateNormal];
        guestBtn.titleLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightMedium];
        [guestBtn addTarget:self action:@selector(guestTapped) forControlEvents:UIControlEventTouchUpInside];
        [guestBtn mas_makeConstraints:^(MASConstraintMaker *make) {
            make.height.mas_equalTo(34);
        }];
        [buttonViews addObject:guestBtn];
    }

    for (UIView *btn in @[registerBtn, qrLoginBtn, codeLoginBtn, _demoButton]) {
        [btn mas_makeConstraints:^(MASConstraintMaker *make) {
            make.height.mas_equalTo(48);
        }];
    }
    [passwordLoginBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(42);
    }];

    UIStackView *actionStack = [[UIStackView alloc] initWithArrangedSubviews:buttonViews];
    actionStack.axis = UILayoutConstraintAxisVertical;
    actionStack.spacing = 10;
    [self.view addSubview:actionStack];

    // Layout
    [ambientGlow mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [_backButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(8);
        make.left.equalTo(self.view).offset(10);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [_closeButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(12);
        make.right.equalTo(self.view).offset(-20);
        make.size.mas_equalTo(CGSizeMake(36, 36));
    }];
    [actionStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.view).offset(28);
        make.right.equalTo(self.view).offset(-28);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideBottom).offset(-22);
    }];
    [heroContainer mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.view).offset(28);
        make.right.equalTo(self.view).offset(-28);
        make.centerY.equalTo(self.view).multipliedBy(0.58);
    }];
    [brandMark mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.centerX.equalTo(heroContainer);
        make.size.mas_equalTo(CGSizeMake(62, 62));
    }];
    [headlineLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(brandMark.mas_bottom).offset(24);
        make.left.right.equalTo(heroContainer);
    }];
    [subLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(headlineLabel.mas_bottom).offset(12);
        make.left.right.bottom.equalTo(heroContainer);
    }];
    [_demoSpinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.demoButton).offset(-18);
        make.centerY.equalTo(self.demoButton);
    }];
}

- (SPScaleButton *)makeOutlinePillWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    SPScaleButton *btn = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    btn.layer.cornerRadius = 25;
    btn.layer.cornerCurve = kCACornerCurveContinuous;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightSemibold];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[SPTheme symbol:symbol size:17 weight:UIImageSymbolWeightMedium]];
    icon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.88];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.userInteractionEnabled = NO;
    [btn addSubview:icon];
    [icon mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(btn).offset(20);
        make.centerY.equalTo(btn);
        make.size.mas_equalTo(CGSizeMake(22, 22));
    }];
    return btn;
}

#pragma mark - Navigation & Actions

- (void)pushFormWithMode:(SPAuthMode)mode {
    [SPHaptics light];
    SPAuthViewController *form = [[SPAuthViewController alloc] initWithMode:mode context:self.context];
    form.authSuccessHandler = self.authSuccessHandler;
    [self.navigationController pushViewController:form animated:YES];
}

- (void)registerTapped { [self pushFormWithMode:SPAuthModeRegister]; }
- (void)qrLoginTapped {
    [SPHaptics light];
    SPNeteaseQRLoginViewController *qr = [[SPNeteaseQRLoginViewController alloc] initWithContext:self.context];
    qr.authSuccessHandler = self.authSuccessHandler;
    [self.navigationController pushViewController:qr animated:YES];
}
- (void)codeLoginTapped { [self pushFormWithMode:SPAuthModeCodeLogin]; }
- (void)passwordLoginTapped { [self pushFormWithMode:SPAuthModePasswordLogin]; }

- (void)backTapped {
    [SPHaptics light];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)closeTapped {
    [SPHaptics light];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)guestTapped {
    [SPHaptics light];
    [SceneDelegate setHasEnteredGuestMode:YES];
    [[SceneDelegate shared] transitionToMainAppAnimated:YES];
}

- (void)demoLoginTapped {
    if (self.demoLoading) return;
    self.demoLoading = YES;
    self.demoButton.enabled = NO;
    [self.demoSpinner startAnimating];
    [SPHaptics medium];

    __weak typeof(self) weakSelf = self;
    [[SPAuthService shared] loginWithAccount:@"demo@spotify.local"
                                    password:@"Spotify123"
                                  completion:^(SPUser *user, NSError *error) {
        weakSelf.demoLoading = NO;
        weakSelf.demoButton.enabled = YES;
        [weakSelf.demoSpinner stopAnimating];
        if (!user || error) {
            [SPToast showMessage:error.localizedDescription ?: @"演示账号登录失败"];
            return;
        }
        [SPToast showMessage:[NSString stringWithFormat:@"欢迎，%@", user.nickname]];
        if (weakSelf.context == SPAuthPresentationContextGate) {
            [[SceneDelegate shared] transitionToMainAppAnimated:YES];
        } else {
            void (^handler)(void) = [weakSelf.authSuccessHandler copy];
            [weakSelf.navigationController dismissViewControllerAnimated:YES completion:handler];
        }
    }];
}

@end
