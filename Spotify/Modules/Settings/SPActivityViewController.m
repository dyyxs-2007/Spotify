//
//  SPActivityViewController.m
//  Spotify
//

#import "SPActivityViewController.h"
#import "SPScaleButton.h"
#import "SPMediaCells.h"
#import "SPDetailViewController.h"
#import "SPMusicRepository.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPActivityViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UIView *navDivider;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, copy) NSArray<id<SPMediaItem>> *items;
@end

@implementation SPActivityViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    _items = @[];
    [self setupViews];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sourceDidChange)
                                                 name:SPMusicSourceDidChangeNotification
                                               object:nil];
    [self loadDataForceRefresh:NO];
}

- (void)sourceDidChange {
    self.items = @[];
    [self.tableView reloadData];
    [self loadDataForceRefresh:NO];
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
    titleLabel.text = @"新动态";
    titleLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor = SPTheme.textPrimaryColor;
    [_navBar addSubview:titleLabel];

    _navDivider = [UIView new];
    _navDivider.backgroundColor = SPTheme.separatorColor;
    _navDivider.alpha = 0.0;
    [_navBar addSubview:_navDivider];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = SPTheme.backgroundColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPMediaRowCell.class forCellReuseIdentifier:[SPMediaRowCell reuseId]];
    [self.view addSubview:_tableView];

    _refreshControl = [UIRefreshControl new];
    _refreshControl.tintColor = SPTheme.accentColor;
    [_refreshControl addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;

    _loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingSpinner.color = SPTheme.accentColor;
    _loadingSpinner.hidesWhenStopped = YES;
    [self.view addSubview:_loadingSpinner];

    _emptyStateView = [UIView new];
    _emptyStateView.hidden = YES;
    [self.view addSubview:_emptyStateView];

    UIImageView *emptyIcon = [[UIImageView alloc] initWithImage:[SPTheme symbol:@"sparkles" size:42 weight:UIImageSymbolWeightLight]];
    emptyIcon.tintColor = SPTheme.textTertiaryColor;
    UILabel *emptyLabel = [UILabel new];
    emptyLabel.text = @"暂无最新动态\n下拉即可刷新最新发行歌单与专辑";
    emptyLabel.font = [SPTheme fontOfSize:14 weight:UIFontWeightRegular];
    emptyLabel.textColor = SPTheme.textSecondaryColor;
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.numberOfLines = 0;
    emptyLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
    [_emptyStateView addSubview:emptyIcon];
    [_emptyStateView addSubview:emptyLabel];

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
    [_loadingSpinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableView);
    }];
    [_emptyStateView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.tableView);
        make.left.greaterThanOrEqualTo(self.view).offset(32);
    }];
    [emptyIcon mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.centerX.equalTo(self.emptyStateView);
    }];
    [emptyLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(emptyIcon.mas_bottom).offset(14);
        make.left.right.bottom.equalTo(self.emptyStateView);
    }];
}

- (void)loadData {
    [self loadDataForceRefresh:NO];
}

- (void)refreshData {
    [self loadDataForceRefresh:YES];
}

- (void)loadDataForceRefresh:(BOOL)forceRefresh {
    if (self.items.count == 0 && !self.refreshControl.isRefreshing) {
        [self.loadingSpinner startAnimating];
    }
    self.emptyStateView.hidden = YES;
    __weak typeof(self) weakSelf = self;
    void (^completion)(NSArray<SPHomeSection *> *, NSError *) = ^(NSArray<SPHomeSection *> *sections, NSError *error) {
        [weakSelf.loadingSpinner stopAnimating];
        [weakSelf.refreshControl endRefreshing];
        if (error) {
            weakSelf.emptyStateView.hidden = (weakSelf.items.count > 0);
            [SPToast showMessage:@"加载动态失败"];
            return;
        }
        NSMutableArray<id<SPMediaItem>> *collected = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (SPHomeSection *sec in sections) {
            if (sec.style == SPHomeSectionStyleShortcut) continue;
            for (id<SPMediaItem> item in sec.items) {
                if (item.mediaType == SPMediaTypeArtist) continue;
                NSString *key = [NSString stringWithFormat:@"%ld:%@", (long)item.mediaType, item.identifier];
                if (![seen containsObject:key]) {
                    [seen addObject:key];
                    [collected addObject:item];
                }
            }
        }
        weakSelf.items = collected;
        weakSelf.emptyStateView.hidden = (collected.count > 0);
        [weakSelf.tableView reloadData];
    };
    if (forceRefresh) {
        [[SPMusicRepository shared] refreshHomeSectionsWithCompletion:completion];
    } else {
        [[SPMusicRepository shared] fetchHomeSectionsWithCompletion:completion];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offsetY = MAX(0.0, scrollView.contentOffset.y);
    self.navDivider.alpha = MIN(MAX(offsetY / 18.0, 0.0), 1.0);
}

- (void)backTapped {
    [SPHaptics light];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPMediaRowCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPMediaRowCell reuseId] forIndexPath:indexPath];
    id<SPMediaItem> item = self.items[indexPath.row];
    cell.rowView.coverSize = 56;
    [cell.rowView configureWithItem:item];
    NSString *sub = item.subtitle;
    cell.rowView.subtitleLabel.text = (sub.length > 0)
        ? [NSString stringWithFormat:@"最新发布 · %@", sub]
        : @"最新发布";
    cell.showsMoreButton = NO;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [SPHaptics light];
    id<SPMediaItem> item = self.items[indexPath.row];
    SPDetailViewController *detail = [[SPDetailViewController alloc] initWithMediaItem:item];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
