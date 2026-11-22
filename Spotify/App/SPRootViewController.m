//
//  SPRootViewController.m
//  Spotify
//

#import "SPRootViewController.h"
#import "SPNavigationController.h"
#import "SPHomeViewController.h"
#import "SPSearchViewController.h"
#import "SPLibraryViewController.h"
#import "SPMiniPlayerView.h"
#import "SPScaleButton.h"
#import "SPNowPlayingViewController.h"
#import "SPNowPlayingTransition.h"
#import "SPSideDrawerViewController.h"
#import "SPAuthWelcomeViewController.h"
#import "SPActivityViewController.h"
#import "SPHistoryViewController.h"
#import "SPSettingsViewController.h"
#import "SPPlayerService.h"
#import "SPHaptics.h"

#pragma mark - Private Tab Bar Controller & Dock Item

@interface SPInternalTabBarController : UITabBarController
@property (nonatomic, copy, nullable) void (^onSelectionChanged)(NSUInteger index);
@end

@implementation SPInternalTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tabBar.hidden = YES;
    self.tabBar.userInteractionEnabled = NO;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tabBar.hidden) {
        self.tabBar.hidden = YES;
    }
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];
    if (self.onSelectionChanged) {
        self.onSelectionChanged(selectedIndex);
    }
}

@end

@interface SPTabItemButton : SPScaleButton
@property (nonatomic, copy) NSString *normalIconName;
@property (nonatomic, copy) NSString *selectedIconName;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabelView;
@property (nonatomic, assign, getter=isTabSelected) BOOL tabSelected;
@end

@implementation SPTabItemButton

- (instancetype)initWithTitle:(NSString *)title normalIcon:(NSString *)normalIcon selectedIcon:(NSString *)selectedIcon {
    if (self = [super initWithFrame:CGRectZero]) {
        _normalIconName = [normalIcon copy];
        _selectedIconName = [selectedIcon copy];

        _iconView = [UIImageView new];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.userInteractionEnabled = NO;

        _titleLabelView = [UILabel new];
        _titleLabelView.text = title;
        _titleLabelView.font = [SPTheme fontOfSize:10 weight:UIFontWeightMedium];
        _titleLabelView.textAlignment = NSTextAlignmentCenter;
        _titleLabelView.userInteractionEnabled = NO;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _titleLabelView]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 3;
        stack.userInteractionEnabled = NO;
        [self addSubview:stack];

        [_iconView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.size.mas_equalTo(CGSizeMake(26, 24));
        }];
        [stack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.center.equalTo(self);
            make.left.greaterThanOrEqualTo(self).offset(4);
            make.right.lessThanOrEqualTo(self).offset(-4);
        }];
        [self updateAppearance];
    }
    return self;
}

- (void)setTabSelected:(BOOL)tabSelected {
    _tabSelected = tabSelected;
    [self updateAppearance];
}

- (void)updateAppearance {
    BOOL selected = self.tabSelected;
    NSString *iconName = selected ? self.selectedIconName : self.normalIconName;
    UIImageSymbolWeight weight = selected ? UIImageSymbolWeightSemibold : UIImageSymbolWeightRegular;
    self.iconView.image = [SPTheme symbol:iconName size:22 weight:weight];
    UIColor *color = selected ? SPTheme.textPrimaryColor : SPTheme.textSecondaryColor;
    self.iconView.tintColor = color;
    self.titleLabelView.textColor = color;
    self.titleLabelView.font = [SPTheme fontOfSize:11 weight:selected ? UIFontWeightSemibold : UIFontWeightMedium];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateAppearance];
    }
}

@end

#pragma mark - SPRootViewController

static const CGFloat SPDockTabBarHeight = 52.0;

@interface SPRootViewController () <SPPlayerObserver, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) SPInternalTabBarController *tabController;
@property (nonatomic, strong) UIView *tabBarOpaqueBackdrop;
@property (nonatomic, strong) UIView *tabBarTopHairline;
@property (nonatomic, strong) UIView *customTabBar;
@property (nonatomic, copy) NSArray<SPTabItemButton *> *tabButtons;
@property (nonatomic, strong) SPMiniPlayerView *miniPlayer;

@property (nonatomic, strong) UIView *drawerDimView;
@property (nonatomic, strong) UIView *drawerContainerView;
@property (nonatomic, strong) SPSideDrawerViewController *drawerController;
@property (nonatomic, strong) MASConstraint *drawerWidthConstraint;
@property (nonatomic, assign) CGFloat lastDrawerWidth;

@property (nonatomic, strong) SPNowPlayingTransition *nowPlayingTransition;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *edgePan;
@property (nonatomic, strong) UIPanGestureRecognizer *closePan;
@property (nonatomic, assign) BOOL drawerOpen;
@property (nonatomic, assign) BOOL isAnimatingDrawer;
@end

@implementation SPRootViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    [self setupContentContainer];
    [self setupTabs];
    [self setupBottomDock];
    [self setupOverlayDrawer];
    [self setupDrawerGestures];
    [[SPPlayerService shared] addObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange)
                                                 name:SPThemeDidChangeNotification
                                               object:nil];
    [UIView performWithoutAnimation:^{
        [self.view layoutIfNeeded];
    }];
    [self updateMiniPlayerVisibilityAnimated:NO];
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    return self.tabController.selectedViewController;
}

- (CGFloat)calculatedDrawerWidth {
    CGFloat w = CGRectGetWidth(self.view.bounds);
    if (w <= 0) w = CGRectGetWidth(UIScreen.mainScreen.bounds);
    return MIN(w * 0.80, 312.0);
}

#pragma mark - Hierarchy (Stationary Main + Unified Compact Bottom Dock + Top Overlay Drawer)

- (void)setupContentContainer {
    _contentContainer = [UIView new];
    _contentContainer.backgroundColor = SPTheme.backgroundColor;
    [self.view addSubview:_contentContainer];
    [_contentContainer mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
}

- (void)setupTabs {
    SPInternalTabBarController *tab = [SPInternalTabBarController new];
    tab.viewControllers = @[
        [self navWithRoot:[SPHomeViewController new]],
        [self navWithRoot:[SPSearchViewController new]],
        [self navWithRoot:[SPLibraryViewController new]],
    ];
    __weak typeof(self) weakSelf = self;
    tab.onSelectionChanged = ^(NSUInteger index) {
        [weakSelf syncCustomTabSelection:(NSInteger)index];
    };

    [self addChildViewController:tab];
    [self.contentContainer addSubview:tab.view];
    [tab.view mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.contentContainer);
    }];
    [tab didMoveToParentViewController:self];
    self.tabController = tab;
}

- (UINavigationController *)navWithRoot:(UIViewController *)root {
    return [[SPNavigationController alloc] initWithRootViewController:root];
}

- (void)setupBottomDock {
    _tabBarOpaqueBackdrop = [UIView new];
    _tabBarOpaqueBackdrop.opaque = YES;
    [self.contentContainer addSubview:_tabBarOpaqueBackdrop];

    _tabBarTopHairline = [UIView new];
    _tabBarTopHairline.backgroundColor = SPTheme.separatorColor;
    [_tabBarOpaqueBackdrop addSubview:_tabBarTopHairline];

    _customTabBar = [UIView new];
    _customTabBar.backgroundColor = UIColor.clearColor;
    [self.contentContainer addSubview:_customTabBar];

    NSArray<NSDictionary *> *items = @[
        @{@"title": @"首页", @"icon": @"house", @"selectedIcon": @"house.fill"},
        @{@"title": @"搜索", @"icon": @"magnifyingglass", @"selectedIcon": @"magnifyingglass"},
        @{@"title": @"音乐库", @"icon": @"books.vertical", @"selectedIcon": @"books.vertical.fill"},
    ];
    NSMutableArray<SPTabItemButton *> *btns = [NSMutableArray arrayWithCapacity:items.count];
    for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
        NSDictionary *info = items[i];
        SPTabItemButton *btn = [[SPTabItemButton alloc] initWithTitle:info[@"title"]
                                                           normalIcon:info[@"icon"]
                                                         selectedIcon:info[@"selectedIcon"]];
        btn.tag = i;
        [btn addTarget:self action:@selector(tabButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [btns addObject:btn];
    }
    _tabButtons = [btns copy];

    UIStackView *tabStack = [[UIStackView alloc] initWithArrangedSubviews:btns];
    tabStack.axis = UILayoutConstraintAxisHorizontal;
    tabStack.distribution = UIStackViewDistributionFillEqually;
    [_customTabBar addSubview:tabStack];

    self.miniPlayer = [SPMiniPlayerView new];
    __weak typeof(self) weakSelf = self;
    self.miniPlayer.tapHandler = ^{ [weakSelf presentNowPlaying]; };
    [self.contentContainer addSubview:self.miniPlayer];

    [_customTabBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.equalTo(self.contentContainer);
        make.height.mas_equalTo(SPDockTabBarHeight);
        make.bottom.equalTo(self.contentContainer.mas_safeAreaLayoutGuideBottom);
    }];
    [_tabBarOpaqueBackdrop mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.customTabBar.mas_top);
        make.left.right.bottom.equalTo(self.contentContainer);
    }];
    [_tabBarTopHairline mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.tabBarOpaqueBackdrop);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [tabStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.customTabBar);
    }];
    [self.miniPlayer mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.contentContainer).offset(8);
        make.right.equalTo(self.contentContainer).offset(-8);
        make.height.mas_equalTo(SPMiniPlayerHeight);
        make.bottom.equalTo(self.customTabBar.mas_top).offset(-8);
    }];

    [self syncCustomTabSelection:(NSInteger)self.tabController.selectedIndex];
    [self updateBottomDockTheme];
    [self updateTabDockMetrics];
}

- (void)tabButtonTapped:(SPTabItemButton *)sender {
    [SPHaptics light];
    NSUInteger targetIndex = (NSUInteger)sender.tag;
    if (self.tabController.selectedIndex == targetIndex) {
        UINavigationController *nav = (UINavigationController *)self.tabController.selectedViewController;
        if ([nav isKindOfClass:UINavigationController.class] && nav.viewControllers.count > 1) {
            [nav popToRootViewControllerAnimated:YES];
        }
        return;
    }
    self.tabController.selectedIndex = targetIndex;
}

- (void)syncCustomTabSelection:(NSInteger)selectedIndex {
    for (SPTabItemButton *btn in self.tabButtons) {
        btn.tabSelected = (btn.tag == selectedIndex);
    }
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)updateTabDockMetrics {
    BOOL visible = ([SPPlayerService shared].currentTrack != nil);
    CGFloat inset = SPDockTabBarHeight + (visible ? (SPMiniPlayerHeight + 16.0) : 6.0);
    for (UIViewController *vc in self.tabController.viewControllers) {
        UIEdgeInsets insets = vc.additionalSafeAreaInsets;
        insets.bottom = inset;
        vc.additionalSafeAreaInsets = insets;
    }
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateTabDockMetrics];
}

- (void)updateBottomDockTheme {
    UIColor *solidDockColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return (tc.userInterfaceStyle == UIUserInterfaceStyleLight)
            ? UIColor.whiteColor
            : [UIColor sp_colorWithHex:0x121214];
    }];
    self.tabBarOpaqueBackdrop.backgroundColor = solidDockColor;
    self.tabBarTopHairline.backgroundColor = SPTheme.separatorColor;
}

#pragma mark - Overlay Drawer

- (void)setupOverlayDrawer {
    _drawerDimView = [UIView new];
    _drawerDimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.52];
    _drawerDimView.alpha = 0;
    _drawerDimView.hidden = YES;
    [_drawerDimView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dimTapped)]];
    [self.view addSubview:_drawerDimView];
    [_drawerDimView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];

    _drawerContainerView = [UIView new];
    _drawerContainerView.hidden = YES;
    _drawerContainerView.layer.shadowColor = UIColor.blackColor.CGColor;
    _drawerContainerView.layer.shadowOpacity = 0.28;
    _drawerContainerView.layer.shadowRadius = 18;
    _drawerContainerView.layer.shadowOffset = CGSizeMake(4, 0);
    [self.view addSubview:_drawerContainerView];

    CGFloat w = [self calculatedDrawerWidth];
    _lastDrawerWidth = w;
    [_drawerContainerView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.left.equalTo(self.view);
        self.drawerWidthConstraint = make.width.mas_equalTo(w);
    }];
    _drawerContainerView.transform = CGAffineTransformMakeTranslation(-w, 0);

    _drawerController = [SPSideDrawerViewController new];
    __weak typeof(self) weakSelf = self;
    _drawerController.menuSelectionHandler = ^(SPDrawerMenuAction action) {
        [weakSelf handleDrawerAction:action];
    };
    [self addChildViewController:_drawerController];
    [_drawerContainerView addSubview:_drawerController.view];
    [_drawerController.view mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.drawerContainerView);
    }];
    [_drawerController didMoveToParentViewController:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [UIView performWithoutAnimation:^{
        [self.contentContainer layoutIfNeeded];
        [self.miniPlayer layoutIfNeeded];
    }];
    CGFloat w = [self calculatedDrawerWidth];
    if (w > 0 && fabs(self.lastDrawerWidth - w) > 0.5) {
        self.lastDrawerWidth = w;
        self.drawerWidthConstraint.mas_equalTo(w);
        if (!self.drawerOpen && !self.isAnimatingDrawer) {
            self.drawerContainerView.transform = CGAffineTransformMakeTranslation(-w, 0);
        }
    }
    if (!CGRectIsEmpty(self.drawerContainerView.bounds)) {
        self.drawerContainerView.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.drawerContainerView.bounds].CGPath;
    }
}

#pragma mark - Theme Updates

- (void)themeDidChange {
    [self updateBottomDockTheme];
    for (SPTabItemButton *btn in self.tabButtons) {
        [btn updateAppearance];
    }
    self.view.backgroundColor = SPTheme.backgroundColor;
    self.contentContainer.backgroundColor = SPTheme.backgroundColor;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self themeDidChange];
    }
}

#pragma mark - Mini Player

- (void)updateMiniPlayerVisibilityAnimated:(BOOL)animated {
    BOOL visible = [SPPlayerService shared].currentTrack != nil;
    [self updateTabDockMetrics];

    // 先在无动画块中自顶向下冲刷 self.view -> contentContainer -> miniPlayer 约束，防止首次进入时子控件从 (0,0,0,0) 飞入导致乱飘
    [UIView performWithoutAnimation:^{
        [self.view layoutIfNeeded];
        [self.contentContainer layoutIfNeeded];
        [self.miniPlayer layoutIfNeeded];
    }];

    if (visible == !self.miniPlayer.hidden) {
        return;
    }

    BOOL shouldAnimate = animated
        && !UIAccessibilityIsReduceMotionEnabled()
        && (self.view.window != nil)
        && (CGRectGetWidth(self.contentContainer.bounds) > 0)
        && (CGRectGetWidth(self.miniPlayer.bounds) > 0);
    if (!shouldAnimate) {
        [UIView performWithoutAnimation:^{
            self.miniPlayer.hidden = !visible;
            self.miniPlayer.alpha = visible ? 1 : 0;
            self.miniPlayer.transform = CGAffineTransformIdentity;
            [self.miniPlayer layoutIfNeeded];
        }];
        return;
    }
    [UIView performWithoutAnimation:^{
        self.miniPlayer.hidden = NO;
        self.miniPlayer.alpha = visible ? 0 : 1;
        self.miniPlayer.transform = visible ? CGAffineTransformMakeTranslation(0, 14) : CGAffineTransformIdentity;
        [self.miniPlayer layoutIfNeeded];
    }];
    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0 options:0 animations:^{
        self.miniPlayer.alpha = visible ? 1 : 0;
        self.miniPlayer.transform = visible ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, 14);
    } completion:^(BOOL finished) {
        self.miniPlayer.hidden = !visible;
        self.miniPlayer.transform = CGAffineTransformIdentity;
    }];
}

- (void)playerDidChangeTrack:(SPPlayerService *)player {
    [self updateMiniPlayerVisibilityAnimated:YES];
}

#pragma mark - Drawer Overlay Interactions (Zero Jitter)

- (void)setupDrawerGestures {
    self.edgePan = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrawerPan:)];
    self.edgePan.edges = UIRectEdgeLeft;
    self.edgePan.delegate = self;
    [self.view addGestureRecognizer:self.edgePan];

    self.closePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrawerPan:)];
    self.closePan.delegate = self;
    [self.view addGestureRecognizer:self.closePan];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.edgePan) {
        if (self.drawerOpen) return NO;
        UINavigationController *nav = (UINavigationController *)self.tabController.selectedViewController;
        if ([nav isKindOfClass:UINavigationController.class] && nav.viewControllers.count > 1) {
            return NO; // 二级页时让位给侧滑返回
        }
        return YES;
    }
    if (gestureRecognizer == self.closePan) {
        if (!self.drawerOpen) return NO;
        CGPoint v = [self.closePan velocityInView:self.view];
        return v.x < 0 && fabs(v.x) > fabs(v.y);
    }
    return YES;
}

- (void)handleDrawerPan:(UIPanGestureRecognizer *)pan {
    CGFloat w = [self calculatedDrawerWidth];
    CGPoint translation = [pan translationInView:self.view];
    CGPoint velocity = [pan velocityInView:self.view];

    CGFloat baseX = self.drawerOpen ? w : 0;
    CGFloat currentX = MIN(MAX(baseX + translation.x, 0), w);
    CGFloat progress = w > 0 ? (currentX / w) : 0;

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.isAnimatingDrawer = YES;
        self.drawerDimView.hidden = NO;
        self.drawerContainerView.hidden = NO;
        [self.drawerController refreshContent];
        [self applyDrawerProgress:(self.drawerOpen ? 1.0 : 0.0)];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        [self applyDrawerProgress:progress];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        BOOL shouldOpen = (velocity.x > 400) || (velocity.x >= -400 && progress > 0.45);
        if (shouldOpen) {
            [self openSideDrawer];
        } else {
            [self closeSideDrawerAnimated:YES completion:nil];
        }
    }
}

- (void)applyDrawerProgress:(CGFloat)progress {
    CGFloat clamped = MIN(MAX(progress, 0.0), 1.0);
    CGFloat w = [self calculatedDrawerWidth];
    // 主视图 contentContainer 绝对静止；仅叠加层与左侧抽屉平移滑入
    self.drawerContainerView.transform = CGAffineTransformMakeTranslation(-w * (1.0 - clamped), 0);
    self.drawerDimView.alpha = clamped;
}

- (void)openSideDrawer {
    self.drawerOpen = YES;
    self.isAnimatingDrawer = YES;
    self.drawerDimView.hidden = NO;
    self.drawerContainerView.hidden = NO;
    [self.drawerController refreshContent];
    [self.view layoutIfNeeded];

    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self applyDrawerProgress:1.0];
        self.isAnimatingDrawer = NO;
        return;
    }

    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:1.0
          initialSpringVelocity:0.35
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        [self applyDrawerProgress:1.0];
    } completion:^(BOOL finished) {
        self.isAnimatingDrawer = NO;
    }];
}

- (void)closeSideDrawerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.drawerOpen = NO;
    self.isAnimatingDrawer = YES;
    void (^work)(void) = ^{
        [self applyDrawerProgress:0.0];
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        self.isAnimatingDrawer = NO;
        if (!self.drawerOpen) {
            self.drawerDimView.hidden = YES;
            self.drawerContainerView.hidden = YES;
        }
        if (completion) completion();
    };
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        work();
        done(YES);
        return;
    }
    [UIView animateWithDuration:0.22
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:work
                     completion:done];
}

- (void)dimTapped {
    [self closeSideDrawerAnimated:YES completion:nil];
}

#pragma mark - Unified VC Transition Choreography

- (void)handleDrawerAction:(SPDrawerMenuAction)action {
    if (action == SPDrawerMenuActionAuth) {
        [self presentAuthFlow];
        return;
    }

    UIViewController *targetVC = nil;
    switch (action) {
        case SPDrawerMenuActionActivity:
            targetVC = [SPActivityViewController new];
            break;
        case SPDrawerMenuActionHistory:
            targetVC = [SPHistoryViewController new];
            break;
        case SPDrawerMenuActionSettings:
            targetVC = [SPSettingsViewController new];
            break;
        case SPDrawerMenuActionAuth:
            break;
    }

    if (targetVC) {
        UINavigationController *nav = (UINavigationController *)self.tabController.selectedViewController;
        if ([nav isKindOfClass:UINavigationController.class] && ![nav.topViewController isKindOfClass:targetVC.class]) {
            // 先让目标页在静止的底层就位，随后抽屉单段平滑滑出并显露目标页，消除“关抽屉闪首页再推入”的两段割裂
            [nav pushViewController:targetVC animated:NO];
        }
    }
    [self closeSideDrawerAnimated:YES completion:nil];
}

- (void)pushOnCurrentTab:(UIViewController *)vc {
    UINavigationController *nav = (UINavigationController *)self.tabController.selectedViewController;
    if ([nav isKindOfClass:UINavigationController.class]) {
        [nav pushViewController:vc animated:YES];
    }
}

#pragma mark - Modal Presentations

- (void)presentNowPlaying {
    if (![SPPlayerService shared].currentTrack) return;
    if (!self.nowPlayingTransition) {
        __weak typeof(self) weakSelf = self;
        self.nowPlayingTransition = [[SPNowPlayingTransition alloc] initWithMiniPlayerView:self.miniPlayer
                                                                       sourceCoverProvider:^UIView *{
            return weakSelf.miniPlayer.coverView;
        }];
    }
    SPNowPlayingViewController *vc = [SPNowPlayingViewController new];
    vc.modalPresentationStyle = UIModalPresentationCustom;
    vc.transitioningDelegate = self.nowPlayingTransition;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)presentAuthFlow {
    SPAuthWelcomeViewController *welcome = [[SPAuthWelcomeViewController alloc] initWithContext:SPAuthPresentationContextModal];
    SPNavigationController *nav = [[SPNavigationController alloc] initWithRootViewController:welcome];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    __weak typeof(self) weakSelf = self;
    [self presentViewController:nav animated:YES completion:^{
        if (weakSelf.drawerOpen) {
            [weakSelf closeSideDrawerAnimated:NO completion:nil];
        }
    }];
}

@end
