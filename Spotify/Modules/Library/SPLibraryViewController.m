//
//  SPLibraryViewController.m
//  Spotify
//

#import "SPLibraryViewController.h"
#import "SPMediaCells.h"
#import "SPUserAvatarButton.h"
#import "SPScaleButton.h"
#import "SPDetailViewController.h"
#import "SPMusicRepository.h"
#import "SPLibraryStore.h"
#import "SPLibraryActionSheet.h"
#import "SPNeteaseSession.h"
#import "SPAuthService.h"
#import "SPPlaylist.h"
#import "SPHaptics.h"
#import "SPToast.h"

#pragma mark - Split Library Section Header

@interface SPLibrarySectionHeaderView : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) SPScaleButton *actionButton;
@property (nonatomic, copy, nullable) void (^actionHandler)(void);
@end

@implementation SPLibrarySectionHeaderView

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _titleLabel = [UILabel new];
        _titleLabel.font = [SPTheme fontOfSize:18 weight:UIFontWeightBold];
        _titleLabel.textColor = SPTheme.textPrimaryColor;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [SPTheme fontOfSize:12 weight:UIFontWeightRegular];
        _subtitleLabel.textColor = SPTheme.textSecondaryColor;

        UIStackView *leftStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        leftStack.axis = UILayoutConstraintAxisVertical;
        leftStack.spacing = 2;
        [self addSubview:leftStack];

        UIButtonConfiguration *actionConfig = [UIButtonConfiguration plainButtonConfiguration];
        actionConfig.contentInsets = NSDirectionalEdgeInsetsMake(0, 12, 0, 12);
        actionConfig.baseForegroundColor = SPTheme.textPrimaryColor;
        actionConfig.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
            NSMutableDictionary *attrs = [incoming mutableCopy];
            attrs[NSFontAttributeName] = [SPTheme fontOfSize:12.5 weight:UIFontWeightSemibold];
            return attrs;
        };
        _actionButton = [SPScaleButton buttonWithType:UIButtonTypeCustom];
        _actionButton.configuration = actionConfig;
        [_actionButton setTitle:@"＋ 新建歌单" forState:UIControlStateNormal];
        _actionButton.backgroundColor = SPTheme.highlightColor;
        _actionButton.layer.cornerRadius = 15;
        _actionButton.layer.cornerCurve = kCACornerCurveContinuous;
        _actionButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _actionButton.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        [_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_actionButton];

        [_actionButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_actionButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        [_actionButton mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(self).offset(-SPMarginHorizontal);
            make.centerY.equalTo(leftStack);
            make.height.mas_equalTo(30);
        }];
        [leftStack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(SPMarginHorizontal);
            make.right.lessThanOrEqualTo(self.actionButton.mas_left).offset(-12);
            make.bottom.equalTo(self).offset(-8);
            make.top.greaterThanOrEqualTo(self).offset(6);
        }];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
               actionTitle:(nullable NSString *)actionTitle
             actionHandler:(void (^ _Nullable)(void))handler {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.actionButton.hidden = (actionTitle.length == 0);
    if (actionTitle.length > 0) {
        [self.actionButton setTitle:actionTitle forState:UIControlStateNormal];
    }
    self.actionHandler = handler;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.actionButton.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    }
}

- (void)actionTapped {
    if (self.actionHandler) self.actionHandler();
}

@end

#pragma mark - SPLibraryViewController

@interface SPLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, SPAuthObserver>
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) SPScaleButton *toggleLayoutButton;
@property (nonatomic, strong) NSArray<UIButton *> *chipButtons;
@property (nonatomic, assign) NSInteger selectedFilterIndex;
@property (nonatomic, assign) BOOL isGridMode;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, copy) NSArray<id<SPMediaItem>> *remoteItems;
@property (nonatomic, copy) NSArray<id<SPMediaItem>> *personalItems;
@property (nonatomic, copy) NSArray<id<SPMediaItem>> *recommendedItems;
@end

@implementation SPLibraryViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    _remoteItems = @[];
    _personalItems = @[];
    _recommendedItems = @[];
    [self setupViews];
    [self rebuildSections];

    [[SPAuthService shared] addObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(musicSourceDidChange)
                                                 name:SPMusicSourceDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(libraryDidUpdate)
                                                 name:SPLibraryDidUpdateNotification
                                               object:nil];
    [self loadData];
}

- (void)musicSourceDidChange {
    self.remoteItems = @[];
    [self rebuildSections];
    [self loadData];
}

- (void)libraryDidUpdate {
    [self rebuildSections];
}

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    [self loadData];
}

- (void)setupViews {
    _topBar = [UIView new];
    _topBar.backgroundColor = SPTheme.backgroundColor;
    [self.view addSubview:_topBar];

    SPUserAvatarButton *avatarButton = [[SPUserAvatarButton alloc] initWithDiameter:34];
    [_topBar addSubview:avatarButton];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"音乐库";
    titleLabel.font = SPTheme.largeTitleFont;
    titleLabel.textColor = SPTheme.textPrimaryColor;
    [_topBar addSubview:titleLabel];

    SPScaleButton *addButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [addButton sp_setSymbol:@"plus" size:21 weight:UIImageSymbolWeightMedium animated:NO];
    addButton.tintColor = SPTheme.textPrimaryColor;
    [addButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topBar addSubview:addButton];

    _toggleLayoutButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_toggleLayoutButton sp_setSymbol:@"square.grid.2x2" size:19 weight:UIImageSymbolWeightMedium animated:NO];
    _toggleLayoutButton.tintColor = SPTheme.textPrimaryColor;
    [_toggleLayoutButton addTarget:self action:@selector(toggleLayoutTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topBar addSubview:_toggleLayoutButton];

    NSArray *filters = @[@"全部", @"歌单", @"专辑", @"艺人"];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)filters.count; i++) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.title = filters[i];
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.contentInsets = NSDirectionalEdgeInsetsMake(7, 15, 7, 15);
        config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
            NSMutableDictionary *attrs = [incoming mutableCopy];
            attrs[NSFontAttributeName] = [SPTheme fontOfSize:13 weight:UIFontWeightMedium];
            return attrs;
        };
        UIButton *btn = [UIButton buttonWithConfiguration:config primaryAction:nil];
        btn.tag = i;
        [btn addTarget:self action:@selector(filterTapped:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:btn];
    }
    _chipButtons = buttons;
    [self updateChipStyles];

    UIStackView *chipStack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    chipStack.spacing = 8;
    [_topBar addSubview:chipStack];

    UICollectionViewFlowLayout *flow = [UICollectionViewFlowLayout new];
    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:flow];
    _collectionView.backgroundColor = SPTheme.backgroundColor;
    _collectionView.showsVerticalScrollIndicator = NO;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    [_collectionView registerClass:SPMediaRowCollectionCell.class forCellWithReuseIdentifier:[SPMediaRowCollectionCell reuseId]];
    [_collectionView registerClass:SPMediaCardCell.class forCellWithReuseIdentifier:[SPMediaCardCell reuseId]];
    [_collectionView registerClass:SPLibrarySectionHeaderView.class
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:[SPLibrarySectionHeaderView reuseId]];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleCellLongPress:)];
    longPress.minimumPressDuration = 0.45;
    [_collectionView addGestureRecognizer:longPress];
    [self.view addSubview:_collectionView];

    _refreshControl = [UIRefreshControl new];
    _refreshControl.tintColor = SPTheme.accentColor;
    [_refreshControl addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    _collectionView.refreshControl = _refreshControl;

    [_topBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop);
        make.left.right.equalTo(self.view);
    }];
    [avatarButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.topBar).offset(10);
        make.left.equalTo(self.topBar).offset(SPMarginHorizontal);
        make.size.mas_equalTo(CGSizeMake(34, 34));
    }];
    [titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(avatarButton.mas_right).offset(12);
        make.centerY.equalTo(avatarButton);
    }];
    [_toggleLayoutButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.topBar).offset(-10);
        make.centerY.equalTo(avatarButton);
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    [addButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.toggleLayoutButton.mas_left);
        make.centerY.equalTo(avatarButton);
        make.size.mas_equalTo(CGSizeMake(40, 40));
    }];
    [chipStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(avatarButton.mas_bottom).offset(14);
        make.left.equalTo(self.topBar).offset(SPMarginHorizontal);
        make.bottom.equalTo(self.topBar).offset(-10);
    }];
    [_collectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.topBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
}

#pragma mark - Data

- (void)loadData {
    __weak typeof(self) weakSelf = self;
    [[SPMusicRepository shared] fetchLibraryItemsWithCompletion:^(NSArray<id<SPMediaItem>> *items, NSError *error) {
        [weakSelf.refreshControl endRefreshing];
        if (error) {
            [SPToast showMessage:error.localizedDescription ?: @"加载音乐库失败"];
            return;
        }
        weakSelf.remoteItems = items ?: @[];
        [weakSelf rebuildSections];
    }];
}

- (NSArray<id<SPMediaItem>> *)itemsMatchingCurrentFilter:(NSArray<id<SPMediaItem>> *)source {
    if (self.selectedFilterIndex == 0) return source;
    SPMediaType target = SPMediaTypePlaylist;
    if (self.selectedFilterIndex == 2) target = SPMediaTypeAlbum;
    else if (self.selectedFilterIndex == 3) target = SPMediaTypeArtist;

    return [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id<SPMediaItem> item, id _) {
        return item.mediaType == target;
    }]];
}

- (void)rebuildSections {
    SPLibraryStore *store = [SPLibraryStore shared];
    NSMutableArray<id<SPMediaItem>> *rawPersonal = [NSMutableArray array];
    NSMutableSet<NSString *> *personalIds = [NSMutableSet set];

    // 1. 始终以用户个人音乐为核心区首项：已点赞歌曲 + 自建歌单 + 关注艺人
    SPPlaylist *liked = [store likedSongsPlaylist];
    [rawPersonal addObject:liked];
    if (liked.identifier.length) [personalIds addObject:liked.identifier];

    for (SPPlaylist *pl in store.userPlaylists) {
        [rawPersonal addObject:pl];
        if (pl.identifier.length) [personalIds addObject:pl.identifier];
    }

    // 2. 若已登录真实网易云账号，把账号所属云歌单同步进「我的音乐」
    NSString *signedNeteaseUID = [SPNeteaseSession shared].userCookie.length > 0 ? [SPNeteaseSession shared].userId : nil;
    NSMutableArray<id<SPMediaItem>> *rawRecommended = [NSMutableArray array];
    for (id<SPMediaItem> item in self.remoteItems) {
        if ([item isKindOfClass:SPPlaylist.class] && signedNeteaseUID.length > 0) {
            SPPlaylist *pl = (SPPlaylist *)item;
            if ([pl.creatorUserId isEqualToString:signedNeteaseUID] && ![personalIds containsObject:pl.identifier]) {
                [rawPersonal addObject:pl];
                [personalIds addObject:pl.identifier];
                continue;
            }
        }
        if (item.identifier.length && [personalIds containsObject:item.identifier]) continue;
        [rawRecommended addObject:item];
    }

    for (SPArtist *artist in store.followedArtists) {
        [rawPersonal addObject:artist];
    }

    self.personalItems = [self itemsMatchingCurrentFilter:rawPersonal];
    self.recommendedItems = [self itemsMatchingCurrentFilter:rawRecommended];
    [self.collectionView reloadData];
}

- (NSArray<id<SPMediaItem>> *)itemsForSection:(NSInteger)section {
    return (section == 0) ? self.personalItems : self.recommendedItems;
}

#pragma mark - Actions

- (void)updateChipStyles {
    UIColor *selectedTextColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
        return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) ? UIColor.whiteColor : UIColor.blackColor;
    }];
    for (UIButton *btn in self.chipButtons) {
        BOOL selected = (btn.tag == self.selectedFilterIndex);
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

- (void)filterTapped:(UIButton *)sender {
    [SPHaptics light];
    self.selectedFilterIndex = sender.tag;
    [self updateChipStyles];
    [self rebuildSections];
}

- (void)toggleLayoutTapped {
    [SPHaptics light];
    self.isGridMode = !self.isGridMode;
    NSString *symbol = self.isGridMode ? @"list.bullet" : @"square.grid.2x2";
    [self.toggleLayoutButton sp_setSymbol:symbol size:19 weight:UIImageSymbolWeightMedium animated:YES];
    [self.collectionView reloadData];
}

- (void)addTapped {
    [SPLibraryActionSheet presentCreatePlaylistAlertFrom:self completion:nil];
}

- (void)handleCellLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    CGPoint pt = [lp locationInView:self.collectionView];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:pt];
    if (!indexPath) return;

    NSArray<id<SPMediaItem>> *sectionItems = [self itemsForSection:indexPath.section];
    if (indexPath.item >= (NSInteger)sectionItems.count) return;
    id<SPMediaItem> item = sectionItems[indexPath.item];
    if (![[SPLibraryStore shared] isUserCreatedPlaylistId:item.identifier]) return;

    [SPHaptics medium];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:item.title
                                                                   message:@"管理个人歌单"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除此歌单" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[SPLibraryStore shared] deletePlaylistWithId:item.identifier];
        [SPToast showMessage:@"已删除歌单"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - UICollectionViewDataSource / DelegateFlowLayout

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 2;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self itemsForSection:section].count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    id<SPMediaItem> item = [self itemsForSection:indexPath.section][indexPath.item];
    if (self.isGridMode) {
        SPMediaCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[SPMediaCardCell reuseId] forIndexPath:indexPath];
        [cell configureWithItem:item];
        return cell;
    }
    SPMediaRowCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[SPMediaRowCollectionCell reuseId] forIndexPath:indexPath];
    [cell.rowView configureWithItem:item];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    SPLibrarySectionHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                            withReuseIdentifier:[SPLibrarySectionHeaderView reuseId]
                                                                                   forIndexPath:indexPath];
    __weak typeof(self) weakSelf = self;
    if (indexPath.section == 0) {
        NSString *sub = [NSString stringWithFormat:@"已点赞歌曲 · 自建歌单 · 关注艺人 (%lu)",
                         (unsigned long)self.personalItems.count];
        [header configureWithTitle:@"我的音乐"
                          subtitle:sub
                       actionTitle:@"＋ 新建歌单"
                     actionHandler:^{ [weakSelf addTapped]; }];
    } else {
        NSString *sub = [NSString stringWithFormat:@"为你挑选的精选歌单、新碟与艺人 (%lu)",
                         (unsigned long)self.recommendedItems.count];
        [header configureWithTitle:@"网易云精选推荐"
                          subtitle:sub
                       actionTitle:nil
                     actionHandler:nil];
    }
    return header;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
referenceSizeForHeaderInSection:(NSInteger)section {
    if ([self itemsForSection:section].count == 0) return CGSizeZero;
    return CGSizeMake(CGRectGetWidth(collectionView.bounds), 54);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView
                        layout:(UICollectionViewLayout *)collectionViewLayout
        insetForSectionAtIndex:(NSInteger)section {
    if ([self itemsForSection:section].count == 0) return UIEdgeInsetsZero;
    return UIEdgeInsetsMake(4, SPMarginHorizontal, section == 0 ? 22 : 28, SPMarginHorizontal);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return self.isGridMode ? 16 : 8;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return self.isGridMode ? 16 : 0;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat totalWidth = CGRectGetWidth(collectionView.bounds);
    if (self.isGridMode) {
        CGFloat width = floor((totalWidth - 48) / 2.0);
        return CGSizeMake(MAX(width, 100), width + 52);
    }
    return CGSizeMake(MAX(totalWidth - SPMarginHorizontal * 2, 100), 72);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    id<SPMediaItem> item = [self itemsForSection:indexPath.section][indexPath.item];
    SPDetailViewController *detail = [[SPDetailViewController alloc] initWithMediaItem:item];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
