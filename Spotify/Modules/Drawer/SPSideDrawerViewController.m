//
//  SPSideDrawerViewController.m
//  Spotify
//

#import "SPSideDrawerViewController.h"
#import "SPUserAvatarButton.h"
#import "SPScaleButton.h"
#import "SPAuthService.h"
#import "SceneDelegate.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPSideDrawerViewController () <SPAuthObserver>
@property (nonatomic, strong) SPUserAvatarButton *avatarButton;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UILabel *planBadgeLabel;
@property (nonatomic, strong) SPScaleButton *authActionButton;
@end

@implementation SPSideDrawerViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.elevatedColor;
    [self setupViews];
    [[SPAuthService shared] addObserver:self];
    [self reloadUserState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshContent];
}

- (void)refreshContent {
    [self reloadUserState];
}

- (void)setupViews {
    UIView *rightBorder = [UIView new];
    rightBorder.backgroundColor = SPTheme.separatorColor;
    [self.view addSubview:rightBorder];

    // 顶部个人资料区
    UIView *profileCard = [UIView new];
    profileCard.userInteractionEnabled = YES;
    [profileCard addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileTapped)]];
    [self.view addSubview:profileCard];

    _avatarButton = [[SPUserAvatarButton alloc] initWithDiameter:48];
    _avatarButton.userInteractionEnabled = NO;
    [profileCard addSubview:_avatarButton];

    _nameLabel = [UILabel new];
    _nameLabel.font = [SPTheme fontOfSize:20 weight:UIFontWeightBold];
    _nameLabel.textColor = SPTheme.textPrimaryColor;
    [profileCard addSubview:_nameLabel];

    _subLabel = [UILabel new];
    _subLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightRegular];
    _subLabel.textColor = SPTheme.textSecondaryColor;
    [profileCard addSubview:_subLabel];

    _planBadgeLabel = [UILabel new];
    _planBadgeLabel.font = [SPTheme fontOfSize:11 weight:UIFontWeightBold];
    _planBadgeLabel.textColor = UIColor.blackColor;
    _planBadgeLabel.backgroundColor = SPTheme.brandGreenColor;
    _planBadgeLabel.textAlignment = NSTextAlignmentCenter;
    _planBadgeLabel.layer.cornerRadius = 9;
    _planBadgeLabel.layer.cornerCurve = kCACornerCurveContinuous;
    _planBadgeLabel.clipsToBounds = YES;
    [profileCard addSubview:_planBadgeLabel];

    UIView *divider = [UIView new];
    divider.backgroundColor = SPTheme.separatorColor;
    [self.view addSubview:divider];

    // 菜单项
    UIView *rowActivity = [self menuRowWithIcon:@"bolt" title:@"新动态" subtitle:nil tag:SPDrawerMenuActionActivity];
    UIView *rowHistory = [self menuRowWithIcon:@"clock.arrow.circlepath" title:@"收听历史" subtitle:nil tag:SPDrawerMenuActionHistory];
    UIView *rowSettings = [self menuRowWithIcon:@"gearshape" title:@"设置与隐私" subtitle:nil tag:SPDrawerMenuActionSettings];

    UIStackView *menuStack = [[UIStackView alloc] initWithArrangedSubviews:@[rowActivity, rowHistory, rowSettings]];
    menuStack.axis = UILayoutConstraintAxisVertical;
    menuStack.spacing = 6;
    [self.view addSubview:menuStack];

    // 底部账号按钮
    _authActionButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _authActionButton.layer.cornerRadius = 23;
    _authActionButton.layer.cornerCurve = kCACornerCurveContinuous;
    _authActionButton.titleLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightBold];
    [_authActionButton addTarget:self action:@selector(authActionTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_authActionButton];

    [rightBorder mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.right.equalTo(self.view);
        make.width.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [profileCard mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(16);
        make.left.right.equalTo(self.view);
    }];
    [_avatarButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(profileCard).offset(4);
        make.left.equalTo(profileCard).offset(20);
        make.size.mas_equalTo(CGSizeMake(48, 48));
    }];
    [_nameLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.avatarButton).offset(2);
        make.left.equalTo(self.avatarButton.mas_right).offset(14);
        make.right.equalTo(profileCard).offset(-16);
    }];
    [_subLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.nameLabel.mas_bottom).offset(4);
        make.left.right.equalTo(self.nameLabel);
    }];
    [_planBadgeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.avatarButton.mas_bottom).offset(14);
        make.left.equalTo(self.avatarButton);
        make.height.mas_equalTo(18);
        make.width.mas_greaterThanOrEqualTo(88);
        make.bottom.equalTo(profileCard).offset(-14);
    }];
    [divider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(profileCard.mas_bottom);
        make.left.equalTo(self.view).offset(20);
        make.right.equalTo(self.view).offset(-20);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [menuStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(divider.mas_bottom).offset(16);
        make.left.right.equalTo(self.view);
    }];
    [_authActionButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.view).offset(20);
        make.right.equalTo(self.view).offset(-20);
        make.height.mas_equalTo(46);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideBottom).offset(-24);
    }];
}

- (UIView *)menuRowWithIcon:(NSString *)symbol title:(NSString *)title subtitle:(nullable NSString *)subtitle tag:(SPDrawerMenuAction)actionTag {
    SPScaleButton *row = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    row.tag = actionTag;
    [row addTarget:self action:@selector(menuRowTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[SPTheme symbol:symbol size:19 weight:UIImageSymbolWeightRegular]];
    iconView.tintColor = SPTheme.textPrimaryColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.userInteractionEnabled = NO;
    [row addSubview:iconView];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = title;
    titleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightMedium];
    titleLabel.textColor = SPTheme.textPrimaryColor;
    titleLabel.userInteractionEnabled = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 2;
    stack.userInteractionEnabled = NO;
    if (subtitle.length > 0) {
        UILabel *sub = [UILabel new];
        sub.text = subtitle;
        sub.font = [SPTheme fontOfSize:12 weight:UIFontWeightRegular];
        sub.textColor = SPTheme.textSecondaryColor;
        [stack addArrangedSubview:sub];
    }
    [row addSubview:stack];

    [row mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(subtitle.length > 0 ? 60 : 52);
    }];
    [iconView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(row).offset(20);
        make.centerY.equalTo(row);
        make.size.mas_equalTo(CGSizeMake(24, 24));
    }];
    [stack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(iconView.mas_right).offset(16);
        make.right.equalTo(row).offset(-16);
        make.centerY.equalTo(row);
    }];
    return row;
}

#pragma mark - Reload

- (void)reloadUserState {
    SPAuthService *auth = [SPAuthService shared];
    if (auth.isLoggedIn) {
        SPUser *u = auth.currentUser;
        self.nameLabel.text = u.nickname;
        self.subLabel.text = u.account;
        self.planBadgeLabel.hidden = NO;
        self.planBadgeLabel.text = [NSString stringWithFormat:@"  %@  ", u.planName ?: @"Premium"];

        self.authActionButton.backgroundColor = UIColor.clearColor;
        self.authActionButton.layer.borderWidth = 1.0;
        self.authActionButton.layer.borderColor = [[SPTheme.textPrimaryColor colorWithAlphaComponent:0.25] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        [self.authActionButton setTitle:@"退出登录" forState:UIControlStateNormal];
        [self.authActionButton setTitleColor:SPTheme.textPrimaryColor forState:UIControlStateNormal];
    } else {
        self.nameLabel.text = @"未登录";
        self.subLabel.text = @"点击登录或免费注册";
        self.planBadgeLabel.hidden = YES;

        self.authActionButton.backgroundColor = SPTheme.brandGreenColor;
        self.authActionButton.layer.borderWidth = 0;
        [self.authActionButton setTitle:@"登录 / 注册" forState:UIControlStateNormal];
        [self.authActionButton setTitleColor:[UIColor sp_colorWithHex:0x0B0B0C] forState:UIControlStateNormal];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] && [SPAuthService shared].isLoggedIn) {
        self.authActionButton.layer.borderColor = [[SPTheme.textPrimaryColor colorWithAlphaComponent:0.25] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    }
}

#pragma mark - Actions

- (void)profileTapped {
    [SPHaptics light];
    SPDrawerMenuAction action = [SPAuthService shared].isLoggedIn ? SPDrawerMenuActionSettings : SPDrawerMenuActionAuth;
    if (self.menuSelectionHandler) self.menuSelectionHandler(action);
}

- (void)menuRowTapped:(UIButton *)sender {
    [SPHaptics light];
    if (self.menuSelectionHandler) self.menuSelectionHandler((SPDrawerMenuAction)sender.tag);
}

- (void)authActionTapped {
    [SPHaptics medium];
    if ([SPAuthService shared].isLoggedIn) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"退出登录"
                                                                       message:@"退出后将返回欢迎登录界面"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
        sheet.view.tintColor = SPTheme.accentColor;
        [sheet addAction:[UIAlertAction actionWithTitle:@"退出登录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [[SPAuthService shared] logout];
            [SceneDelegate setHasEnteredGuestMode:NO];
            [[SceneDelegate shared] transitionToAuthWelcomeAnimated:YES];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:sheet animated:YES completion:nil];
    } else {
        if (self.menuSelectionHandler) self.menuSelectionHandler(SPDrawerMenuActionAuth);
    }
}

#pragma mark - SPAuthObserver

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    [self reloadUserState];
}

@end
