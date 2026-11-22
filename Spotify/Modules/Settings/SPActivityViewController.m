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
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<id<SPMediaItem>> *items;
@end

@implementation SPActivityViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    _items = @[];
    [self setupViews];
    [self loadData];
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

    UIView *divider = [UIView new];
    divider.backgroundColor = SPTheme.separatorColor;
    [_navBar addSubview:divider];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = SPTheme.backgroundColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:SPMediaRowCell.class forCellReuseIdentifier:[SPMediaRowCell reuseId]];
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
    [divider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.navBar);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.navBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
}

- (void)loadData {
    __weak typeof(self) weakSelf = self;
    [[SPMusicRepository shared] fetchHomeSectionsWithCompletion:^(NSArray<SPHomeSection *> *sections, NSError *error) {
        if (error) {
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
        [weakSelf.tableView reloadData];
    }];
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
    cell.rowView.subtitleLabel.text = [NSString stringWithFormat:@"最新发布 · %@", item.subtitle];
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
