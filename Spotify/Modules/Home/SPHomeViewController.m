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
#import "SPActivityViewController.h"
#import "SPHistoryViewController.h"
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
@property (nonatomic, assign) BOOL isLoadingMore;
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
    self.selectedChipIndex = 0;
    [self updateChipStyles];
    [self.sectionsByCategory removeAllObjects];
    [self.nextPageByCategory removeAllObjects];
    [self.hasMoreByCategory removeAllObjects];
    self.isLoadingMore = NO;
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

    SPUserAvatarButton *avatarButton = [[SPUserAvatarButton alloc] initWithDiameter:34];
    [_topBar addSubview:avatarButton];

    _greetingLabel = [UILabel new];
    _greetingLabel.text = [SPFormatter greeting];
    _greetingLabel.font = SPTheme.largeTitleFont;
    _greetingLabel.textColor = SPTheme.textPrimaryColor;
    [_topBar addSubview:_greetingLabel];

    SPScaleButton *bellBtn = [self topIconButton:@"bell" action:@selector(bellTapped)];
    SPScaleButton *historyBtn = [self topIconButton:@"clock.arrow.circlepath" action:@selector(historyTapped)];
    SPScaleButton *settingsBtn = [self topIconButton:@"gearshape" action:@selector(settingsTapped)];
    UIStackView *actionStack = [[UIStackView alloc] initWithArrangedSubviews:@[bellBtn, historyBtn, settingsBtn]];
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
        UIButton *chip = [UIButton buttonWithConfiguration:config primaryAction:nil];
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
        make.right.equalTo(self.topBar).offset(-8);
        make.centerY.equalTo(avatarButton);
    }];
    [chipStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(avatarButton.mas_bottom).offset(14);
        make.left.equalTo(self.topBar).offset(SPMarginHorizontal);
        make.bottom.equalTo(self.topBar).offset(-8);
    }];
    [_collectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.topBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
}

- (SPScaleButton *)topIconButton:(NSString *)symbol action:(SEL)action {
    SPScaleButton *btn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [btn sp_setSymbol:symbol size:20 weight:UIImageSymbolWeightRegular animated:NO];
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
    self.isLoadingMore = NO;
    self.categoryRequestToken += 1;
    NSUInteger token = self.categoryRequestToken;

    __weak typeof(self) weakSelf = self;
    void (^handler)(NSArray<SPHomeSection *> *, NSError *) = ^(NSArray<SPHomeSection *> *sections, NSError *error) {
        if (!weakSelf) return;
        [weakSelf.refreshControl endRefreshing];
        [weakSelf.skeletonView dismissAnimated:YES];
        weakSelf.skeletonView = nil;
        if (error) {
            [SPToast showMessage:error.localizedDescription ?: @"加载首页失败"];
            return;
        }
        weakSelf.sectionsByCategory[key] = sections ?: @[];
        if (weakSelf.categoryRequestToken == token && [weakSelf currentCategory] == category) {
            [weakSelf applyCurrentCategorySectionsAndScrollTop:NO];
            [weakSelf playInitialEntranceIfNeeded];
        }
        [weakSelf warmupPlayerIfNeededWithSections:(sections ?: @[])];
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
    if (self.isLoadingMore || !hasMore) return;

    NSInteger requestingPage = self.nextPageByCategory[key] ? self.nextPageByCategory[key].integerValue : 1;
    self.isLoadingMore = YES;
    [self updateFooterState];

    __weak typeof(self) weakSelf = self;
    [[SPMusicRepository shared] fetchHomeMoreSectionsForCategory:category
                                                            page:requestingPage
                                                      completion:^(NSArray<SPHomeSection *> *newSections, BOOL moreAvailable, NSError *error) {
        if (!weakSelf) return;
        weakSelf.isLoadingMore = NO;
        if (error) {
            [weakSelf updateFooterState];
            return;
        }
        weakSelf.nextPageByCategory[key] = @(requestingPage + 1);
        weakSelf.hasMoreByCategory[key] = @(moreAvailable);

        if (newSections.count > 0) {
            NSMutableArray<SPHomeSection *> *merged = [NSMutableArray arrayWithArray:weakSelf.sectionsByCategory[key] ?: @[]];
            [merged addObjectsFromArray:newSections];
            weakSelf.sectionsByCategory[key] = merged;

            if ([weakSelf currentCategory] == category) {
                NSInteger oldCount = weakSelf.visibleSections.count;
                weakSelf.visibleSections = merged;
                if (weakSelf.collectionView.numberOfSections == oldCount) {
                    NSIndexSet *added = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(oldCount, newSections.count)];
                    [UIView performWithoutAnimation:^{
                        [weakSelf.collectionView performBatchUpdates:^{
                            [weakSelf.collectionView insertSections:added];
                        } completion:nil];
                    }];
                } else {
                    [weakSelf.collectionView reloadData];
                }
            }
        }
        [weakSelf updateFooterState];
    }];
}

- (void)updateFooterState {
    SPHomeCategory category = [self currentCategory];
    BOOL hasMore = self.hasMoreByCategory[@(category)] ? self.hasMoreByCategory[@(category)].boolValue : YES;
    [self.footerView configureLoading:self.isLoadingMore
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

- (void)updateAmbientColorFromTrack:(SPTrack *)track {
    if (!track.coverURL.length) return;
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

- (void)warmupPlayerIfNeededWithSections:(NSArray<SPHomeSection *> *)sections {
    if ([SPPlayerService shared].currentTrack != nil) return;
    SPPlaylist *firstEmptyPlaylist = nil;
    for (SPHomeSection *section in sections) {
        for (id<SPMediaItem> item in section.items) {
            if ([item isKindOfClass:SPPlaylist.class]) {
                SPPlaylist *playlist = (SPPlaylist *)item;
                if (playlist.tracks.count > 0) {
                    [[SPPlayerService shared] prepareTracks:playlist.tracks startIndex:0 contextTitle:playlist.name];
                    return;
                }
                if (!firstEmptyPlaylist && playlist.identifier.length > 0) {
                    firstEmptyPlaylist = playlist;
                }
            } else if ([item isKindOfClass:SPAlbum.class]) {
                SPAlbum *album = (SPAlbum *)item;
                if (album.tracks.count > 0) {
                    [[SPPlayerService shared] prepareTracks:album.tracks startIndex:0 contextTitle:album.name];
                    return;
                }
            }
        }
    }
    if (firstEmptyPlaylist) {
        [[SPMusicRepository shared] fetchPlaylistWithId:firstEmptyPlaylist.identifier completion:^(SPPlaylist *pl, NSError *err) {
            if ([SPPlayerService shared].currentTrack != nil) return;
            if (!err && pl.tracks.count > 0) {
                [[SPPlayerService shared] prepareTracks:pl.tracks startIndex:0 contextTitle:pl.name];
            }
        }];
    }
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
    self.isLoadingMore = NO;

    SPHomeCategory category = [self currentCategory];
    NSArray<SPHomeSection *> *cached = self.sectionsByCategory[@(category)];
    if (cached.count > 0) {
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

- (void)bellTapped {
    [SPHaptics light];
    [self.navigationController pushViewController:[SPActivityViewController new] animated:YES];
}

- (void)historyTapped {
    [SPHaptics light];
    [self.navigationController pushViewController:[SPHistoryViewController new] animated:YES];
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
    SPHomeCategory category = [self currentCategory];
    BOOL hasMore = self.hasMoreByCategory[@(category)] ? self.hasMoreByCategory[@(category)].boolValue : YES;
    if (self.isLoadingMore || !hasMore || self.visibleSections.count == 0) {
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
