//
//  SPQueueViewController.m
//  Spotify
//

#import "SPQueueViewController.h"
#import "SPScaleButton.h"
#import "SPMediaCells.h"
#import "SPPlayerService.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPQueueViewController () <UITableViewDataSource, UITableViewDelegate, SPPlayerObserver>
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *emptyStateView;
@end

@implementation SPQueueViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor sp_colorWithHex:0x121214];
    [self setupViews];
    [[SPPlayerService shared] addObserver:self];
    [self updateEmptyState];
}

- (void)setupViews {
    _navBar = [UIView new];
    _navBar.backgroundColor = SPTheme.elevatedColor;
    [self.view addSubview:_navBar];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"播放队列";
    titleLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor = SPTheme.textPrimaryColor;
    [_navBar addSubview:titleLabel];

    SPScaleButton *closeBtn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [closeBtn sp_setSymbol:@"xmark" size:17 weight:UIImageSymbolWeightSemibold animated:NO];
    closeBtn.tintColor = SPTheme.textPrimaryColor;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBar addSubview:closeBtn];

    UIView *divider = [UIView new];
    divider.backgroundColor = SPTheme.separatorColor;
    [_navBar addSubview:divider];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.backgroundColor = SPTheme.backgroundColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPMediaRowCell.class forCellReuseIdentifier:[SPMediaRowCell reuseId]];
    [self.view addSubview:_tableView];

    _emptyStateView = [UIView new];
    _emptyStateView.hidden = YES;
    [self.view addSubview:_emptyStateView];

    UIImageView *emptyIcon = [[UIImageView alloc] initWithImage:[SPTheme symbol:@"music.note.list" size:42 weight:UIImageSymbolWeightLight]];
    emptyIcon.tintColor = SPTheme.textTertiaryColor;
    UILabel *emptyLabel = [UILabel new];
    emptyLabel.text = @"播放队列为空\n去首页或音乐库挑选喜欢的歌曲开始播放";
    emptyLabel.font = [SPTheme fontOfSize:14 weight:UIFontWeightRegular];
    emptyLabel.textColor = SPTheme.textSecondaryColor;
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.numberOfLines = 0;
    emptyLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
    [_emptyStateView addSubview:emptyIcon];
    [_emptyStateView addSubview:emptyLabel];

    [_navBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(54);
    }];
    [closeBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.navBar).offset(-8);
        make.bottom.equalTo(self.navBar).offset(-4);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.navBar);
        make.centerY.equalTo(closeBtn);
    }];
    [divider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.navBar);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.navBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
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

- (void)updateEmptyState {
    SPPlayerService *player = [SPPlayerService shared];
    BOOL isEmpty = (player.currentTrack == nil && player.upNextTracks.count == 0);
    self.emptyStateView.hidden = !isEmpty;
    self.tableView.hidden = isEmpty;
}

- (void)closeTapped {
    [SPHaptics light];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    SPPlayerService *player = [SPPlayerService shared];
    if (section == 0) return player.currentTrack ? 1 : 0;
    return player.upNextTracks.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 1 && [SPPlayerService shared].upNextTracks.count == 0) {
        return [UIView new];
    }
    UIView *header = [UIView new];
    UILabel *label = [UILabel new];
    label.text = (section == 0) ? @"正在播放" : @"接下来播放";
    label.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
    label.textColor = SPTheme.textPrimaryColor;
    [header addSubview:label];
    [label mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(header).offset(SPMarginHorizontal);
        make.right.equalTo(header).offset(-SPMarginHorizontal);
        make.bottom.equalTo(header).offset(-6);
    }];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 1 && [SPPlayerService shared].upNextTracks.count == 0) return 0.01;
    return 42;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return 8; }
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section { return [UIView new]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPMediaRowCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPMediaRowCell reuseId] forIndexPath:indexPath];
    SPPlayerService *player = [SPPlayerService shared];
    SPTrack *track = (indexPath.section == 0) ? player.currentTrack : player.upNextTracks[indexPath.row];
    cell.rowView.coverSize = 48;
    [cell.rowView configureWithItem:track];
    [cell.rowView setActive:(indexPath.section == 0) isPlaying:player.isPlaying];
    cell.selectionStyle = (indexPath.section == 0) ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    cell.showsMoreButton = NO;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [[SPPlayerService shared] playUpNextAtIndex:indexPath.row];
    }
}

#pragma mark - SPPlayerObserver

- (void)playerDidChangeTrack:(SPPlayerService *)player {
    [self updateEmptyState];
    [self.tableView reloadData];
}
- (void)playerDidChangeQueue:(SPPlayerService *)player {
    [self updateEmptyState];
    [self.tableView reloadData];
}

- (void)playerDidChangeState:(SPPlayerService *)player {
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        SPMediaRowCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if ([cell isKindOfClass:SPMediaRowCell.class]) {
            [cell.rowView setActive:(indexPath.section == 0) isPlaying:player.isPlaying];
        }
    }
}

@end
