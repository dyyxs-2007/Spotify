//
//  SPQueueViewController.m
//  Spotify
//

#import "SPQueueViewController.h"
#import "SPMediaCells.h"
#import "SPPlayerService.h"
#import "SPToast.h"

@interface SPQueueViewController () <UITableViewDataSource, UITableViewDelegate, SPPlayerObserver>
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SPQueueViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    [self setupViews];
    [[SPPlayerService shared] addObserver:self];
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

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeBtn setImage:[SPTheme symbol:@"xmark" size:17 weight:UIImageSymbolWeightSemibold] forState:UIControlStateNormal];
    closeBtn.tintColor = SPTheme.textPrimaryColor;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBar addSubview:closeBtn];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.backgroundColor = SPTheme.backgroundColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPMediaRowCell.class forCellReuseIdentifier:[SPMediaRowCell reuseId]];
    [self.view addSubview:_tableView];

    [_navBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(50);
    }];
    [titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.navBar);
        make.bottom.equalTo(self.navBar).offset(-14);
    }];
    [closeBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.navBar).offset(-8);
        make.centerY.equalTo(titleLabel);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.navBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
}

- (void)closeTapped {
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

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 42; }
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return 8; }
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section { return [UIView new]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPMediaRowCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPMediaRowCell reuseId] forIndexPath:indexPath];
    SPPlayerService *player = [SPPlayerService shared];
    SPTrack *track = (indexPath.section == 0) ? player.currentTrack : player.upNextTracks[indexPath.row];
    cell.rowView.coverSize = 48;
    [cell.rowView configureWithItem:track];
    [cell.rowView setActive:(indexPath.section == 0) isPlaying:player.isPlaying];
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

- (void)playerDidChangeTrack:(SPPlayerService *)player { [self.tableView reloadData]; }
- (void)playerDidChangeQueue:(SPPlayerService *)player { [self.tableView reloadData]; }

- (void)playerDidChangeState:(SPPlayerService *)player {
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        SPMediaRowCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if ([cell isKindOfClass:SPMediaRowCell.class]) {
            [cell.rowView setActive:(indexPath.section == 0) isPlaying:player.isPlaying];
        }
    }
}

@end
