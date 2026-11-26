//
//  SPHistoryViewController.m
//  Spotify
//

#import "SPHistoryViewController.h"
#import "SPScaleButton.h"
#import "SPMediaCells.h"
#import "SPHistoryStore.h"
#import "SPPlayerService.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPHistoryViewController () <UITableViewDataSource, UITableViewDelegate, SPPlayerObserver>
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UIView *navDivider;
@property (nonatomic, strong) SPScaleButton *clearButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, copy) NSArray<SPTrack *> *tracks;
@end

@implementation SPHistoryViewController

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
                                             selector:@selector(reloadHistory)
                                                 name:SPHistoryDidUpdateNotification
                                               object:nil];
    [self reloadHistory];
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
    titleLabel.text = @"最近收听";
    titleLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor = SPTheme.textPrimaryColor;
    [_navBar addSubview:titleLabel];

    _clearButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_clearButton setTitle:@"清空" forState:UIControlStateNormal];
    _clearButton.titleLabel.font = [SPTheme fontOfSize:14 weight:UIFontWeightMedium];
    _clearButton.tintColor = SPTheme.textSecondaryColor;
    [_clearButton addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBar addSubview:_clearButton];

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

    _emptyStateView = [UIView new];
    _emptyStateView.hidden = YES;
    [self.view addSubview:_emptyStateView];

    UIImageView *emptyIcon = [[UIImageView alloc] initWithImage:[SPTheme symbol:@"clock.arrow.circlepath" size:44 weight:UIImageSymbolWeightLight]];
    emptyIcon.tintColor = SPTheme.textTertiaryColor;
    UILabel *emptyLabel = [UILabel new];
    emptyLabel.text = @"还没有播放记录\n点击任意歌曲即可在此记录收听足迹";
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
    [_clearButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.navBar).offset(-12);
        make.centerY.equalTo(backBtn);
        make.height.mas_equalTo(44);
    }];
    [_navDivider mas_makeConstraints:^(MASConstraintMaker *make) {
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

- (void)reloadHistory {
    self.tracks = [SPHistoryStore shared].recentTracks;
    self.emptyStateView.hidden = (self.tracks.count > 0);
    self.clearButton.hidden = (self.tracks.count == 0);
    [self.tableView reloadData];
}

- (void)backTapped {
    [SPHaptics light];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)clearTapped {
    [SPHaptics medium];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"清空最近收听记录？"
                                                                   message:@"清空后当前账号的收听足迹将无法恢复"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;
    [sheet addAction:[UIAlertAction actionWithTitle:@"确认清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[SPHistoryStore shared] clearHistory];
        [SPToast showMessage:@"已清空最近收听记录"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:self.clearButton presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offsetY = MAX(0.0, scrollView.contentOffset.y);
    self.navDivider.alpha = MIN(MAX(offsetY / 18.0, 0.0), 1.0);
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPMediaRowCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPMediaRowCell reuseId] forIndexPath:indexPath];
    SPTrack *track = self.tracks[indexPath.row];
    SPPlayerService *player = [SPPlayerService shared];
    cell.rowView.coverSize = 52;
    [cell.rowView configureWithItem:track];
    [cell.rowView setActive:[track isEqual:player.currentTrack] isPlaying:player.isPlaying];
    cell.showsMoreButton = YES;
    __weak typeof(self) weakSelf = self;
    cell.moreHandler = ^{
        [weakSelf showActionSheetForTrack:track atIndex:indexPath.row];
    };
    return cell;
}

- (void)showActionSheetForTrack:(SPTrack *)track atIndex:(NSInteger)index {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:track.name
                                                                   message:[track artistNames]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;
    __weak typeof(self) weakSelf = self;
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
            [[SPPlayerService shared] playTracks:weakSelf.tracks startIndex:currentIdx contextTitle:@"最近收听"];
        }
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [SPHaptics light];
    [[SPPlayerService shared] playTracks:self.tracks startIndex:indexPath.row contextTitle:@"最近收听"];
}

#pragma mark - SPPlayerObserver

- (void)updateVisibleRowStates {
    SPPlayerService *player = [SPPlayerService shared];
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        if (indexPath.row >= (NSInteger)self.tracks.count) continue;
        SPMediaRowCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (![cell isKindOfClass:SPMediaRowCell.class]) continue;
        [cell.rowView setActive:[self.tracks[indexPath.row] isEqual:player.currentTrack] isPlaying:player.isPlaying];
    }
}

- (void)playerDidChangeTrack:(SPPlayerService *)player { [self updateVisibleRowStates]; }
- (void)playerDidChangeState:(SPPlayerService *)player { [self updateVisibleRowStates]; }

@end
