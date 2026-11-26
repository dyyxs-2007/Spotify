//
//  SPSettingsViewController.m
//  Spotify
//

#import "SPSettingsViewController.h"
#import "SPScaleButton.h"
#import "SPToggleSwitch.h"
#import "SPOnboardingViewController.h"
#import "SPAuthService.h"
#import "SPPlayerService.h"
#import "SPAudioCacheManager.h"
#import "SPMusicRepository.h"
#import "SPMockMusicSource.h"
#import "SPNeteaseMusicSource.h"
#import "SPNeteaseSession.h"
#import "SPLocalAuthProvider.h"
#import "SPNeteaseAuthProvider.h"
#import "SPRootViewController.h"
#import "UIImage+SPDominantColor.h"
#import "SceneDelegate.h"
#import "SPHaptics.h"
#import "SPToast.h"

typedef NS_ENUM(NSInteger, SPSettingsAccessoryType) {
    SPSettingsAccessoryTypeNone = 0,
    SPSettingsAccessoryTypeDisclosure,
    SPSettingsAccessoryTypeSwitch,
    SPSettingsAccessoryTypeBadgeText,
};

#pragma mark - Row / Section Models

@interface SPSettingsRow : NSObject
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong) UIColor *iconTintColor;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, strong) UIColor *titleColor;
@property (nonatomic, assign) SPSettingsAccessoryType accessoryType;
@property (nonatomic, copy, nullable) NSString *trailingText;
@property (nonatomic, assign) BOOL switchOn;
@property (nonatomic, copy, nullable) void (^switchHandler)(BOOL isOn);
@property (nonatomic, copy, nullable) void (^action)(void);
@end

@implementation SPSettingsRow
+ (instancetype)rowWithIcon:(NSString *)icon
                  iconColor:(UIColor *)iconColor
                      title:(NSString *)title
                   subtitle:(nullable NSString *)subtitle {
    SPSettingsRow *r = [SPSettingsRow new];
    r.iconName = icon;
    r.iconTintColor = iconColor ?: SPTheme.accentColor;
    r.title = title;
    r.subtitle = subtitle;
    r.titleColor = SPTheme.textPrimaryColor;
    return r;
}
@end

@interface SPSettingsSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<SPSettingsRow *> *rows;
@end

@implementation SPSettingsSection
@end

#pragma mark - Spacious Custom Settings Cell

@interface SPSettingsCell : UITableViewCell
@property (nonatomic, strong) UIView *iconContainer;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) SPToggleSwitch *toggleSwitch;
@property (nonatomic, strong) UILabel *trailingLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, copy, nullable) void (^switchHandler)(BOOL isOn);
@end

@implementation SPSettingsCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = SPTheme.elevatedColor;
        UIView *selected = [UIView new];
        selected.backgroundColor = SPTheme.highlightColor;
        self.selectedBackgroundView = selected;

        _iconContainer = [UIView new];
        _iconContainer.layer.cornerRadius = 7;
        _iconContainer.layer.cornerCurve = kCACornerCurveContinuous;
        [self.contentView addSubview:_iconContainer];

        _iconView = [UIImageView new];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconContainer addSubview:_iconView];

        _titleLabel = [UILabel new];
        _titleLabel.font = [SPTheme fontOfSize:15.5 weight:UIFontWeightSemibold];
        _titleLabel.textColor = SPTheme.textPrimaryColor;
        _titleLabel.numberOfLines = 0;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [SPTheme monospacedDigitFontOfSize:12.5 weight:UIFontWeightRegular];
        _subtitleLabel.textColor = SPTheme.textSecondaryColor;
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.lineBreakStrategy = NSLineBreakStrategyStandard;

        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 3;
        [self.contentView addSubview:textStack];

        _toggleSwitch = [SPToggleSwitch new];
        _toggleSwitch.onTintColor = SPTheme.accentColor;
        [_toggleSwitch addTarget:self action:@selector(switchValueChanged:) forControlEvents:UIControlEventValueChanged];
        [_toggleSwitch setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_toggleSwitch setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _trailingLabel = [UILabel new];
        _trailingLabel.font = [SPTheme monospacedDigitFontOfSize:13 weight:UIFontWeightMedium];
        _trailingLabel.textColor = SPTheme.textSecondaryColor;
        _trailingLabel.textAlignment = NSTextAlignmentRight;
        [_trailingLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_trailingLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _chevronView = [[UIImageView alloc] initWithImage:[SPTheme symbol:@"chevron.right" size:13 weight:UIImageSymbolWeightSemibold]];
        _chevronView.tintColor = SPTheme.textTertiaryColor;
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        [_chevronView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UIStackView *trailingStack = [[UIStackView alloc] initWithArrangedSubviews:@[_trailingLabel, _chevronView, _toggleSwitch]];
        trailingStack.axis = UILayoutConstraintAxisHorizontal;
        trailingStack.alignment = UIStackViewAlignmentCenter;
        trailingStack.spacing = 8;
        [trailingStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:trailingStack];

        [_iconContainer mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self.contentView).offset(16);
            make.centerY.equalTo(self.contentView);
            make.size.mas_equalTo(CGSizeMake(34, 34));
        }];
        [_iconView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.center.equalTo(self.iconContainer);
            make.size.mas_equalTo(CGSizeMake(17, 17));
        }];
        [_toggleSwitch mas_makeConstraints:^(MASConstraintMaker *make) {
            make.size.mas_equalTo(CGSizeMake(51, 31));
        }];
        [trailingStack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(self.contentView).offset(-16);
            make.centerY.equalTo(self.contentView);
        }];
        [textStack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self.iconContainer.mas_right).offset(14);
            make.right.lessThanOrEqualTo(trailingStack.mas_left).offset(-12);
            make.top.equalTo(self.contentView).offset(14);
            make.bottom.equalTo(self.contentView).offset(-14);
            make.height.mas_greaterThanOrEqualTo(32);
        }];
    }
    return self;
}

- (void)configureWithRow:(SPSettingsRow *)row {
    self.iconContainer.backgroundColor = [row.iconTintColor colorWithAlphaComponent:0.15];
    self.iconView.image = [SPTheme symbol:row.iconName size:16 weight:UIImageSymbolWeightSemibold];
    self.iconView.tintColor = row.iconTintColor;

    self.titleLabel.text = row.title;
    self.titleLabel.textColor = row.titleColor;
    self.subtitleLabel.text = row.subtitle;
    self.subtitleLabel.hidden = (row.subtitle.length == 0);

    self.toggleSwitch.hidden = (row.accessoryType != SPSettingsAccessoryTypeSwitch);
    self.chevronView.hidden = (row.accessoryType != SPSettingsAccessoryTypeDisclosure);
    self.trailingLabel.hidden = (row.trailingText.length == 0);
    self.trailingLabel.text = row.trailingText;

    if (row.accessoryType == SPSettingsAccessoryTypeSwitch) {
        self.toggleSwitch.onTintColor = SPTheme.accentColor;
        [self.toggleSwitch setOn:row.switchOn animated:NO];
        self.switchHandler = row.switchHandler;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        self.switchHandler = nil;
        self.selectionStyle = row.action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
}

- (void)switchValueChanged:(SPToggleSwitch *)sender {
    if (self.switchHandler) self.switchHandler(sender.isOn);
    [SPHaptics selection];
}

@end

#pragma mark - SPSettingsViewController

@interface SPSettingsViewController () <UITableViewDataSource, UITableViewDelegate, SPAuthObserver>
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UIView *navDivider;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SPSettingsSection *> *sections;
@end

@implementation SPSettingsViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    [self setupViews];
    [[SPAuthService shared] addObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange)
                                                 name:SPThemeDidChangeNotification
                                               object:nil];
    [self rebuildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuildSections];
}

- (void)themeDidChange {
    [UIView performWithoutAnimation:^{
        [self setNeedsStatusBarAppearanceUpdate];
        self.view.backgroundColor = SPTheme.backgroundColor;
        self.navBar.backgroundColor = SPTheme.backgroundColor;
        self.tableView.backgroundColor = SPTheme.backgroundColor;
        self.tableView.separatorColor = SPTheme.separatorColor;
        [self rebuildSections];
        [self.tableView layoutIfNeeded];
    }];
}

- (void)setupViews {
    _navBar = [UIView new];
    _navBar.backgroundColor = SPTheme.backgroundColor;
    [self.view addSubview:_navBar];

    SPScaleButton *backBtn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [backBtn sp_setSymbol:@"chevron.left" size:18 weight:UIImageSymbolWeightSemibold animated:NO];
    backBtn.tintColor = SPTheme.textPrimaryColor;
    [backBtn addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBar addSubview:backBtn];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"设置与隐私";
    titleLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor = SPTheme.textPrimaryColor;
    [_navBar addSubview:titleLabel];

    _navDivider = [UIView new];
    _navDivider.backgroundColor = SPTheme.separatorColor;
    _navDivider.alpha = 0.0;
    [_navBar addSubview:_navDivider];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.backgroundColor = SPTheme.backgroundColor;
    _tableView.separatorColor = SPTheme.separatorColor;
    _tableView.separatorInset = UIEdgeInsetsMake(0, 64, 0, 16);
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 66;
    _tableView.contentInset = UIEdgeInsetsMake(8, 0, 16, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPSettingsCell.class forCellReuseIdentifier:[SPSettingsCell reuseId]];
    [self.view addSubview:_tableView];

    [_navBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(48);
    }];
    [backBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.navBar).offset(8);
        make.bottom.equalTo(self.navBar).offset(-2);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.navBar);
        make.centerY.equalTo(backBtn);
    }];
    [_navDivider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.navBar);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.navBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
}

- (void)rebuildSections {
    __weak typeof(self) weakSelf = self;
    SPAuthService *auth = [SPAuthService shared];
    SPAudioCacheManager *audioCache = [SPAudioCacheManager shared];
    SPMusicRepository *repo = [SPMusicRepository shared];
    SPPlayerService *player = [SPPlayerService shared];

    // 1. 外观与体验
    SPSettingsRow *darkRow = [SPSettingsRow rowWithIcon:@"moon.fill"
                                              iconColor:[UIColor sp_colorWithHex:0x7C6CF6]
                                                  title:@"深色模式"
                                               subtitle:@"切换深色与浅色界面外观"];
    darkRow.accessoryType = SPSettingsAccessoryTypeSwitch;
    darkRow.switchOn = SPTheme.isDarkMode;
    darkRow.switchHandler = ^(BOOL isOn) {
        [SPTheme applyInterfaceStyle:(isOn ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight) animated:YES];
    };

    SPSettingsRow *hapticRow = [SPSettingsRow rowWithIcon:@"hand.tap.fill"
                                                iconColor:[UIColor sp_colorWithHex:0xF59B23]
                                                    title:@"触感反馈"
                                                 subtitle:@"按压按钮与切歌时提供细腻震动"];
    hapticRow.accessoryType = SPSettingsAccessoryTypeSwitch;
    hapticRow.switchOn = SPHaptics.isEnabled;
    hapticRow.switchHandler = ^(BOOL isOn) {
        SPHaptics.enabled = isOn;
    };

    SPSettingsRow *onboardingRow = [SPSettingsRow rowWithIcon:@"sparkles.rectangle.stack.fill"
                                                    iconColor:[UIColor sp_colorWithHex:0x38BDF8]
                                                        title:@"重新查看新手引导"
                                                     subtitle:@"浏览全屏横滑介绍页"];
    onboardingRow.accessoryType = SPSettingsAccessoryTypeDisclosure;
    onboardingRow.action = ^{ [weakSelf openOnboardingReplay]; };

    SPSettingsSection *secAppearance = [SPSettingsSection new];
    secAppearance.title = @"外观与体验";
    secAppearance.rows = @[darkRow, hapticRow, onboardingRow];

    // 2. 账号与安全
    SPSettingsSection *secAuth = [SPSettingsSection new];
    secAuth.title = @"账号与安全";
    if (auth.isLoggedIn) {
        SPUser *u = auth.currentUser;
        SPSettingsRow *profileRow = [SPSettingsRow rowWithIcon:@"person.crop.circle.fill"
                                                     iconColor:SPTheme.accentColor
                                                         title:u.nickname
                                                      subtitle:u.account];
        profileRow.trailingText = u.planName ?: @"Premium";

        SPSettingsRow *logoutRow = [SPSettingsRow rowWithIcon:@"rectangle.portrait.and.arrow.right"
                                                    iconColor:[UIColor sp_colorWithHex:0xEF4444]
                                                        title:@"退出当前账号"
                                                     subtitle:nil];
        logoutRow.titleColor = [UIColor sp_colorWithHex:0xEF4444];
        logoutRow.action = ^{ [weakSelf confirmLogout]; };
        secAuth.rows = @[profileRow, logoutRow];
    } else {
        SPSettingsRow *loginRow = [SPSettingsRow rowWithIcon:@"person.badge.plus"
                                                   iconColor:SPTheme.accentColor
                                                       title:@"登录或注册 Spotify"
                                                    subtitle:@"当前为游客浏览模式"];
        loginRow.titleColor = SPTheme.accentColor;
        loginRow.accessoryType = SPSettingsAccessoryTypeDisclosure;
        loginRow.action = ^{ [weakSelf openAuthPage]; };
        secAuth.rows = @[loginRow];
    }

    // 3. 播放与缓存策略
    SPSettingsRow *preloadRow = [SPSettingsRow rowWithIcon:@"bolt.fill"
                                                 iconColor:SPTheme.accentColor
                                                     title:@"上下首自动预加载"
                                                  subtitle:@"提前缓存相邻曲目，实现 0ms 秒切"];
    preloadRow.accessoryType = SPSettingsAccessoryTypeSwitch;
    preloadRow.switchOn = player.isPreloadEnabled;
    preloadRow.switchHandler = ^(BOOL isOn) {
        player.preloadEnabled = isOn;
    };

    SPSettingsRow *bgRow = [SPSettingsRow rowWithIcon:@"hifispeaker.2.fill"
                                            iconColor:[UIColor sp_colorWithHex:0x60A5FA]
                                                title:@"后台播放与灵动岛"
                                             subtitle:@"Audio Background 与 NowPlaying 已就绪"];
    bgRow.trailingText = @"已适配";

    SPSettingsSection *secPlayback = [SPSettingsSection new];
    secPlayback.title = @"播放与缓存策略";
    secPlayback.rows = @[preloadRow, bgRow];

    // 4. 三级 LRU 缓存与诊断
    double hitRate = audioCache.totalRequestCount > 0
        ? (audioCache.totalHitCount * 100.0 / audioCache.totalRequestCount) : 0.0;

    SPSettingsRow *l1Row = [SPSettingsRow rowWithIcon:@"memorychip.fill"
                                            iconColor:[UIColor sp_colorWithHex:0x34D399]
                                                title:@"L1 内存热缓存"
                                             subtitle:[NSString stringWithFormat:@"AVURLAsset %lu 首 · 播放地址 %lu 条",
                                                       (unsigned long)audioCache.memoryAssetCount,
                                                       (unsigned long)audioCache.resolvedURLCount]];
    SPSettingsRow *l2Row = [SPSettingsRow rowWithIcon:@"internaldrive.fill"
                                            iconColor:[UIColor sp_colorWithHex:0x38BDF8]
                                                title:@"L2 磁盘音频文件"
                                             subtitle:[NSString stringWithFormat:@"已缓存 %lu 首 · 命中率 %.0f%%",
                                                       (unsigned long)audioCache.diskCachedTrackCount, hitRate]];
    l2Row.trailingText = [NSString stringWithFormat:@"%.1f MB", audioCache.diskCacheBytes / (1024.0 * 1024.0)];

    SPSettingsRow *l3Row = [SPSettingsRow rowWithIcon:@"square.stack.3d.up.fill"
                                            iconColor:[UIColor sp_colorWithHex:0xA78BFA]
                                                title:@"L3 元数据与取色缓存"
                                             subtitle:[NSString stringWithFormat:@"缓存条目 %lu 条 · 累计命中 %lu 次",
                                                       (unsigned long)repo.cachedEntryCount,
                                                       (unsigned long)repo.cacheHitCount]];

    SPSettingsRow *clearRow = [SPSettingsRow rowWithIcon:@"trash.fill"
                                               iconColor:[UIColor sp_colorWithHex:0xEF4444]
                                                   title:@"清空全部缓存"
                                                subtitle:@"释放 L1/L2/L3 与封面磁盘缓存"];
    clearRow.titleColor = [UIColor sp_colorWithHex:0xEF4444];
    clearRow.action = ^{ [weakSelf clearAllCaches]; };

    SPSettingsSection *secCache = [SPSettingsSection new];
    secCache.title = @"三级 LRU 缓存管理";
    secCache.rows = @[l1Row, l2Row, l3Row, clearRow];

    // 5. 数据源与认证通道
    SPSettingsRow *srcRow = [SPSettingsRow rowWithIcon:@"antenna.radiowaves.left.and.right"
                                             iconColor:[UIColor sp_colorWithHex:0x38BDF8]
                                                 title:@"当前音乐数据源"
                                              subtitle:repo.sourceName];
    srcRow.accessoryType = SPSettingsAccessoryTypeDisclosure;
    srcRow.action = ^{ [weakSelf chooseMusicSource]; };

    SPSettingsRow *authSrcRow = [SPSettingsRow rowWithIcon:@"key.fill"
                                                 iconColor:[UIColor sp_colorWithHex:0xA78BFA]
                                                     title:@"当前认证通道"
                                                  subtitle:auth.provider.providerName];
    authSrcRow.accessoryType = SPSettingsAccessoryTypeDisclosure;
    authSrcRow.action = ^{ [weakSelf chooseAuthProvider]; };

    SPSettingsSection *secSource = [SPSettingsSection new];
    secSource.title = @"数据源与认证通道";
    secSource.rows = @[srcRow, authSrcRow];

    self.sections = @[secAppearance, secAuth, secPlayback, secCache, secSource];
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)backTapped {
    [SPHaptics light];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)openOnboardingReplay {
    [SPHaptics light];
    SPOnboardingViewController *onboarding = [SPOnboardingViewController new];
    onboarding.replayMode = YES;
    onboarding.modalPresentationStyle = UIModalPresentationFullScreen;
    UIViewController *presenter = self.view.window.rootViewController ?: self;
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    [presenter presentViewController:onboarding animated:YES completion:nil];
}

- (void)openAuthPage {
    [SPHaptics light];
    UIViewController *root = self.view.window.rootViewController;
    if ([root isKindOfClass:SPRootViewController.class]) {
        [(SPRootViewController *)root presentAuthFlow];
    }
}

- (void)confirmLogout {
    [SPHaptics medium];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"退出登录"
                                                                   message:@"确定要退出当前账号并返回登录页吗？"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;
    [sheet addAction:[UIAlertAction actionWithTitle:@"退出登录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[SPAuthService shared] logout];
        [SceneDelegate setHasEnteredGuestMode:NO];
        [[SceneDelegate shared] transitionToAuthWelcomeAnimated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)clearAllCaches {
    [SPHaptics medium];
    [[SPAudioCacheManager shared] clearAllCaches];
    [[SPMusicRepository shared] clearMetadataCaches];
    [UIImage sp_clearDominantColorCache];
    [SDImageCache.sharedImageCache clearMemory];
    __weak typeof(self) weakSelf = self;
    [SDImageCache.sharedImageCache clearDiskOnCompletion:^{
        [weakSelf rebuildSections];
    }];
    [self rebuildSections];
    [SPToast showMessage:@"全部缓存已清空"];
}

- (void)chooseMusicSource {
    [SPHaptics light];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"切换音乐数据源"
                                                                   message:@"支持在网易云真实 API 与本地 Mock 间热切换"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"网易云音乐 API (msapi.awup.cn)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:@"netease" forKey:@"sp_music_source_type_v1"];
        SPNeteaseSession.baseURLString = SPNeteaseDefaultBaseURL;
        [SPNeteaseSession shared].anonymousCookie = nil;
        [[SPPlayerService shared] resetToEmptyState];
        [SPMusicRepository shared].source = [SPNeteaseMusicSource new];
        [weakSelf rebuildSections];
        [SPToast showMessage:@"已切换至网易云音乐 API"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"本地 Mock 数据源"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:@"mock" forKey:@"sp_music_source_type_v1"];
        [[SPPlayerService shared] resetToEmptyState];
        [SPMusicRepository shared].source = [SPMockMusicSource new];
        [weakSelf rebuildSections];
        [SPToast showMessage:@"已切换至本地 Mock 数据源"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"自定义 API Base URL..."
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf promptCustomBaseURL];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptCustomBaseURL {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"自定义网易云 API 地址"
                                                                   message:@"输入 NeteaseCloudMusicApi 服务根地址"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    alert.view.tintColor = SPTheme.accentColor;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [SPNeteaseSession baseURLString];
        field.placeholder = SPNeteaseDefaultBaseURL;
        field.keyboardType = UIKeyboardTypeURL;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text ?: @"";
        SPNeteaseSession.baseURLString = input;
        NSString *resolved = [SPNeteaseSession baseURLString];
        [[NSUserDefaults standardUserDefaults] setObject:@"netease" forKey:@"sp_music_source_type_v1"];
        [SPNeteaseSession shared].anonymousCookie = nil;
        [[SPPlayerService shared] resetToEmptyState];
        [SPMusicRepository shared].source = [[SPNeteaseMusicSource alloc] initWithBaseURLString:resolved];
        [weakSelf rebuildSections];
        [SPToast showMessage:[NSString stringWithFormat:@"已切换 API：%@", resolved]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseAuthProvider {
    [SPHaptics light];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"切换认证通道"
                                                                   message:@"本地认证免风控，网易云账号可同步个人歌单"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"本地安全认证（推荐）"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:@"local" forKey:@"sp_auth_provider_type_v1"];
        [SPAuthService shared].provider = [SPLocalAuthProvider new];
        [weakSelf rebuildSections];
        [SPToast showMessage:@"已切换为本地安全认证"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"网易云账号认证"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:@"netease" forKey:@"sp_auth_provider_type_v1"];
        [SPAuthService shared].provider = [SPNeteaseAuthProvider new];
        [weakSelf rebuildSections];
        [SPToast showMessage:@"已切换为网易云账号认证"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - SPAuthObserver

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    [self rebuildSections];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].rows.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [UIView new];
    UILabel *label = [UILabel new];
    label.text = self.sections[section].title;
    label.font = [SPTheme fontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = SPTheme.textSecondaryColor;
    [header addSubview:label];
    [label mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(header).offset(6);
        make.right.equalTo(header).offset(-6);
        make.bottom.equalTo(header).offset(-8);
        make.top.equalTo(header).offset(16);
    }];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 14.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return [UIView new];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPSettingsCell reuseId] forIndexPath:indexPath];
    [cell configureWithRow:self.sections[indexPath.section].rows[indexPath.row]];
    return cell;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offsetY = MAX(0.0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top);
    self.navDivider.alpha = MIN(MAX(offsetY / 16.0, 0.0), 1.0);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SPSettingsRow *row = self.sections[indexPath.section].rows[indexPath.row];
    if (row.action) row.action();
}

@end
