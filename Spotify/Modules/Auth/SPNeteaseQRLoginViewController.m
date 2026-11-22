//
//  SPNeteaseQRLoginViewController.m
//  Spotify
//

#import "SPNeteaseQRLoginViewController.h"
#import "SPNeteaseAuthProvider.h"
#import "SPAuthService.h"
#import "SPGradientView.h"
#import "SPScaleButton.h"
#import "SceneDelegate.h"
#import "SPHaptics.h"
#import "SPToast.h"
#import <CoreImage/CoreImage.h>

@interface SPNeteaseQRLoginViewController ()
@property (nonatomic, assign) SPAuthPresentationContext context;
@property (nonatomic, strong) SPNeteaseAuthProvider *provider;
@property (nonatomic, copy, nullable) NSString *unikey;
@property (nonatomic, strong, nullable) NSTimer *pollTimer;
@property (nonatomic, assign) BOOL fetchingProfile;

@property (nonatomic, strong) UIView *qrCardView;
@property (nonatomic, strong) UIImageView *qrImageView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, strong) UIView *expiredOverlay;
@property (nonatomic, strong) UILabel *statusTitleLabel;
@property (nonatomic, strong) UILabel *statusDescLabel;
@property (nonatomic, strong) SPScaleButton *refreshButton;
@end

@implementation SPNeteaseQRLoginViewController

- (instancetype)init {
    return [self initWithContext:SPAuthPresentationContextModal];
}

- (instancetype)initWithContext:(SPAuthPresentationContext)context {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _context = context;
        _provider = [SPNeteaseAuthProvider new];
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)dealloc {
    [self stopPolling];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor sp_colorWithHex:0x0E0E10];
    [self setupViews];
    [self loadNewQRCode];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopPolling];
}

- (void)setupViews {
    SPGradientView *ambient = [SPGradientView new];
    ambient.colors = @[
        [SPTheme.brandGreenColor colorWithAlphaComponent:0.08],
        [UIColor sp_colorWithHex:0x0E0E10],
    ];
    ambient.locations = @[@0.0, @0.45];
    [self.view addSubview:ambient];

    UIView *navBar = [UIView new];
    [self.view addSubview:navBar];

    SPScaleButton *backBtn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [backBtn sp_setSymbol:@"chevron.left" size:19 weight:UIImageSymbolWeightSemibold animated:NO];
    backBtn.tintColor = UIColor.whiteColor;
    [backBtn addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [navBar addSubview:backBtn];

    UILabel *navTitle = [UILabel new];
    navTitle.text = @"网易云扫码登录";
    navTitle.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
    navTitle.textColor = UIColor.whiteColor;
    [navBar addSubview:navTitle];

    // 居中扫码白卡
    _qrCardView = [UIView new];
    _qrCardView.backgroundColor = UIColor.whiteColor;
    _qrCardView.layer.cornerRadius = 20;
    _qrCardView.layer.cornerCurve = kCACornerCurveContinuous;
    _qrCardView.layer.shadowColor = SPTheme.brandGreenColor.CGColor;
    _qrCardView.layer.shadowOpacity = 0.16;
    _qrCardView.layer.shadowRadius = 28;
    _qrCardView.layer.shadowOffset = CGSizeZero;
    [self.view addSubview:_qrCardView];

    _qrImageView = [UIImageView new];
    _qrImageView.contentMode = UIViewContentModeScaleAspectFit;
    _qrImageView.layer.magnificationFilter = kCAFilterNearest;
    [_qrCardView addSubview:_qrImageView];

    _loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _loadingSpinner.color = [UIColor sp_colorWithHex:0x121212];
    _loadingSpinner.hidesWhenStopped = YES;
    [_qrCardView addSubview:_loadingSpinner];

    _expiredOverlay = [UIView new];
    _expiredOverlay.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.84];
    _expiredOverlay.layer.cornerRadius = 14;
    _expiredOverlay.layer.cornerCurve = kCACornerCurveContinuous;
    _expiredOverlay.hidden = YES;
    [_expiredOverlay addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(refreshTapped)]];
    [_qrCardView addSubview:_expiredOverlay];

    UILabel *expiredLabel = [UILabel new];
    expiredLabel.text = @"二维码已过期\n轻触重新生成";
    expiredLabel.font = [SPTheme fontOfSize:14 weight:UIFontWeightSemibold];
    expiredLabel.textColor = UIColor.whiteColor;
    expiredLabel.textAlignment = NSTextAlignmentCenter;
    expiredLabel.numberOfLines = 2;
    [_expiredOverlay addSubview:expiredLabel];

    _statusTitleLabel = [UILabel new];
    _statusTitleLabel.text = @"正在生成安全二维码...";
    _statusTitleLabel.font = [SPTheme fontOfSize:20 weight:UIFontWeightBold];
    _statusTitleLabel.textColor = UIColor.whiteColor;
    _statusTitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_statusTitleLabel];

    _statusDescLabel = [UILabel new];
    _statusDescLabel.text = @"打开手机网易云音乐 App，在侧边栏右上角扫一扫授权登录，登录态将自动同步到你的音乐库";
    _statusDescLabel.font = [SPTheme fontOfSize:13.5 weight:UIFontWeightRegular];
    _statusDescLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.60];
    _statusDescLabel.textAlignment = NSTextAlignmentCenter;
    _statusDescLabel.numberOfLines = 0;
    [self.view addSubview:_statusDescLabel];

    _refreshButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _refreshButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    _refreshButton.layer.cornerRadius = 22;
    _refreshButton.layer.cornerCurve = kCACornerCurveContinuous;
    _refreshButton.layer.borderWidth = 1.0;
    _refreshButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    [_refreshButton setTitle:@"刷新二维码" forState:UIControlStateNormal];
    [_refreshButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _refreshButton.titleLabel.font = [SPTheme fontOfSize:14 weight:UIFontWeightSemibold];
    [_refreshButton addTarget:self action:@selector(refreshTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_refreshButton];

    [ambient mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [navBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(48);
    }];
    [backBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(navBar).offset(10);
        make.bottom.equalTo(navBar);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [navTitle mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(navBar);
        make.centerY.equalTo(backBtn);
    }];
    [_qrCardView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.view);
        make.centerY.equalTo(self.view).offset(-62);
        make.size.mas_equalTo(CGSizeMake(224, 224));
    }];
    [_qrImageView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.qrCardView).inset(16);
    }];
    [_loadingSpinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.qrCardView);
    }];
    [_expiredOverlay mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.qrCardView).inset(8);
    }];
    [expiredLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.expiredOverlay);
    }];
    [_statusTitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.qrCardView.mas_bottom).offset(28);
        make.left.equalTo(self.view).offset(28);
        make.right.equalTo(self.view).offset(-28);
    }];
    [_statusDescLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.statusTitleLabel.mas_bottom).offset(10);
        make.left.equalTo(self.view).offset(32);
        make.right.equalTo(self.view).offset(-32);
    }];
    [_refreshButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.statusDescLabel.mas_bottom).offset(28);
        make.centerX.equalTo(self.view);
        make.width.mas_equalTo(156);
        make.height.mas_equalTo(44);
    }];
}

#pragma mark - QR Code Generation & Polling

- (void)loadNewQRCode {
    [self stopPolling];
    self.unikey = nil;
    self.fetchingProfile = NO;
    self.expiredOverlay.hidden = YES;
    self.qrImageView.image = nil;
    [self.loadingSpinner startAnimating];
    self.statusTitleLabel.text = @"正在生成安全二维码...";
    self.statusTitleLabel.textColor = UIColor.whiteColor;

    __weak typeof(self) weakSelf = self;
    [self.provider createQRCodeWithCompletion:^(NSString *unikey, NSString *qrURL, NSError *error) {
        [weakSelf.loadingSpinner stopAnimating];
        if (error || unikey.length == 0 || qrURL.length == 0) {
            weakSelf.statusTitleLabel.text = @"二维码获取失败";
            [SPToast showMessage:error.localizedDescription ?: @"无法连接到网易云登录服务"];
            return;
        }
        weakSelf.unikey = unikey;
        weakSelf.qrImageView.image = [weakSelf qrImageFromString:qrURL size:384];
        weakSelf.statusTitleLabel.text = @"请打开网易云音乐 App 扫一扫";
        [weakSelf startPolling];
    }];
}

- (nullable UIImage *)qrImageFromString:(NSString *)string size:(CGFloat)size {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *output = filter.outputImage;
    if (!output) return nil;

    CIContext *ciContext = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [ciContext createCGImage:output fromRect:output.extent];
    if (!cgImage) return nil;

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextSetInterpolationQuality(ctx.CGContext, kCGInterpolationNone);
        CGContextTranslateCTM(ctx.CGContext, 0, size);
        CGContextScaleCTM(ctx.CGContext, 1.0, -1.0);
        CGContextDrawImage(ctx.CGContext, CGRectMake(0, 0, size, size), cgImage);
    }];
    CGImageRelease(cgImage);
    return result;
}

- (void)startPolling {
    [self stopPolling];
    __weak typeof(self) weakSelf = self;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf pollQRStatus];
    }];
}

- (void)stopPolling {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
}

- (void)pollQRStatus {
    if (self.unikey.length == 0 || self.fetchingProfile) return;
    NSString *currentKey = self.unikey;
    __weak typeof(self) weakSelf = self;
    [self.provider checkQRStatusForKey:currentKey
                            completion:^(NSInteger statusCode, NSString *message, NSString *cookie, NSError *error) {
        if (![weakSelf.unikey isEqualToString:currentKey] || error) return;
        if (statusCode == 800) {
            [weakSelf stopPolling];
            weakSelf.expiredOverlay.hidden = NO;
            weakSelf.statusTitleLabel.text = @"二维码已过期";
            weakSelf.statusTitleLabel.textColor = [UIColor sp_colorWithHex:0xF59B23];
        } else if (statusCode == 802) {
            weakSelf.statusTitleLabel.text = @"已扫码，请在手机上确认登录";
            weakSelf.statusTitleLabel.textColor = SPTheme.brandGreenColor;
        } else if (statusCode == 803 && cookie.length > 0) {
            [weakSelf stopPolling];
            [weakSelf completeQRLoginWithCookie:cookie];
        }
    }];
}

- (void)completeQRLoginWithCookie:(NSString *)cookie {
    self.fetchingProfile = YES;
    self.statusTitleLabel.text = @"授权成功，正在同步账号...";
    self.statusTitleLabel.textColor = SPTheme.brandGreenColor;
    [SPHaptics medium];

    __weak typeof(self) weakSelf = self;
    [self.provider fetchUserProfileWithCookie:cookie completion:^(SPUser *user, NSError *error) {
        weakSelf.fetchingProfile = NO;
        if (error || !user) {
            [SPToast showMessage:error.localizedDescription ?: @"同步账号资料失败"];
            weakSelf.statusTitleLabel.text = @"同步账号失败，请重试";
            return;
        }
        [[SPAuthService shared] adoptAuthenticatedUser:user];
        [SPToast showMessage:[NSString stringWithFormat:@"欢迎回来，%@", user.nickname]];

        if (weakSelf.context == SPAuthPresentationContextGate) {
            [[SceneDelegate shared] transitionToMainAppAnimated:YES];
        } else {
            void (^handler)(void) = [weakSelf.authSuccessHandler copy];
            [weakSelf.navigationController dismissViewControllerAnimated:YES completion:handler];
        }
    }];
}

#pragma mark - Actions

- (void)backTapped {
    [SPHaptics light];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)refreshTapped {
    [SPHaptics light];
    [self loadNewQRCode];
}

@end
