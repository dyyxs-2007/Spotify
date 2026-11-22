//
//  SPAuthViewController.m
//  Spotify
//

#import "SPAuthViewController.h"
#import "SPGradientView.h"
#import "SPScaleButton.h"
#import "SPAuthService.h"
#import "SPLocalAuthProvider.h"
#import "SceneDelegate.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPAuthViewController () <UITextFieldDelegate>
@property (nonatomic, assign) SPAuthMode mode;
@property (nonatomic, assign) SPAuthPresentationContext context;

@property (nonatomic, strong) UILabel *navTitleLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UITextField *accountField;
@property (nonatomic, strong) UIView *accountBox;

@property (nonatomic, strong) UIView *codeGroup;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UIView *codeBox;
@property (nonatomic, strong) SPScaleButton *sendCodeButton;
@property (nonatomic, strong) UIButton *codeHintButton;
@property (nonatomic, copy, nullable) NSString *lastDebugCode;

@property (nonatomic, strong) UIView *passwordGroup;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIView *passwordBox;
@property (nonatomic, strong) SPScaleButton *eyeButton;
@property (nonatomic, strong) UIView *strengthContainer;
@property (nonatomic, copy) NSArray<UIView *> *strengthBars;
@property (nonatomic, strong) UILabel *strengthLabel;

@property (nonatomic, strong) UIView *nicknameGroup;
@property (nonatomic, strong) UITextField *nicknameField;

@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) SPScaleButton *submitButton;
@property (nonatomic, strong) UIActivityIndicatorView *submitSpinner;
@property (nonatomic, strong) UIButton *switchModeButton;

@property (nonatomic, strong, nullable) NSTimer *countdownTimer;
@property (nonatomic, assign) NSInteger countdownSeconds;
@property (nonatomic, assign) BOOL submitting;
@end

@implementation SPAuthViewController

- (instancetype)init {
    return [self initWithMode:SPAuthModePasswordLogin context:SPAuthPresentationContextModal];
}

- (instancetype)initWithMode:(SPAuthMode)mode context:(SPAuthPresentationContext)context {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _mode = mode;
        _context = context;
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)dealloc {
    [self.countdownTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor sp_colorWithHex:0x121212];
    [self setupViews];
    [self registerKeyboardNotifications];
    [self configureForCurrentMode];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.accountField becomeFirstResponder];
}

- (void)setupViews {
    SPGradientView *ambient = [SPGradientView new];
    ambient.colors = @[[UIColor colorWithWhite:1.0 alpha:0.04], [UIColor sp_colorWithHex:0x121212]];
    ambient.locations = @[@0.0, @0.32];
    [self.view addSubview:ambient];

    // 简洁顶栏
    UIView *navBar = [UIView new];
    [self.view addSubview:navBar];

    SPScaleButton *backButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [backButton sp_setSymbol:@"chevron.left" size:19 weight:UIImageSymbolWeightSemibold animated:NO];
    backButton.tintColor = UIColor.whiteColor;
    [backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [navBar addSubview:backButton];

    _navTitleLabel = [UILabel new];
    _navTitleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
    _navTitleLabel.textColor = UIColor.whiteColor;
    [navBar addSubview:_navTitleLabel];

    _scrollView = [UIScrollView new];
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:_scrollView];

    _contentView = [UIView new];
    [_scrollView addSubview:_contentView];
    [_contentView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)]];

    // 1. 账号组
    _accountField = [self makeTextFieldWithPlaceholder:@"如 name@domain.com 或 13800138000"
                                          keyboardType:UIKeyboardTypeEmailAddress
                                                secure:NO];
    _accountField.returnKeyType = UIReturnKeyNext;
    _accountBox = [self wrapField:_accountField trailingView:nil];
    UIView *accountGroup = [self fieldGroupWithTitle:@"邮箱或手机号"
                                             caption:(self.mode == SPAuthModeRegister ? @"我们将通过短信/邮件验证码校验账号安全性" : nil)
                                                 box:_accountBox];

    // 2. 验证码组
    _codeField = [self makeTextFieldWithPlaceholder:@"输入 6 位数字验证码"
                                       keyboardType:UIKeyboardTypeNumberPad
                                             secure:NO];
    _sendCodeButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_sendCodeButton setTitle:@"获取验证码" forState:UIControlStateNormal];
    _sendCodeButton.titleLabel.font = [SPTheme monospacedDigitFontOfSize:13 weight:UIFontWeightSemibold];
    _sendCodeButton.tintColor = SPTheme.brandGreenColor;
    [_sendCodeButton addTarget:self action:@selector(sendCodeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_sendCodeButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.mas_greaterThanOrEqualTo(86);
        make.height.mas_equalTo(36);
    }];
    _codeBox = [self wrapField:_codeField trailingView:_sendCodeButton];
    _codeGroup = [self fieldGroupWithTitle:@"验证码" caption:nil box:_codeBox];

    _codeHintButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _codeHintButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _codeHintButton.titleLabel.font = [SPTheme monospacedDigitFontOfSize:13 weight:UIFontWeightSemibold];
    [_codeHintButton setTitleColor:SPTheme.brandGreenColor forState:UIControlStateNormal];
    _codeHintButton.backgroundColor = [SPTheme.brandGreenColor colorWithAlphaComponent:0.12];
    _codeHintButton.layer.cornerRadius = 8;
    _codeHintButton.layer.cornerCurve = kCACornerCurveContinuous;
    _codeHintButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _codeHintButton.layer.borderColor = [SPTheme.brandGreenColor colorWithAlphaComponent:0.32].CGColor;
    _codeHintButton.hidden = YES;
    [_codeHintButton addTarget:self action:@selector(fillDebugCodeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_codeHintButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(34);
    }];

    // 3. 密码组 + 强度条
    _passwordField = [self makeTextFieldWithPlaceholder:@"至少 8 位，包含字母与数字"
                                            keyboardType:UIKeyboardTypeDefault
                                                  secure:YES];
    _passwordField.returnKeyType = (self.mode == SPAuthModeRegister) ? UIReturnKeyNext : UIReturnKeyDone;
    [_passwordField addTarget:self action:@selector(passwordChanged) forControlEvents:UIControlEventEditingChanged];

    _eyeButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_eyeButton sp_setSymbol:@"eye.slash" size:17 weight:UIFontWeightRegular animated:NO];
    _eyeButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.62];
    [_eyeButton addTarget:self action:@selector(toggleSecureTapped) forControlEvents:UIControlEventTouchUpInside];
    [_eyeButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    _passwordBox = [self wrapField:_passwordField trailingView:_eyeButton];

    _strengthContainer = [UIView new];
    NSMutableArray *bars = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        UIView *bar = [UIView new];
        bar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        bar.layer.cornerRadius = 2;
        [bars addObject:bar];
    }
    _strengthBars = bars;
    UIStackView *barStack = [[UIStackView alloc] initWithArrangedSubviews:bars];
    barStack.axis = UILayoutConstraintAxisHorizontal;
    barStack.distribution = UIStackViewDistributionFillEqually;
    barStack.spacing = 6;
    [_strengthContainer addSubview:barStack];

    _strengthLabel = [UILabel new];
    _strengthLabel.font = [SPTheme fontOfSize:12 weight:UIFontWeightMedium];
    _strengthLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    _strengthLabel.text = @"密码至少 8 位且包含字母与数字";
    [_strengthContainer addSubview:_strengthLabel];

    [barStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.strengthContainer);
        make.height.mas_equalTo(3.5);
    }];
    [_strengthLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(barStack.mas_bottom).offset(6);
        make.left.right.bottom.equalTo(self.strengthContainer);
    }];

    _passwordGroup = [self fieldGroupWithTitle:@"密码" caption:nil box:_passwordBox];

    // 4. 昵称组
    _nicknameField = [self makeTextFieldWithPlaceholder:@"将展示在你的个人主页"
                                            keyboardType:UIKeyboardTypeDefault
                                                  secure:NO];
    _nicknameField.returnKeyType = UIReturnKeyDone;
    UIView *nicknameBox = [self wrapField:_nicknameField trailingView:nil];
    _nicknameGroup = [self fieldGroupWithTitle:@"如何称呼你？（选填）" caption:nil box:nicknameBox];

    _errorLabel = [UILabel new];
    _errorLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightMedium];
    _errorLabel.textColor = [UIColor sp_colorWithHex:0xF87171];
    _errorLabel.numberOfLines = 0;
    _errorLabel.hidden = YES;

    UIStackView *formStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        accountGroup, _codeGroup, _codeHintButton, _passwordGroup, _strengthContainer, _nicknameGroup, _errorLabel
    ]];
    formStack.axis = UILayoutConstraintAxisVertical;
    formStack.spacing = 22;
    [formStack setCustomSpacing:8 afterView:_codeGroup];
    [formStack setCustomSpacing:10 afterView:_passwordGroup];
    [_contentView addSubview:formStack];

    // 标志性白色胶囊按钮
    _submitButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _submitButton.backgroundColor = UIColor.whiteColor;
    _submitButton.layer.cornerRadius = 25;
    _submitButton.layer.cornerCurve = kCACornerCurveContinuous;
    [_submitButton setTitleColor:[UIColor sp_colorWithHex:0x0B0B0C] forState:UIControlStateNormal];
    _submitButton.titleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
    [_submitButton addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_submitButton];

    _submitSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _submitSpinner.color = [UIColor sp_colorWithHex:0x0B0B0C];
    _submitSpinner.hidesWhenStopped = YES;
    _submitSpinner.userInteractionEnabled = NO;
    [_submitButton addSubview:_submitSpinner];

    _switchModeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _switchModeButton.titleLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightMedium];
    _switchModeButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    [_switchModeButton addTarget:self action:@selector(switchModeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_switchModeButton];

    // Constraints
    [ambient mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [navBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(48);
    }];
    [backButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(navBar).offset(10);
        make.bottom.equalTo(navBar);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [_navTitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(navBar);
        make.centerY.equalTo(backButton);
    }];
    [_scrollView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(navBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
    [_contentView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.scrollView);
        make.width.equalTo(self.scrollView);
    }];
    [formStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.contentView).offset(24);
        make.left.equalTo(self.contentView).offset(24);
        make.right.equalTo(self.contentView).offset(-24);
    }];
    [_submitButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(formStack.mas_bottom).offset(34);
        make.centerX.equalTo(self.contentView);
        make.width.mas_equalTo(208);
        make.height.mas_equalTo(50);
    }];
    [_submitSpinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.submitButton);
    }];
    [_switchModeButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.submitButton.mas_bottom).offset(18);
        make.centerX.equalTo(self.contentView);
        make.height.mas_equalTo(36);
        make.bottom.equalTo(self.contentView).offset(-32);
    }];
}

- (UIView *)fieldGroupWithTitle:(NSString *)title caption:(nullable NSString *)caption box:(UIView *)box {
    UIView *group = [UIView new];
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [SPTheme fontOfSize:18 weight:UIFontWeightBold];
    label.textColor = UIColor.whiteColor;
    [group addSubview:label];
    [group addSubview:box];

    [label mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(group);
    }];
    [box mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(label.mas_bottom).offset(10);
        make.left.right.equalTo(group);
        if (!caption.length) make.bottom.equalTo(group);
    }];

    if (caption.length > 0) {
        UILabel *capLabel = [UILabel new];
        capLabel.text = caption;
        capLabel.font = [SPTheme fontOfSize:12 weight:UIFontWeightRegular];
        capLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        capLabel.numberOfLines = 0;
        [group addSubview:capLabel];
        [capLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(box.mas_bottom).offset(8);
            make.left.right.bottom.equalTo(group);
        }];
    }
    return group;
}

- (UITextField *)makeTextFieldWithPlaceholder:(NSString *)placeholder
                                 keyboardType:(UIKeyboardType)keyboardType
                                       secure:(BOOL)secure {
    UITextField *field = [UITextField new];
    field.textColor = UIColor.whiteColor;
    field.tintColor = SPTheme.brandGreenColor;
    field.font = [SPTheme fontOfSize:15 weight:UIFontWeightMedium];
    field.keyboardType = keyboardType;
    field.secureTextEntry = secure;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.delegate = self;
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
                                                                attributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.35],
        NSFontAttributeName: [SPTheme fontOfSize:14 weight:UIFontWeightRegular],
    }];
    return field;
}

- (UIView *)wrapField:(UITextField *)field trailingView:(nullable UIView *)trailingView {
    UIView *box = [UIView new];
    box.backgroundColor = [UIColor sp_colorWithHex:0x222226];
    box.layer.cornerRadius = 10;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.layer.borderWidth = 1.0;
    box.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    [box addSubview:field];

    [box mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(52);
    }];

    if (trailingView) {
        [box addSubview:trailingView];
        [trailingView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(box).offset(-10);
            make.centerY.equalTo(box);
        }];
        [field mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(box).offset(16);
            make.right.equalTo(trailingView.mas_left).offset(-8);
            make.top.bottom.equalTo(box);
        }];
    } else {
        [field mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(box).offset(16);
            make.right.equalTo(box).offset(-16);
            make.top.bottom.equalTo(box);
        }];
    }
    return box;
}

- (void)configureForCurrentMode {
    BOOL showCode = (self.mode == SPAuthModeCodeLogin || self.mode == SPAuthModeRegister);
    BOOL showPassword = (self.mode == SPAuthModePasswordLogin || self.mode == SPAuthModeRegister);
    BOOL isRegister = (self.mode == SPAuthModeRegister);

    self.codeGroup.hidden = !showCode;
    if (!showCode) {
        self.codeHintButton.hidden = YES;
    }
    self.passwordGroup.hidden = !showPassword;
    self.strengthContainer.hidden = !isRegister;
    self.nicknameGroup.hidden = !isRegister;

    if (self.mode == SPAuthModePasswordLogin) {
        self.navTitleLabel.text = @"登录";
        [self.submitButton setTitle:@"登录" forState:UIControlStateNormal];
        [self.switchModeButton setTitle:@"改用验证码登录" forState:UIControlStateNormal];
    } else if (self.mode == SPAuthModeCodeLogin) {
        self.navTitleLabel.text = @"验证码登录";
        [self.submitButton setTitle:@"登录" forState:UIControlStateNormal];
        [self.switchModeButton setTitle:@"改用密码登录" forState:UIControlStateNormal];
    } else {
        self.navTitleLabel.text = @"创建账号";
        [self.submitButton setTitle:@"创建账号" forState:UIControlStateNormal];
        [self.switchModeButton setTitle:@"已有账号？去登录" forState:UIControlStateNormal];
    }
}

- (void)showError:(nullable NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = (message.length == 0);
}

#pragma mark - UITextFieldDelegate & Smooth Focus Transition

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    [self showError:nil];
    UIView *box = textField.superview;
    [UIView animateWithDuration:0.18 animations:^{
        box.backgroundColor = [UIColor sp_colorWithHex:0x2A2A30];
    }];
    box.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.50].CGColor;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    UIView *box = textField.superview;
    [UIView animateWithDuration:0.18 animations:^{
        box.backgroundColor = [UIColor sp_colorWithHex:0x222226];
    }];
    box.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.accountField) {
        if (!self.codeGroup.hidden) [self.codeField becomeFirstResponder];
        else if (!self.passwordGroup.hidden) [self.passwordField becomeFirstResponder];
    } else if (textField == self.passwordField && !self.nicknameGroup.hidden) {
        [self.nicknameField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
        [self submitTapped];
    }
    return YES;
}

#pragma mark - Keyboard

- (void)registerKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted));
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = overlap;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
}

- (void)dismissKeyboard { [self.view endEditing:YES]; }

#pragma mark - Actions

- (void)backTapped {
    [SPHaptics light];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)switchModeTapped {
    [SPHaptics light];
    SPAuthMode nextMode = (self.mode == SPAuthModeCodeLogin || self.mode == SPAuthModeRegister)
        ? SPAuthModePasswordLogin
        : SPAuthModeCodeLogin;
    SPAuthViewController *replacement = [[SPAuthViewController alloc] initWithMode:nextMode context:self.context];
    replacement.authSuccessHandler = self.authSuccessHandler;

    NSMutableArray *stack = [self.navigationController.viewControllers mutableCopy];
    if (stack.count > 0) {
        [stack replaceObjectAtIndex:stack.count - 1 withObject:replacement];
        [self.navigationController setViewControllers:stack animated:YES];
    }
}

- (void)toggleSecureTapped {
    [SPHaptics light];
    self.passwordField.secureTextEntry = !self.passwordField.secureTextEntry;
    NSString *sym = self.passwordField.secureTextEntry ? @"eye.slash" : @"eye";
    [self.eyeButton sp_setSymbol:sym size:17 weight:UIImageSymbolWeightRegular animated:YES];
}

- (void)passwordChanged {
    if (self.mode != SPAuthModeRegister) return;
    NSString *pwd = self.passwordField.text ?: @"";
    NSInteger level = [SPLocalAuthProvider passwordStrengthFor:pwd];
    UIColor *activeColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    NSString *tip = @"密码至少 8 位且包含字母和数字";
    if (pwd.length > 0 && level == 0) {
        activeColor = [UIColor sp_colorWithHex:0xF87171];
        tip = @"强度不足：需满 8 位并包含字母与数字";
    } else if (level == 1) {
        activeColor = [UIColor sp_colorWithHex:0xF59B23];
        tip = @"密码强度：一般";
    } else if (level == 2) {
        activeColor = SPTheme.brandGreenColor;
        tip = @"密码强度：良好";
    } else if (level >= 3) {
        activeColor = SPTheme.brandGreenColor;
        tip = @"密码强度：极强";
    }

    for (NSInteger i = 0; i < (NSInteger)self.strengthBars.count; i++) {
        BOOL lit = (pwd.length > 0) && (level == 0 ? i == 0 : i < level);
        self.strengthBars[i].backgroundColor = lit ? activeColor : [UIColor colorWithWhite:1.0 alpha:0.12];
    }
    self.strengthLabel.text = tip;
    self.strengthLabel.textColor = (pwd.length > 0 && level == 0) ? activeColor : [UIColor colorWithWhite:1.0 alpha:0.55];
}

- (void)sendCodeTapped {
    [SPHaptics light];
    [self showError:nil];
    NSString *account = self.accountField.text ?: @"";
    SPAuthCodePurpose purpose = (self.mode == SPAuthModeRegister) ? SPAuthCodePurposeRegister : SPAuthCodePurposeLogin;

    __weak typeof(self) weakSelf = self;
    [[SPAuthService shared] sendVerificationCodeToAccount:account
                                                  purpose:purpose
                                               completion:^(BOOL success, NSString *debugCode, NSError *error) {
        if (!success || error) {
            [weakSelf showError:error.localizedDescription ?: @"验证码发送失败"];
            return;
        }
        [weakSelf startCountdown];
        [weakSelf.codeField becomeFirstResponder];
        if (debugCode.length > 0) {
            weakSelf.lastDebugCode = debugCode;
            NSString *hintTitle = [NSString stringWithFormat:@"  验证码已发送：%@  ·  点击此处一键填入  ", debugCode];
            [weakSelf.codeHintButton setTitle:hintTitle forState:UIControlStateNormal];
            weakSelf.codeHintButton.hidden = NO;
            [SPToast showMessage:[NSString stringWithFormat:@"测试验证码：%@（5分钟内有效，也可点击下方提示一键填入）", debugCode]
                        duration:6.5
                        position:SPToastPositionTop];
        } else {
            [SPToast showMessage:@"验证码已发送，请注意查收"
                        duration:4.0
                        position:SPToastPositionTop];
        }
    }];
}

- (void)fillDebugCodeTapped {
    if (self.lastDebugCode.length == 0) return;
    [SPHaptics selection];
    self.codeField.text = self.lastDebugCode;
    [self showError:nil];
}

- (void)startCountdown {
    [self.countdownTimer invalidate];
    self.countdownSeconds = 60;
    self.sendCodeButton.enabled = NO;
    self.sendCodeButton.alpha = 0.55;
    [self.sendCodeButton setTitle:@"60s 后重发" forState:UIControlStateNormal];

    __weak typeof(self) weakSelf = self;
    self.countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        weakSelf.countdownSeconds -= 1;
        if (weakSelf.countdownSeconds <= 0) {
            [timer invalidate];
            weakSelf.countdownTimer = nil;
            weakSelf.sendCodeButton.enabled = YES;
            weakSelf.sendCodeButton.alpha = 1.0;
            [weakSelf.sendCodeButton setTitle:@"获取验证码" forState:UIControlStateNormal];
        } else {
            [weakSelf.sendCodeButton setTitle:[NSString stringWithFormat:@"%lds 后重发", (long)weakSelf.countdownSeconds]
                                     forState:UIControlStateNormal];
        }
    }];
}

- (void)setSubmitting:(BOOL)submitting {
    _submitting = submitting;
    self.submitButton.enabled = !submitting;
    self.submitButton.alpha = submitting ? 0.72 : 1.0;
    if (submitting) {
        [self.submitButton setTitle:@"" forState:UIControlStateNormal];
        [self.submitSpinner startAnimating];
    } else {
        [self.submitSpinner stopAnimating];
        [self.submitButton setTitle:(self.mode == SPAuthModeRegister) ? @"创建账号" : @"登录" forState:UIControlStateNormal];
    }
}

- (void)submitTapped {
    if (self.submitting) return;
    [SPHaptics medium];
    [self dismissKeyboard];
    [self showError:nil];

    NSString *account = self.accountField.text ?: @"";
    NSString *password = self.passwordField.text ?: @"";
    NSString *code = self.codeField.text ?: @"";
    NSString *nickname = self.nicknameField.text;

    self.submitting = YES;
    __weak typeof(self) weakSelf = self;
    void (^done)(SPUser *, NSError *) = ^(SPUser *user, NSError *error) {
        weakSelf.submitting = NO;
        if (error || !user) {
            [weakSelf showError:error.localizedDescription ?: @"操作失败"];
            return;
        }
        [SPToast showMessage:[NSString stringWithFormat:@"欢迎回来，%@", user.nickname]];
        if (weakSelf.context == SPAuthPresentationContextGate) {
            [[SceneDelegate shared] transitionToMainAppAnimated:YES];
        } else {
            void (^handler)(void) = [weakSelf.authSuccessHandler copy];
            [weakSelf.navigationController dismissViewControllerAnimated:YES completion:handler];
        }
    };

    if (self.mode == SPAuthModePasswordLogin) {
        [[SPAuthService shared] loginWithAccount:account password:password completion:done];
    } else if (self.mode == SPAuthModeCodeLogin) {
        [[SPAuthService shared] loginWithAccount:account verificationCode:code completion:done];
    } else {
        [[SPAuthService shared] registerWithAccount:account
                                           password:password
                                   verificationCode:code
                                           nickname:nickname
                                         completion:done];
    }
}

@end
