//
//  SPHomeViewController.m
//  Spotify
//

#import "SPHomeViewController.h"
#import "SPHomeShortcutCell.h"
#import "SPHomeSectionHeaderView.h"
#import "SPMediaCells.h"
#import "SPGradientView.h"
#import "SPSkeletonView.h"
#import "SPUserAvatarButton.h"
#import "SPScaleButton.h"
#import "SPDetailViewController.h"
#import "SPListeningStatsViewController.h"
#import "SPMoodRoamViewController.h"
#import "SPSettingsViewController.h"
#import "SPMusicRepository.h"
#import "SPPlayerService.h"
#import "SPAudioCacheManager.h"
#import "SPRootViewController.h"
#import "UIImage+SPDominantColor.h"
#import "SPPlaylist.h"
#import "SPAlbum.h"
#import "SPFormatter.h"
#import "SPHaptics.h"
#import "SPToast.h"

static NSString * const SPHomeGlobalFooterKind = @"SPHomeGlobalFooter";

@interface SPHomeLoadMoreFooterView : UICollectionReusableView
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation SPHomeLoadMoreFooterView

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.color = SPTheme.accentColor;
        _spinner.hidesWhenStopped = YES;

        _statusLabel = [UILabel new];
        _statusLabel.font = [SPTheme fontOfSize:12.5 weight:UIFontWeightMedium];
        _statusLabel.textColor = SPTheme.textSecondaryColor;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_spinner, _statusLabel]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 8;
        [self addSubview:stack];
        [stack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.center.equalTo(self);
            make.left.greaterThanOrEqualTo(self).offset(16);
            make.right.lessThanOrEqualTo(self).offset(-16);
        }];
    }
    return self;
}

- (void)configureLoading:(BOOL)loading hasMore:(BOOL)hasMore isPodcast:(BOOL)isPodcast visible:(BOOL)visible {
    self.hidden = !visible;
    if (!visible) {
        [self.spinner stopAnimating];
        return;
    }
    if (loading) {
        [self.spinner startAnimating];
        self.statusLabel.text = isPodcast ? @"正在发现更多精彩播客..." : @"正在为你发现更多音乐...";
    } else if (hasMore) {
        [self.spinner stopAnimating];
        self.statusLabel.text = isPodcast ? @"继续下滑，探索更多精选播客" : @"继续下滑，探索更多精选歌单";
    } else {
        [self.spinner stopAnimating];
        self.statusLabel.text = @"— 已为你呈现全部精选内容 —";
    }
}

@end

@interface SPHomeViewController () <UICollectionViewDataSource, UICollectionViewDelegate, SPPlayerObserver>
@property (nonatomic, strong) SPGradientView *ambientGradient;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *topBarHairline;
@property (nonatomic, strong) UILabel *greetingLabel;
@property (nonatomic, strong) NSArray<UIButton *> *chipButtons;
@property (nonatomic, assign) NSInteger selectedChipIndex;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, weak, nullable) SPHomeLoadMoreFooterView *footerView;
@property (nonatomic, strong, nullable) SPSkeletonView *skeletonView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<SPHomeSection *> *> *sectionsByCategory;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *nextPageByCategory;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *hasMoreByCategory;
@property (nonatomic, copy) NSArray<SPHomeSection *> *visibleSections;
@property (nonatomic, assign) BOOL hasPlayedInitialEntrance;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *loadingMoreCategories;
@property (nonatomic, assign) NSUInteger categoryRequestToken;
@end

@implementation SPHomeViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    _sectionsByCategory = [NSMutableDictionary dictionary];
    _nextPageByCategory = [NSMutableDictionary dictionary];
    _hasMoreByCategory = [NSMutableDictionary dictionary];
    _loadingMoreCategories = [NSMutableSet set];
    _visibleSections = @[];
    [self setupViews];
    [[SPPlayerService shared] addObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(musicSourceDidChange)
                                                 name:SPMusicSourceDidChangeNotification
                                               object:nil];
    [self showSkeleton];
    [self loadDataForCurrentCategoryForceRefresh:NO];
}

- (SPHomeCategory)currentCategory {
    if (self.selectedChipIndex == 1) return SPHomeCategoryMusic;
    if (self.selectedChipIndex == 2) return SPHomeCategoryPodcast;
    return SPHomeCategoryAll;
}

- (void)musicSourceDidChange {
    self.categoryRequestToken += 1;
    self.selectedChipIndex = 0;
    [self updateChipStyles];
    [self.sectionsByCategory removeAllObjects];
    [self.nextPageByCategory removeAllObjects];
    [self.hasMoreByCategory removeAllObjects];
    [self.loadingMoreCategories removeAllObjects];
    self.visibleSections = @[];
    [self.collectionView reloadData];
    [self showSkeleton];
    [self loadDataForCurrentCategoryForceRefresh:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.greetingLabel.text = [SPFormatter greeting];
}

- (void)setupViews {
    _ambientGradient = [SPGradientView new];
    UIColor *ambientTop = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
        return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight)
            ? [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:0.10]
            : [UIColor sp_colorWithHex:0x2A1F4A];
    }];
    _ambientGradient.colors = @[ambientTop, SPTheme.backgroundColor];
    [self.view addSubview:_ambientGradient];

    _topBar = [UIView new];
    [self.view addSubview:_topBar];

    _topBarHairline = [UIView new];
    _topBarHairline.backgroundColor = SPTheme.separatorColor;
    _topBarHairline.alpha = 0.0;
    [_topBar addSubview:_topBarHairline];

    SPUserAvatarButton *avatarButton = [[SPUserAvatarButton alloc] initWithDiameter:34];
    [_topBar addSubview:avatarButton];

    _greetingLabel = [UILabel new];
    _greetingLabel.text = [SPFormatter greeting];
    _greetingLabel.font = SPTheme.largeTitleFont;
    _greetingLabel.textColor = SPTheme.textPrimaryColor;
    [_topBar addSubview:_greetingLabel];

    SPScaleButton *roamBtn = [self topIconButton:@"headphones" action:@selector(roamTapped)];
    roamBtn.accessibilityLabel = @"漫游电台";
    SPScaleButton *statsBtn = [self topIconButton:@"chart.bar" action:@selector(statsTapped)];
    statsBtn.accessibilityLabel = @"听歌统计";
    SPScaleButton *settingsBtn = [self topIconButton:@"gearshape" action:@selector(settingsTapped)];
    settingsBtn.accessibilityLabel = @"设置";
    UIStackView *actionStack = [[UIStackView alloc] initWithArrangedSubviews:@[roamBtn, statsBtn, settingsBtn]];
    actionStack.spacing = 4;
    [_topBar addSubview:actionStack];

    NSArray *chips = @[@"全部", @"音乐", @"播客"];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)chips.count; i++) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.title = chips[i];
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.contentInsets = NSDirectionalEdgeInsetsMake(7, 16, 7, 16);
        config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
            NSMutableDictionary *attrs = [incoming mutableCopy];
            attrs[NSFontAttributeName] = [SPTheme fontOfSize:13 weight:UIFontWeightMedium];
            return attrs;
        };
        SPScaleButton *chip = [SPScaleButton buttonWithConfiguration:config primaryAction:nil];
        chip.tag = i;
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:chip];
    }
    _chipButtons = buttons;
    [self updateChipStyles];

    UIStackView *chipStack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    chipStack.spacing = 8;
    [_topBar addSubview:chipStack];

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[self createLayout]];
    _collectionView.backgroundColor = UIColor.clearColor;
    _collectionView.showsVerticalScrollIndicator = NO;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    [_collectionView registerClass:SPHomeShortcutCell.class forCellWithReuseIdentifier:[SPHomeShortcutCell reuseId]];
    [_collectionView registerClass:SPMediaCardCell.class forCellWithReuseIdentifier:[SPMediaCardCell reuseId]];
    [_collectionView registerClass:SPHomeSectionHeaderView.class
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:[SPHomeSectionHeaderView reuseId]];
    [_collectionView registerClass:SPHomeLoadMoreFooterView.class
        forSupplementaryViewOfKind:SPHomeGlobalFooterKind
               withReuseIdentifier:[SPHomeLoadMoreFooterView reuseId]];
    [self.view addSubview:_collectionView];

    _refreshControl = [UIRefreshControl new];
    _refreshControl.tintColor = SPTheme.accentColor;
    [_refreshControl addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    _collectionView.refreshControl = _refreshControl;

    [_ambientGradient mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.height.mas_equalTo(280);
    }];
    [_topBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop);
        make.left.right.equalTo(self.view);
    }];
    [avatarButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.topBar).offset(10);
        make.left.equalTo(self.topBar).offset(SPMarginHorizontal);
        make.size.mas_equalTo(CGSizeMake(34, 34));
    }];
    [_greetingLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(avatarButton.mas_right).offset(12);
        make.centerY.equalTo(avatarButton);
    }];
    [actionStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.topBar).offset(-6);
        make.centerY.equalTo(avatarButton);
    }];
    [chipStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(avatarButton.mas_bottom).offset(14);
        make.left.equalTo(self.topBar).offset(SPMarginHorizontal);
        make.bottom.equalTo(self.topBar).offset(-8);
    }];
    [_topBarHairline mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.topBar);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [_collectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.topBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
}

- (SPScaleButton *)topIconButton:(NSString *)symbol action:(SEL)action {
    SPScaleButton *btn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [btn sp_setSymbol:symbol size:19 weight:UIImageSymbolWeightMedium animated:NO];
    btn.tintColor = SPTheme.textPrimaryColor;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [btn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    return btn;
}

- (UICollectionViewLayout *)createLayout {
    UICollectionViewCompositionalLayoutConfiguration *config = [UICollectionViewCompositionalLayoutConfiguration new];
    NSCollectionLayoutSize *footerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:56]];
    NSCollectionLayoutBoundarySupplementaryItem *footer = [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:footerSize
                                                                                                                                  elementKind:SPHomeGlobalFooterKind
                                                                                                                                    alignment:NSRectAlignmentBottom];
    config.boundarySupplementaryItems = @[footer];

    __weak typeof(self) weakSelf = self;
    return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> env) {
        if (sectionIndex < 0 || sectionIndex >= (NSInteger)weakSelf.visibleSections.count) return nil;
        SPHomeSection *model = weakSelf.visibleSections[sectionIndex];

        if (model.style == SPHomeSectionStyleShortcut) {
            NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:0.5]
                                                                              heightDimension:[NSCollectionLayoutDimension absoluteDimension:56]];
            NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
            NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                               heightDimension:[NSCollectionLayoutDimension absoluteDimension:56]];
            NSCollectionLayoutGroup *group = nil;
            if (@available(iOS 16.0, *)) {
                group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize repeatingSubitem:item count:2];
            } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:2];
#pragma clang diagnostic pop
            }
            group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:8];
            NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
            section.interGroupSpacing = 8;
            section.contentInsets = NSDirectionalEdgeInsetsMake(8, SPMarginHorizontal, 16, SPMarginHorizontal);
            return section;
        }

        BOOL isArtist = (model.style == SPHomeSectionStyleArtist);
        CGFloat width = isArtist ? 136 : 148;
        CGFloat height = isArtist ? 182 : 198;
        NSCollectionLayoutSize *size = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:width]
                                                                      heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:size];
        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size subitems:@[item]];

        NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
        section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuous;
        section.interGroupSpacing = 12;
        section.contentInsets = NSDirectionalEdgeInsetsMake(0, SPMarginHorizontal, 20, SPMarginHorizontal);

        NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                            heightDimension:[NSCollectionLayoutDimension absoluteDimension:44]];
        NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
                                                                                                                                      elementKind:UICollectionElementKindSectionHeader
                                                                                                                                        alignment:NSRectAlignmentTop];
        section.boundarySupplementaryItems = @[header];
        return section;
    } configuration:config];
}

#pragma mark - Data

- (void)showSkeleton {
    if (self.skeletonView) return;
    self.skeletonView = [SPSkeletonView homeSkeletonView];
    [self.view addSubview:self.skeletonView];
    [self.skeletonView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.collectionView);
    }];
}

- (void)loadData {
    [self loadDataForCurrentCategoryForceRefresh:NO];
}

- (void)refreshData {
    [self loadDataForCurrentCategoryForceRefresh:YES];
}

- (void)loadDataForCurrentCategoryForceRefresh:(BOOL)forceRefresh {
    SPHomeCategory category = [self currentCategory];
    NSNumber *key = @(category);
    self.nextPageByCategory[key] = @1;
    self.hasMoreByCategory[key] = @YES;
    [self.loadingMoreCategories removeObject:key];
    self.categoryRequestToken += 1;
    NSUInteger token = self.categoryRequestToken;

    __weak typeof(self) weakSelf = self;
    void (^handler)(NSArray<SPHomeSection *> *, NSError *) = ^(NSArray<SPHomeSection *> *sections, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        BOOL isCurrentRequest = (strongSelf.categoryRequestToken == token && [strongSelf currentCategory] == category);
        if (!error) {
            strongSelf.sectionsByCategory[key] = sections ?: @[];
        }
        if (!isCurrentRequest) return;

        [strongSelf.refreshControl endRefreshing];
        [strongSelf.skeletonView dismissAnimated:YES];
        strongSelf.skeletonView = nil;
        if (error) {
            [SPToast showMessage:error.localizedDescription ?: @"加载首页失败"];
            return;
        }
        [strongSelf applyCurrentCategorySectionsAndScrollTop:NO];
        [strongSelf playInitialEntranceIfNeeded];
    };
    if (forceRefresh) {
        [[SPMusicRepository shared] refreshHomeSectionsForCategory:category completion:handler];
    } else {
        [[SPMusicRepository shared] fetchHomeSectionsForCategory:category completion:handler];
    }
}

- (void)loadMoreSections {
    SPHomeCategory category = [self currentCategory];
    NSNumber *key = @(category);
    BOOL hasMore = self.hasMoreByCategory[key] ? self.hasMoreByCategory[key].boolValue : YES;
    if ([self.loadingMoreCategories containsObject:key] || !hasMore) return;

    NSInteger requestingPage = self.nextPageByCategory[key] ? self.nextPageByCategory[key].integerValue : 1;
    NSUInteger token = self.categoryRequestToken;
    [self.loadingMoreCategories addObject:key];
    [self updateFooterState];

    __weak typeof(self) weakSelf = self;
    [[SPMusicRepository shared] fetchHomeMoreSectionsForCategory:category
                                                            page:requestingPage
                                                      completion:^(NSArray<SPHomeSection *> *newSections, BOOL moreAvailable, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.loadingMoreCategories removeObject:key];
        if (strongSelf.categoryRequestToken != token) {
            return;
        }
        if (error) {
            if ([strongSelf currentCategory] == category) {
                [strongSelf updateFooterState];
            }
            return;
        }
        strongSelf.nextPageByCategory[key] = @(requestingPage + 1);
        strongSelf.hasMoreByCategory[key] = @(moreAvailable);

        if (newSections.count > 0) {
            NSMutableArray<SPHomeSection *> *merged = [NSMutableArray arrayWithArray:strongSelf.sectionsByCategory[key] ?: @[]];
            [merged addObjectsFromArray:newSections];
            strongSelf.sectionsByCategory[key] = merged;

            if ([strongSelf currentCategory] == category) {
                NSInteger oldCount = strongSelf.visibleSections.count;
                strongSelf.visibleSections = merged;
                if (strongSelf.collectionView.numberOfSections == oldCount &&
                    (NSInteger)merged.count == oldCount + (NSInteger)newSections.count) {
                    NSIndexSet *added = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(oldCount, newSections.count)];
                    [UIView performWithoutAnimation:^{
                        [strongSelf.collectionView performBatchUpdates:^{
                            [strongSelf.collectionView insertSections:added];
                        } completion:nil];
                    }];
                } else {
                    [strongSelf.collectionView reloadData];
                }
            }
        }
        if ([strongSelf currentCategory] == category) {
            [strongSelf updateFooterState];
        }
    }];
}

- (void)updateFooterState {
    SPHomeCategory category = [self currentCategory];
    NSNumber *key = @(category);
    BOOL hasMore = self.hasMoreByCategory[key] ? self.hasMoreByCategory[key].boolValue : YES;
    BOOL loading = [self.loadingMoreCategories containsObject:key];
    [self.footerView configureLoading:loading
                              hasMore:hasMore
                            isPodcast:(category == SPHomeCategoryPodcast)
                              visible:(self.visibleSections.count > 0)];
}

- (void)playInitialEntranceIfNeeded {
    if (self.hasPlayedInitialEntrance || UIAccessibilityIsReduceMotionEnabled()) {
        self.hasPlayedInitialEntrance = YES;
        return;
    }
    self.hasPlayedInitialEntrance = YES;
    [self.collectionView layoutIfNeeded];
    NSArray<UICollectionViewCell *> *cells = [self.collectionView visibleCells];
    NSArray<UICollectionViewCell *> *sorted = [cells sortedArrayUsingComparator:^NSComparisonResult(UICollectionViewCell *a, UICollectionViewCell *b) {
        CGFloat dy = CGRectGetMinY(a.frame) - CGRectGetMinY(b.frame);
        if (fabs(dy) > 8) return dy < 0 ? NSOrderedAscending : NSOrderedDescending;
        return CGRectGetMinX(a.frame) < CGRectGetMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];

    for (NSInteger i = 0; i < MIN((NSInteger)sorted.count, 10); i++) {
        UICollectionViewCell *cell = sorted[i];
        cell.alpha = 0;
        cell.transform = CGAffineTransformMakeTranslation(0, 12);
        [UIView animateWithDuration:0.32
                              delay:i * 0.04
             usingSpringWithDamping:0.9
              initialSpringVelocity:0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            cell.alpha = 1;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)updateAmbientColorFromTrack:(nullable SPTrack *)track {
    if (!track || !track.coverURL.length) {
        UIColor *ambientTop = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight)
                ? [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:0.10]
                : [UIColor sp_colorWithHex:0x2A1F4A];
        }];
        [self.ambientGradient setColors:@[ambientTop, SPTheme.backgroundColor] animated:YES];
        return;
    }
    NSURL *url = [NSURL URLWithString:track.coverURL];
    if (!url) return;
    __weak typeof(self) weakSelf = self;
    NSString *trackId = track.identifier;
    [[SDWebImageManager sharedManager] loadImageWithURL:url options:SDWebImageRetryFailed progress:nil completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        if (!image || !weakSelf) return;
        [UIImage sp_extractDominantColorForImage:image cacheKey:track.coverURL completion:^(UIColor *color) {
            if (![[SPPlayerService shared].currentTrack.identifier isEqualToString:trackId]) return;
            UIColor *dynamicTop = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
                return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight)
                    ? [color colorWithAlphaComponent:0.16]
                    : [color sp_darkenedBy:0.25];
            }];
            [weakSelf.ambientGradient setColors:@[dynamicTop, SPTheme.backgroundColor] animated:YES];
        }];
    }];
}

- (void)playerDidChangeTrack:(SPPlayerService *)player {
    [self updateAmbientColorFromTrack:player.currentTrack];
}

- (void)applyCurrentCategorySectionsAndScrollTop:(BOOL)scrollTop {
    NSArray<SPHomeSection *> *cached = self.sectionsByCategory[@([self currentCategory])];
    self.visibleSections = cached ?: @[];
    [self.collectionView reloadData];
    if (scrollTop && self.visibleSections.count > 0) {
        [self.collectionView setContentOffset:CGPointZero animated:NO];
    }
    [self updateFooterState];
}

#pragma mark - Actions

- (void)updateChipStyles {
    UIColor *selectedTextColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
        return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) ? UIColor.whiteColor : UIColor.blackColor;
    }];
    for (UIButton *btn in self.chipButtons) {
        BOOL selected = (btn.tag == self.selectedChipIndex);
        UIButtonConfiguration *config = [btn.configuration copy];
        config.baseBackgroundColor = selected ? SPTheme.accentColor : SPTheme.highlightColor;
        config.baseForegroundColor = selected ? selectedTextColor : SPTheme.textPrimaryColor;
        btn.configuration = config;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateChipStyles];
    }
}

- (void)chipTapped:(UIButton *)sender {
    [SPHaptics light];
    if (self.selectedChipIndex == sender.tag) return;
    self.selectedChipIndex = sender.tag;
    [self updateChipStyles];

    SPHomeCategory category = [self currentCategory];
    NSArray<SPHomeSection *> *cached = self.sectionsByCategory[@(category)];
    if (cached.count > 0) {
        self.categoryRequestToken += 1;
        [self.skeletonView dismissAnimated:YES];
        self.skeletonView = nil;
        [self applyCurrentCategorySectionsAndScrollTop:YES];
    } else {
        self.visibleSections = @[];
        [self.collectionView reloadData];
        [self updateFooterState];
        [self showSkeleton];
        [self loadDataForCurrentCategoryForceRefresh:NO];
    }
}

- (void)roamTapped {
    [SPHaptics light];
    [self.navigationController pushViewController:[SPMoodRoamViewController new] animated:YES];
}

- (void)statsTapped {
    [SPHaptics light];
    [self.navigationController pushViewController:[SPListeningStatsViewController new] animated:YES];
}

- (void)settingsTapped {
    [SPHaptics light];
    [self.navigationController pushViewController:[SPSettingsViewController new] animated:YES];
}

#pragma mark - UICollectionViewDataSource / Delegate

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.visibleSections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.visibleSections[section].items.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SPHomeSection *section = self.visibleSections[indexPath.section];
    id<SPMediaItem> item = section.items[indexPath.item];
    if (section.style == SPHomeSectionStyleShortcut) {
        SPHomeShortcutCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[SPHomeShortcutCell reuseId] forIndexPath:indexPath];
        [cell configureWithItem:item];
        return cell;
    }
    SPMediaCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[SPMediaCardCell reuseId] forIndexPath:indexPath];
    [cell configureWithItem:item];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if ([kind isEqualToString:SPHomeGlobalFooterKind]) {
        SPHomeLoadMoreFooterView *footer = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                              withReuseIdentifier:[SPHomeLoadMoreFooterView reuseId]
                                                                                     forIndexPath:indexPath];
        self.footerView = footer;
        [self updateFooterState];
        return footer;
    }
    SPHomeSectionHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                         withReuseIdentifier:[SPHomeSectionHeaderView reuseId]
                                                                                forIndexPath:indexPath];
    header.titleLabel.text = self.visibleSections[indexPath.section].title;
    return header;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // 顶部氛围渐变随滚动做柔和视差淡出，顶栏细线随滚动浮现
    CGFloat offsetY = MAX(0.0, scrollView.contentOffset.y);
    self.topBarHairline.alpha = MIN(MAX(offsetY / 20.0, 0.0), 1.0);
    CGFloat fade = MIN(MAX(1.0 - offsetY / 180.0, 0.0), 1.0);
    self.ambientGradient.alpha = fade;
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        self.ambientGradient.transform = CGAffineTransformMakeTranslation(0, -MIN(offsetY, 180.0) * 0.35);
    }

    SPHomeCategory category = [self currentCategory];
    NSNumber *key = @(category);
    BOOL hasMore = self.hasMoreByCategory[key] ? self.hasMoreByCategory[key].boolValue : YES;
    if ([self.loadingMoreCategories containsObject:key] || !hasMore || self.visibleSections.count == 0) {
        return;
    }
    CGFloat height = CGRectGetHeight(scrollView.bounds);
    CGFloat contentHeight = scrollView.contentSize.height;
    if (height <= 0 || contentHeight <= height) return;
    if (scrollView.contentOffset.y + height >= contentHeight - 280.0) {
        [self loadMoreSections];
    }
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    id<SPMediaItem> item = self.visibleSections[indexPath.section].items[indexPath.item];
    SPDetailViewController *detail = [[SPDetailViewController alloc] initWithMediaItem:item];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
