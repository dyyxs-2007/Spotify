//
//  SPSideDrawerViewController.m
//  Spotify
//

#import "SPSideDrawerViewController.h"
#import "SPUserAvatarButton.h"
#import "SPScaleButton.h"
#import "SPToggleSwitch.h"
#import "SPAuthService.h"
#import "SPLibraryStore.h"
#import "SPHistoryStore.h"
#import "SPPlayerService.h"
#import "SceneDelegate.h"
#import "SPHaptics.h"
#import "SPToast.h"

#pragma mark - Drawer Highlight Row Button

@interface SPDrawerRowButton : SPScaleButton
@end

@implementation SPDrawerRowButton

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    UIColor *target = highlighted ? SPTheme.highlightColor : UIColor.clearColor;
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.backgroundColor = target;
    } else {
        [UIView animateWithDuration:0.12
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.backgroundColor = target;
        } completion:nil];
    }
}

@end

#pragma mark - SPSideDrawerViewController

@interface SPSideDrawerViewController () <SPAuthObserver>
@property (nonatomic, strong) SPUserAvatarButton *avatarButton;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UILabel *planBadgeLabel;

@property (nonatomic, strong) UIView *statsCard;
@property (nonatomic, strong) UILabel *likedCountLabel;
@property (nonatomic, strong) UILabel *playlistCountLabel;
@property (nonatomic, strong) UILabel *followedCountLabel;

@property (nonatomic, strong) UILabel *historySubtitleLabel;
@property (nonatomic, strong) UILabel *sleepSubtitleLabel;
@property (nonatomic, strong) SPToggleSwitch *themeSwitch;

@property (nonatomic, strong) SPScaleButton *switchAccountButton;
@property (nonatomic, strong) SPScaleButton *authActionButton;
@end

@implementation SPSideDrawerViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)dealloc {
    [[SPAuthService shared] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.elevatedColor;
    [self setupViews];
    [[SPAuthService shared] addObserver:self];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(reloadStatsAndBadges) name:SPLibraryDidUpdateNotification object:nil];
    [nc addObserver:self selector:@selector(reloadStatsAndBadges) name:SPHistoryDidUpdateNotification object:nil];
    [nc addObserver:self selector:@selector(reloadSleepTimerBadge) name:SPPlayerSleepTimerDidUpdateNotification object:nil];
    [nc addObserver:self selector:@selector(themeDidChange) name:SPThemeDidChangeNotification object:nil];
    [self refreshContent];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshContent];
}

- (void)refreshContent {
    [self reloadUserState];
    [self reloadStatsAndBadges];
    [self reloadSleepTimerBadge];
    [self.themeSwitch setOn:SPTheme.isDarkMode animated:NO];
}

- (void)setupViews {
    UIView *rightBorder = [UIView new];
    rightBorder.backgroundColor = SPTheme.separatorColor;
    [self.view addSubview:rightBorder];

    // 顶部个人资料区
    SPDrawerRowButton *profileCard = [SPDrawerRowButton buttonWithType:UIButtonTypeCustom];
    profileCard.isStatic = YES;
    [profileCard addTarget:self action:@selector(profileTapped) forControlEvents:UIControlEventTouchUpInside];
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
    _planBadgeLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return (tc.userInterfaceStyle == UIUserInterfaceStyleLight) ? UIColor.whiteColor : UIColor.blackColor;
    }];
    _planBadgeLabel.backgroundColor = SPTheme.accentColor;
    _planBadgeLabel.textAlignment = NSTextAlignmentCenter;
    _planBadgeLabel.layer.cornerRadius = 9;
    _planBadgeLabel.layer.cornerCurve = kCACornerCurveContinuous;
    _planBadgeLabel.clipsToBounds = YES;
    [profileCard addSubview:_planBadgeLabel];

    // 个人音乐库三栏实时概览卡
    _statsCard = [UIView new];
    _statsCard.backgroundColor = SPTheme.highlightColor;
    _statsCard.layer.cornerRadius = 12;
    _statsCard.layer.cornerCurve = kCACornerCurveContinuous;
    _statsCard.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _statsCard.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:[SPTheme resolvedTraitCollectionForView:self.view]].CGColor;
    [self.view addSubview:_statsCard];

    UILabel *likedVal = nil;
    UIView *likedItem = [self statColumnWithTitle:@"已点赞" valueLabel:&likedVal action:@selector(likedStatTapped)];
    _likedCountLabel = likedVal;

    UILabel *plVal = nil;
    UIView *plItem = [self statColumnWithTitle:@"自建歌单" valueLabel:&plVal action:@selector(libraryStatTapped)];
    _playlistCountLabel = plVal;

    UILabel *followVal = nil;
    UIView *followItem = [self statColumnWithTitle:@"关注歌手" valueLabel:&followVal action:@selector(libraryStatTapped)];
    _followedCountLabel = followVal;

    UIStackView *statsStack = [[UIStackView alloc] initWithArrangedSubviews:@[likedItem, plItem, followItem]];
    statsStack.axis = UILayoutConstraintAxisHorizontal;
    statsStack.distribution = UIStackViewDistributionFillEqually;
    [_statsCard addSubview:statsStack];

    // 滚动菜单区
    UIScrollView *menuScroll = [UIScrollView new];
    menuScroll.showsVerticalScrollIndicator = NO;
    menuScroll.alwaysBounceVertical = YES;
    [self.view addSubview:menuScroll];

    UIView *rowActivity = [self menuRowWithIcon:@"bolt"
                                        title:@"新动态"
                                subtitleLabel:nil
                                 trailingView:nil
                                       action:@selector(activityTapped)];
    UILabel *histSub = nil;
    UIView *rowHistory = [self menuRowWithIcon:@"clock.arrow.circlepath"
                                       title:@"收听历史"
                               subtitleLabel:&histSub
                                trailingView:nil
                                      action:@selector(historyTapped)];
    _historySubtitleLabel = histSub;

    UILabel *sleepSub = nil;
    UIView *rowSleep = [self menuRowWithIcon:@"moon.zzz"
                                     title:@"睡眠定时"
                             subtitleLabel:&sleepSub
                              trailingView:nil
                                    action:@selector(sleepTimerTapped)];
    _sleepSubtitleLabel = sleepSub;

    _themeSwitch = [SPToggleSwitch new];
    [_themeSwitch addTarget:self action:@selector(themeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    UIView *rowTheme = [self menuRowWithIcon:@"circle.lefthalf.filled"
                                     title:@"深色外观"
                             subtitleLabel:nil
                              trailingView:_themeSwitch
                                    action:nil];

    UIView *rowSettings = [self menuRowWithIcon:@"gearshape"
                                        title:@"设置与隐私"
                                subtitleLabel:nil
                                 trailingView:nil
                                       action:@selector(settingsTapped)];

    UIStackView *menuStack = [[UIStackView alloc] initWithArrangedSubviews:@[rowActivity, rowHistory, rowSleep, rowTheme, rowSettings]];
    menuStack.axis = UILayoutConstraintAxisVertical;
    menuStack.spacing = 4;
    [menuScroll addSubview:menuStack];

    // 底部账号操作区
    _switchAccountButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _switchAccountButton.backgroundColor = SPTheme.highlightColor;
    _switchAccountButton.layer.cornerRadius = 21;
    _switchAccountButton.layer.cornerCurve = kCACornerCurveContinuous;
    [_switchAccountButton setTitle:@"切换账号" forState:UIControlStateNormal];
    [_switchAccountButton setTitleColor:SPTheme.textPrimaryColor forState:UIControlStateNormal];
    _switchAccountButton.titleLabel.font = [SPTheme fontOfSize:14 weight:UIFontWeightSemibold];
    [_switchAccountButton addTarget:self action:@selector(switchAccountTapped) forControlEvents:UIControlEventTouchUpInside];

    _authActionButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    _authActionButton.layer.cornerRadius = 23;
    _authActionButton.layer.cornerCurve = kCACornerCurveContinuous;
    _authActionButton.titleLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightBold];
    [_authActionButton addTarget:self action:@selector(authActionTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *footerStack = [[UIStackView alloc] initWithArrangedSubviews:@[_switchAccountButton, _authActionButton]];
    footerStack.axis = UILayoutConstraintAxisVertical;
    footerStack.spacing = 10;
    [self.view addSubview:footerStack];

    [rightBorder mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.right.equalTo(self.view);
        make.width.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [profileCard mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(14);
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
        make.top.equalTo(self.avatarButton.mas_bottom).offset(12);
        make.left.equalTo(self.avatarButton);
        make.height.mas_equalTo(18);
        make.width.mas_greaterThanOrEqualTo(88);
        make.bottom.equalTo(profileCard).offset(-12);
    }];
    [_statsCard mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(profileCard.mas_bottom).offset(4);
        make.left.equalTo(self.view).offset(18);
        make.right.equalTo(self.view).offset(-18);
        make.height.mas_equalTo(62);
    }];
    [statsStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.statsCard);
    }];
    [menuScroll mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.statsCard.mas_bottom).offset(12);
        make.left.right.equalTo(self.view);
        make.bottom.equalTo(footerStack.mas_top).offset(-12);
    }];
    [menuStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(menuScroll);
        make.width.equalTo(menuScroll);
    }];
    [_switchAccountButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(42);
    }];
    [_authActionButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(46);
    }];
    [footerStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.view).offset(20);
        make.right.equalTo(self.view).offset(-20);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideBottom).offset(-20);
    }];
}

- (UIView *)statColumnWithTitle:(NSString *)title valueLabel:(UILabel * __autoreleasing *)outValueLabel action:(SEL)action {
    SPScaleButton *btn = [SPScaleButton buttonWithType:UIButtonTypeCustom];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    UILabel *val = [UILabel new];
    val.font = [SPTheme monospacedDigitFontOfSize:17 weight:UIFontWeightBold];
    val.textColor = SPTheme.textPrimaryColor;
    val.textAlignment = NSTextAlignmentCenter;
    val.text = @"0";
    val.userInteractionEnabled = NO;

    UILabel *cap = [UILabel new];
    cap.font = [SPTheme fontOfSize:11 weight:UIFontWeightMedium];
    cap.textColor = SPTheme.textSecondaryColor;
    cap.textAlignment = NSTextAlignmentCenter;
    cap.text = title;
    cap.userInteractionEnabled = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[val, cap]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 2;
    stack.userInteractionEnabled = NO;
    [btn addSubview:stack];
    [stack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(btn);
        make.left.greaterThanOrEqualTo(btn).offset(4);
        make.right.lessThanOrEqualTo(btn).offset(-4);
    }];
    if (outValueLabel) *outValueLabel = val;
    return btn;
}

- (UIView *)menuRowWithIcon:(NSString *)symbol
                      title:(NSString *)title
              subtitleLabel:(UILabel * __autoreleasing _Nullable * _Nullable)outSubtitleLabel
               trailingView:(nullable UIView *)trailingView
                     action:(nullable SEL)action {
    UIView *row = nil;
    if (action) {
        SPDrawerRowButton *btn = [SPDrawerRowButton buttonWithType:UIButtonTypeCustom];
        btn.isStatic = YES;
        [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        row = btn;
    } else {
        row = [UIView new];
    }

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[SPTheme symbol:symbol size:19 weight:UIImageSymbolWeightMedium]];
    iconView.tintColor = SPTheme.textPrimaryColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.userInteractionEnabled = NO;
    [row addSubview:iconView];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = title;
    titleLabel.font = [SPTheme fontOfSize:15.5 weight:UIFontWeightMedium];
    titleLabel.textColor = SPTheme.textPrimaryColor;
    titleLabel.userInteractionEnabled = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 2;
    stack.userInteractionEnabled = NO;
    if (outSubtitleLabel) {
        UILabel *sub = [UILabel new];
        sub.font = [SPTheme monospacedDigitFontOfSize:12 weight:UIFontWeightRegular];
        sub.textColor = SPTheme.textSecondaryColor;
        sub.userInteractionEnabled = NO;
        [stack addArrangedSubview:sub];
        *outSubtitleLabel = sub;
    }
    [row addSubview:stack];

    if (trailingView) {
        [trailingView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [trailingView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [row addSubview:trailingView];
        [trailingView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(row).offset(-20);
            make.centerY.equalTo(row);
        }];
    }

    [row mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(outSubtitleLabel ? 58 : 48);
    }];
    [iconView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(row).offset(20);
        make.centerY.equalTo(row);
        make.size.mas_equalTo(CGSizeMake(24, 24));
    }];
    [stack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(iconView.mas_right).offset(16);
        make.right.equalTo(trailingView ? trailingView.mas_left : row).offset(-12);
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
        self.switchAccountButton.hidden = NO;

        self.authActionButton.backgroundColor = UIColor.clearColor;
        self.authActionButton.layer.borderWidth = 1.0;
        self.authActionButton.layer.borderColor = [[SPTheme.textPrimaryColor colorWithAlphaComponent:0.25] resolvedColorWithTraitCollection:[SPTheme resolvedTraitCollectionForView:self.view]].CGColor;
        [self.authActionButton setTitle:@"退出登录" forState:UIControlStateNormal];
        [self.authActionButton setTitleColor:SPTheme.textPrimaryColor forState:UIControlStateNormal];
    } else {
        self.nameLabel.text = @"未登录";
        self.subLabel.text = @"点击登录或免费注册";
        self.planBadgeLabel.hidden = YES;
        self.switchAccountButton.hidden = YES;

        self.authActionButton.backgroundColor = SPTheme.accentColor;
        self.authActionButton.layer.borderWidth = 0;
        [self.authActionButton setTitle:@"登录 / 注册" forState:UIControlStateNormal];
        UIColor *onAccent = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return (tc.userInterfaceStyle == UIUserInterfaceStyleLight) ? UIColor.whiteColor : [UIColor sp_colorWithHex:0x0B0B0C];
        }];
        [self.authActionButton setTitleColor:onAccent forState:UIControlStateNormal];
    }
}

- (void)reloadStatsAndBadges {
    SPLibraryStore *lib = [SPLibraryStore shared];
    self.likedCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)lib.likedTracks.count];
    self.playlistCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)lib.userPlaylists.count];
    self.followedCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)lib.followedArtists.count];

    NSUInteger histCount = [SPHistoryStore shared].recentTracks.count;
    self.historySubtitleLabel.text = histCount > 0
        ? [NSString stringWithFormat:@"最近播放 %lu 首", (unsigned long)histCount]
        : @"暂无播放记录";
}

- (void)reloadSleepTimerBadge {
    SPPlayerService *player = [SPPlayerService shared];
    if (!player.isSleepTimerActive) {
        self.sleepSubtitleLabel.text = @"未开启";
        self.sleepSubtitleLabel.textColor = SPTheme.textSecondaryColor;
        return;
    }
    NSInteger sec = (NSInteger)ceil(player.sleepTimerRemaining);
    NSInteger m = sec / 60;
    NSInteger s = sec % 60;
    self.sleepSubtitleLabel.text = [NSString stringWithFormat:@"剩余 %02ld:%02ld 后暂停", (long)m, (long)s];
    self.sleepSubtitleLabel.textColor = SPTheme.accentColor;
}

- (void)themeDidChange {
    [self.themeSwitch setOn:SPTheme.isDarkMode animated:YES];
    UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self.view];
    self.statsCard.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:tc].CGColor;
    if ([SPAuthService shared].isLoggedIn) {
        self.authActionButton.layer.borderColor = [[SPTheme.textPrimaryColor colorWithAlphaComponent:0.25] resolvedColorWithTraitCollection:tc].CGColor;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self.view];
        self.statsCard.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:tc].CGColor;
        if ([SPAuthService shared].isLoggedIn) {
            self.authActionButton.layer.borderColor = [[SPTheme.textPrimaryColor colorWithAlphaComponent:0.25] resolvedColorWithTraitCollection:tc].CGColor;
        }
    }
}

#pragma mark - Actions

- (void)profileTapped {
    [SPHaptics light];
    SPDrawerMenuAction action = [SPAuthService shared].isLoggedIn ? SPDrawerMenuActionSettings : SPDrawerMenuActionAuth;
    if (self.menuSelectionHandler) self.menuSelectionHandler(action);
}

- (void)likedStatTapped {
    [SPHaptics light];
    if (self.menuSelectionHandler) self.menuSelectionHandler(SPDrawerMenuActionLikedSongs);
}

- (void)libraryStatTapped {
    [SPHaptics light];
    if (self.menuSelectionHandler) self.menuSelectionHandler(SPDrawerMenuActionLibrary);
}

- (void)activityTapped {
    [SPHaptics light];
    if (self.menuSelectionHandler) self.menuSelectionHandler(SPDrawerMenuActionActivity);
}

- (void)historyTapped {
    [SPHaptics light];
    if (self.menuSelectionHandler) self.menuSelectionHandler(SPDrawerMenuActionHistory);
}

- (void)settingsTapped {
    [SPHaptics light];
    if (self.menuSelectionHandler) self.menuSelectionHandler(SPDrawerMenuActionSettings);
}

- (void)switchAccountTapped {
    [SPHaptics light];
    if (self.menuSelectionHandler) self.menuSelectionHandler(SPDrawerMenuActionSwitchAccount);
}

- (void)themeSwitchChanged:(SPToggleSwitch *)sender {
    [SPHaptics light];
    [SPTheme applyInterfaceStyle:(sender.isOn ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight) animated:YES];
}

- (void)sleepTimerTapped {
    [SPHaptics light];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"睡眠定时关闭"
                                                                   message:@"计时结束后将自动为你暂停音乐播放"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;

    NSArray<NSNumber *> *durations = @[@15, @30, @45, @60];
    for (NSNumber *mins in durations) {
        NSInteger m = mins.integerValue;
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%ld 分钟后暂停", (long)m]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [[SPPlayerService shared] setSleepTimerMinutes:m];
            [SPToast showMessage:[NSString stringWithFormat:@"已开启睡眠定时：%ld 分钟后暂停播放", (long)m]];
        }]];
    }
    if ([SPPlayerService shared].isSleepTimerActive) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"关闭当前定时"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [[SPPlayerService shared] setSleepTimerMinutes:0];
            [SPToast showMessage:@"已取消睡眠定时"];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)authActionTapped {
    [SPHaptics medium];
    if ([SPAuthService shared].isLoggedIn) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"退出登录"
                                                                       message:@"退出后将停止当前播放并返回登录欢迎页"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
        sheet.view.tintColor = SPTheme.accentColor;
        [sheet addAction:[UIAlertAction actionWithTitle:@"退出登录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [[SPAuthService shared] logout];
            [SceneDelegate setHasEnteredGuestMode:NO];
            [[SceneDelegate shared] transitionToAuthWelcomeAnimated:YES];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [SPTheme configurePopoverForViewController:sheet sourceView:self.authActionButton presentingVC:self];
        [self presentViewController:sheet animated:YES completion:nil];
    } else {
        if (self.menuSelectionHandler) self.menuSelectionHandler(SPDrawerMenuActionAuth);
    }
}

#pragma mark - SPAuthObserver

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    [self refreshContent];
}

@end
