//
//  SPDetailViewController.m
//  Spotify
//

#import "SPDetailViewController.h"
#import "SPDetailHeaderView.h"
#import "SPGradientView.h"
#import "SPSkeletonView.h"
#import "SPScaleButton.h"
#import "SPMediaCells.h"
#import "SPMusicRepository.h"
#import "SPLibraryStore.h"
#import "SPLibraryActionSheet.h"
#import "SPPlayerService.h"
#import "UIImage+SPDominantColor.h"
#import "SPPlaylist.h"
#import "SPAlbum.h"
#import "SPArtist.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPDetailViewController () <UITableViewDataSource, UITableViewDelegate, SPPlayerObserver>
@property (nonatomic, strong) id<SPMediaItem> mediaItem;
@property (nonatomic, copy) NSArray<SPTrack *> *tracks;
@property (nonatomic, strong) SPGradientView *gradientView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) SPDetailHeaderView *headerView;
@property (nonatomic, strong, nullable) SPSkeletonView *skeletonView;
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UIView *navBarBackground;
@property (nonatomic, strong) SPScaleButton *backButton;
@property (nonatomic, strong) UILabel *navTitleLabel;
@property (nonatomic, strong) UIColor *currentThemeColor;
@property (nonatomic, assign) CGFloat lastHeaderWidth;
@end

@implementation SPDetailViewController

- (instancetype)initWithMediaItem:(id<SPMediaItem>)item {
    if (self = [super init]) {
        _mediaItem = item;
        _tracks = @[];
        if (item.mediaType == SPMediaTypePlaylist) {
            SPPlaylist *local = [[SPLibraryStore shared] localPlaylistWithId:item.identifier];
            if (local) {
                _mediaItem = local;
                _tracks = local.tracks ?: @[];
            } else {
                SPPlaylist *pl = (SPPlaylist *)item;
                if (pl.tracks.count > 0) {
                    _tracks = pl.tracks;
                } else {
                    SPPlaylist *cached = [[SPMusicRepository shared] cachedPlaylistForId:item.identifier];
                    if (cached.tracks.count > 0) {
                        _mediaItem = cached;
                        _tracks = cached.tracks;
                    }
                }
            }
        } else if (item.mediaType == SPMediaTypeAlbum) {
            SPAlbum *al = (SPAlbum *)item;
            if (al.tracks.count > 0) {
                _tracks = al.tracks;
            } else {
                SPAlbum *cached = [[SPMusicRepository shared] cachedAlbumForId:item.identifier];
                if (cached.tracks.count > 0) {
                    _mediaItem = cached;
                    _tracks = cached.tracks;
                }
            }
        }
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    [self setupViews];
    [[SPPlayerService shared] addObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(libraryDidUpdate)
                                                 name:SPLibraryDidUpdateNotification
                                               object:nil];
    BOOL isLocalPlaylist = ([[SPLibraryStore shared] localPlaylistWithId:self.mediaItem.identifier] != nil);
    if (self.tracks.count == 0 && !isLocalPlaylist) {
        [self loadDetail];
    }
}

- (void)libraryDidUpdate {
    if (self.mediaItem.mediaType == SPMediaTypeArtist) {
        [self.headerView updateFollowState:[[SPLibraryStore shared] isArtistFollowed:self.mediaItem.identifier] animated:YES];
        return;
    }
    [self.headerView updateLikeState:[[SPLibraryStore shared] isCollectionSaved:self.mediaItem.identifier] animated:YES];
    SPPlaylist *local = [[SPLibraryStore shared] localPlaylistWithId:self.mediaItem.identifier];
    if (local) {
        self.mediaItem = local;
        self.tracks = local.tracks ?: @[];
        if (self.skeletonView) {
            [self.skeletonView dismissAnimated:NO];
            self.skeletonView = nil;
        }
        self.navTitleLabel.text = local.title;
        [self.headerView configureWithItem:local
                                    tracks:self.tracks
                                 isPlaying:[self isPlayingCurrentContext]
                            shuffleEnabled:[SPPlayerService shared].isShuffleEnabled];
        [self updateHeaderLayout];
        [self.tableView reloadData];
    } else if (self.mediaItem.mediaType == SPMediaTypePlaylist
               && [[SPLibraryStore shared] isUserCreatedPlaylistId:self.mediaItem.identifier]
               && self.navigationController) {
        if (self.navigationController.topViewController == self) {
            [self.navigationController popViewControllerAnimated:NO];
        } else {
            NSMutableArray<UIViewController *> *vcs = [self.navigationController.viewControllers mutableCopy];
            [vcs removeObject:self];
            [self.navigationController setViewControllers:vcs animated:NO];
        }
    }
}

- (void)setupViews {
    NSString *cacheKey = self.mediaItem.coverURL.length ? self.mediaItem.coverURL : self.mediaItem.identifier;
    UIColor *cachedColor = [UIImage sp_cachedDominantColorForKey:cacheKey];
    UIColor *themeColor = cachedColor ?: (self.mediaItem.themeColor ? [self.mediaItem.themeColor sp_clampedForDarkBackground] : [UIColor sp_colorWithHex:0x3A2E5E]);
    _currentThemeColor = themeColor;
    _gradientView = [SPGradientView new];
    _gradientView.locations = @[@0.0, @0.55, @1.0];
    [self.view addSubview:_gradientView];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.contentInset = UIEdgeInsetsMake(48, 0, 24, 0);
    [_tableView registerClass:SPMediaRowCell.class forCellReuseIdentifier:[SPMediaRowCell reuseId]];
    [self.view addSubview:_tableView];

    _headerView = [SPDetailHeaderView new];
    __weak typeof(self) weakSelf = self;
    _headerView.playHandler = ^{ [weakSelf handleHeaderPlay]; };
    _headerView.shuffleHandler = ^{ [[SPPlayerService shared] toggleShuffle]; };
    _headerView.followHandler = ^{ [weakSelf handleFollowArtist]; };
    _headerView.likeHandler = ^{ [weakSelf handleToggleSaveCollection]; };
    _headerView.moreHandler = ^{ [weakSelf handleHeaderMore]; };
    _headerView.dominantColorHandler = ^(UIColor *color) {
        weakSelf.currentThemeColor = color;
        [weakSelf updateThemeColorsAnimated:YES];
    };
    [_headerView configureWithItem:self.mediaItem tracks:self.tracks isPlaying:[self isPlayingCurrentContext] shuffleEnabled:[SPPlayerService shared].isShuffleEnabled];
    if (self.mediaItem.mediaType == SPMediaTypeArtist) {
        [_headerView updateFollowState:[[SPLibraryStore shared] isArtistFollowed:self.mediaItem.identifier] animated:NO];
    } else {
        [_headerView updateLikeState:[[SPLibraryStore shared] isCollectionSaved:self.mediaItem.identifier] animated:NO];
    }
    _tableView.tableHeaderView = _headerView;

    BOOL isLocalPlaylist = ([[SPLibraryStore shared] localPlaylistWithId:self.mediaItem.identifier] != nil);
    if (self.tracks.count == 0 && !isLocalPlaylist) {
        _skeletonView = [SPSkeletonView detailSkeletonView];
        [self.tableView addSubview:_skeletonView];
    }

    _navBar = [UIView new];
    [self.view addSubview:_navBar];

    _navBarBackground = [UIView new];
    _navBarBackground.alpha = 0;
    [_navBar addSubview:_navBarBackground];

    UIView *navHairline = [UIView new];
    navHairline.backgroundColor = SPTheme.separatorColor;
    [_navBarBackground addSubview:navHairline];
    [navHairline mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.navBarBackground);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];

    _backButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_backButton sp_setSymbol:@"chevron.left" size:18 weight:UIImageSymbolWeightSemibold animated:NO];
    [_backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBar addSubview:_backButton];

    _navTitleLabel = [UILabel new];
    _navTitleLabel.text = self.mediaItem.title;
    _navTitleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
    _navTitleLabel.alpha = 0;
    [_navBar addSubview:_navTitleLabel];

    [self updateThemeColorsAnimated:NO];

    [_gradientView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.height.mas_equalTo(380);
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [_navBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(48);
    }];
    [_navBarBackground mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.navBar);
    }];
    [_backButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.navBar).offset(8);
        make.bottom.equalTo(self.navBar).offset(-2);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [_navTitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.backButton.mas_right).offset(4);
        make.right.equalTo(self.navBar).offset(-56);
        make.centerY.equalTo(self.backButton);
    }];
}

- (void)updateThemeColorsAnimated:(BOOL)animated {
    UIColor *color = self.currentThemeColor ?: [UIColor sp_colorWithHex:0x3A2E5E];
    BOOL isLight = ([SPTheme resolvedTraitCollectionForView:self.view].userInterfaceStyle == UIUserInterfaceStyleLight);
    NSArray<UIColor *> *gradColors = isLight
        ? @[[color colorWithAlphaComponent:0.26], [color colorWithAlphaComponent:0.08], SPTheme.backgroundColor]
        : @[color, [color sp_darkenedBy:0.5], SPTheme.backgroundColor];
    [self.gradientView setColors:gradColors animated:animated];

    UIColor *navBg = isLight
        ? [SPTheme.backgroundColor colorWithAlphaComponent:0.95]
        : [color sp_darkenedBy:0.45];
    self.backButton.tintColor = SPTheme.textPrimaryColor;
    self.navTitleLabel.textColor = SPTheme.textPrimaryColor;
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.35 animations:^{
            self.navBarBackground.backgroundColor = navBg;
        }];
    } else {
        self.navBarBackground.backgroundColor = navBg;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateThemeColorsAnimated:NO];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width > 0 && width != self.lastHeaderWidth) {
        self.lastHeaderWidth = width;
        [self updateHeaderLayout];
    }
}

- (void)updateHeaderLayout {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    if (fabs(CGRectGetWidth(self.headerView.frame) - width) > 0.5) {
        self.headerView.frame = CGRectMake(0, 0, width, CGRectGetHeight(self.headerView.frame));
    }
    [self.headerView setNeedsLayout];
    [self.headerView layoutIfNeeded];
    CGSize target = CGSizeMake(width, UILayoutFittingCompressedSize.height);
    CGFloat height = [self.headerView systemLayoutSizeFittingSize:target
                                    withHorizontalFittingPriority:UILayoutPriorityRequired
                                          verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGRect frame = self.headerView.frame;
    if (fabs(frame.size.height - height) > 0.5 || fabs(frame.size.width - width) > 0.5) {
        self.headerView.frame = CGRectMake(0, 0, width, height);
        self.tableView.tableHeaderView = self.headerView;
    }
    if (self.skeletonView) {
        self.skeletonView.frame = CGRectMake(0, CGRectGetMaxY(self.headerView.frame), width, 420);
    }
}

#pragma mark - Data

- (void)loadDetail {
    __weak typeof(self) weakSelf = self;

    if (self.mediaItem.mediaType == SPMediaTypePlaylist) {
        [[SPMusicRepository shared] fetchPlaylistWithId:self.mediaItem.identifier completion:^(SPPlaylist *playlist, NSError *error) {
            [weakSelf finishLoadingWithItem:playlist ?: weakSelf.mediaItem tracks:playlist.tracks error:error];
        }];
    } else if (self.mediaItem.mediaType == SPMediaTypeAlbum) {
        [[SPMusicRepository shared] fetchAlbumWithId:self.mediaItem.identifier completion:^(SPAlbum *album, NSError *error) {
            [weakSelf finishLoadingWithItem:album ?: weakSelf.mediaItem tracks:album.tracks error:error];
        }];
    } else {
        [[SPMusicRepository shared] fetchArtistTopTracksWithId:self.mediaItem.identifier
                                                    completion:^(SPArtist *artist, NSArray<SPTrack *> *tracks, NSError *error) {
            [weakSelf finishLoadingWithItem:(artist ?: weakSelf.mediaItem) tracks:tracks error:error];
        }];
    }
}

- (void)finishLoadingWithItem:(id<SPMediaItem>)item tracks:(NSArray<SPTrack *> *)tracks error:(NSError *)error {
    [self.skeletonView dismissAnimated:YES];
    self.skeletonView = nil;
    if (error) {
        [SPToast showMessage:error.localizedDescription ?: @"加载失败"];
        return;
    }
    self.mediaItem = item;
    self.tracks = tracks ?: @[];
    self.navTitleLabel.text = item.title;
    [self.headerView configureWithItem:item
                                tracks:self.tracks
                             isPlaying:[self isPlayingCurrentContext]
                        shuffleEnabled:[SPPlayerService shared].isShuffleEnabled];
    if (item.mediaType == SPMediaTypeArtist) {
        [self.headerView updateFollowState:[[SPLibraryStore shared] isArtistFollowed:item.identifier] animated:NO];
    } else {
        [self.headerView updateLikeState:[[SPLibraryStore shared] isCollectionSaved:item.identifier] animated:NO];
    }
    [self updateHeaderLayout];
    [self.tableView reloadData];
}

- (BOOL)isPlayingCurrentContext {
    SPPlayerService *player = [SPPlayerService shared];
    return player.isPlaying && player.currentTrack && [self.tracks containsObject:player.currentTrack]
        && [player.contextTitle isEqualToString:self.mediaItem.title];
}

#pragma mark - Actions

- (void)backTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)handleHeaderPlay {
    if (self.tracks.count == 0) return;
    SPPlayerService *player = [SPPlayerService shared];
    if (player.currentTrack && [self.tracks containsObject:player.currentTrack]
        && [player.contextTitle isEqualToString:self.mediaItem.title]) {
        [player togglePlayPause];
    } else {
        [player playTracks:self.tracks startIndex:0 contextTitle:self.mediaItem.title];
    }
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPMediaRowCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPMediaRowCell reuseId] forIndexPath:indexPath];
    SPTrack *track = self.tracks[indexPath.row];
    SPPlayerService *player = [SPPlayerService shared];
    cell.rowView.coverSize = (self.mediaItem.mediaType == SPMediaTypeAlbum) ? 0 : 48;
    [cell.rowView configureWithItem:track];
    [cell.rowView setActive:[track isEqual:player.currentTrack] isPlaying:player.isPlaying];
    __weak typeof(self) weakSelf = self;
    cell.moreHandler = ^{
        [weakSelf showActionSheetForTrack:track atIndex:indexPath.row];
    };
    return cell;
}

- (void)handleFollowArtist {
    if (self.mediaItem.mediaType != SPMediaTypeArtist) return;
    SPArtist *artist = (SPArtist *)self.mediaItem;
    BOOL followed = [[SPLibraryStore shared] toggleFollowArtist:artist];
    [self.headerView updateFollowState:followed animated:YES];
    [SPToast showMessage:followed
        ? [NSString stringWithFormat:@"已关注艺人 %@", artist.name ?: @""]
        : [NSString stringWithFormat:@"已取消关注 %@", artist.name ?: @""]];
}

- (void)handleToggleSaveCollection {
    if (self.mediaItem.identifier.length == 0) return;
    BOOL saved = [[SPLibraryStore shared] toggleSaveCollectionWithId:self.mediaItem.identifier];
    [self.headerView updateLikeState:saved animated:YES];
    [SPToast showMessage:saved ? @"已收藏到你的音乐库" : @"已从音乐库移除收藏"];
}

- (void)handleHeaderMore {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:self.mediaItem.title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;

    __weak typeof(self) weakSelf = self;
    BOOL isUserPlaylist = [[SPLibraryStore shared] isUserCreatedPlaylistId:self.mediaItem.identifier];
    if (isUserPlaylist) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"删除此歌单" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [[SPLibraryStore shared] deletePlaylistWithId:weakSelf.mediaItem.identifier];
            [SPToast showMessage:@"已删除歌单"];
            [weakSelf.navigationController popViewControllerAnimated:YES];
        }]];
    } else if (self.tracks.count > 0 && ![self.mediaItem.identifier isEqualToString:SPLikedSongsPlaylistId]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"另存为我的歌单" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            SPPlaylist *saved = [[SPLibraryStore shared] createPlaylistWithName:weakSelf.mediaItem.title desc:@"从推荐歌单收藏"];
            for (NSInteger i = (NSInteger)weakSelf.tracks.count - 1; i >= 0; i--) {
                [[SPLibraryStore shared] addTrack:weakSelf.tracks[i] toPlaylistId:saved.identifier];
            }
            [SPToast showMessage:[NSString stringWithFormat:@"已保存为「%@」", saved.name]];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showActionSheetForTrack:(SPTrack *)track atIndex:(NSInteger)index {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:track.name
                                                                   message:[track artistNames]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;

    SPLibraryStore *store = [SPLibraryStore shared];
    BOOL isLiked = [store isTrackLiked:track.identifier];
    __weak typeof(self) weakSelf = self;

    [sheet addAction:[UIAlertAction actionWithTitle:(isLiked ? @"取消喜欢" : @"喜欢这首歌")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        BOOL likedNow = [store toggleLikeTrack:track];
        [SPHaptics medium];
        [SPToast showMessage:likedNow ? @"已添加到「已点赞的歌曲」" : @"已取消点赞"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"添加到歌单..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SPLibraryActionSheet presentAddTrack:track toPlaylistFrom:weakSelf];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"下一首播放" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[SPPlayerService shared] insertNextTrack:track];
        [SPToast showMessage:@"已添加到下一首播放"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"立即播放" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSUInteger currentIdx = [weakSelf.tracks indexOfObject:track];
        if (currentIdx == NSNotFound && weakSelf.tracks.count > 0) {
            currentIdx = (NSUInteger)MIN(MAX(index, 0), (NSInteger)weakSelf.tracks.count - 1);
        }
        if (currentIdx < weakSelf.tracks.count) {
            [[SPPlayerService shared] playTracks:weakSelf.tracks startIndex:currentIdx contextTitle:weakSelf.mediaItem.title];
        }
    }]];
    if ([store localPlaylistWithId:self.mediaItem.identifier] != nil) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"从此歌单移除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [store removeTrackId:track.identifier fromPlaylistId:weakSelf.mediaItem.identifier];
            [SPToast showMessage:@"已从歌单移除"];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [[SPPlayerService shared] playTracks:self.tracks startIndex:indexPath.row contextTitle:self.mediaItem.title];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offsetY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top;
    CGFloat navProgress = MIN(MAX((offsetY - 160) / 60.0, 0), 1);
    self.navBarBackground.alpha = navProgress;
    self.navTitleLabel.alpha = navProgress;

    // 向下拉伸时放大封面，向上滚动时背景渐变微视差移动
    CGFloat shift = MIN(offsetY, 0);
    self.gradientView.transform = CGAffineTransformMakeTranslation(0, -MAX(offsetY * 0.35, 0) - shift * 0.2);
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        CGFloat stretch = MIN(-shift / 260.0, 0.25);
        self.headerView.shadowContainer.transform = CGAffineTransformMakeScale(1.0 + stretch, 1.0 + stretch);
    }
}

#pragma mark - SPPlayerObserver

- (void)updateVisibleRowStates {
    SPPlayerService *player = [SPPlayerService shared];
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        if (indexPath.row >= (NSInteger)self.tracks.count) continue;
        SPMediaRowCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (![cell isKindOfClass:SPMediaRowCell.class]) continue;
        SPTrack *track = self.tracks[indexPath.row];
        [cell.rowView setActive:[track isEqual:player.currentTrack] isPlaying:player.isPlaying];
    }
}

- (void)playerDidChangeTrack:(SPPlayerService *)player {
    [self updateVisibleRowStates];
    [self.headerView updatePlaying:[self isPlayingCurrentContext] shuffleEnabled:player.isShuffleEnabled animated:YES];
}

- (void)playerDidChangeState:(SPPlayerService *)player {
    [self updateVisibleRowStates];
    [self.headerView updatePlaying:[self isPlayingCurrentContext] shuffleEnabled:player.isShuffleEnabled animated:YES];
}

- (void)playerDidChangeMode:(SPPlayerService *)player {
    [self.headerView updatePlaying:[self isPlayingCurrentContext] shuffleEnabled:player.isShuffleEnabled animated:YES];
}

@end
