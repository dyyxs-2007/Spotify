//
//  SPSearchViewController.m
//  Spotify
//

#import "SPSearchViewController.h"
#import "SPSearchCategoryCell.h"
#import "SPHomeSectionHeaderView.h"
#import "SPMediaCells.h"
#import "SPUserAvatarButton.h"
#import "SPScaleButton.h"
#import "SPDetailViewController.h"
#import "SPMusicRepository.h"
#import "SPLibraryStore.h"
#import "SPLibraryActionSheet.h"
#import "SPPlayerService.h"
#import "SPHaptics.h"
#import "SPToast.h"

@interface SPSearchResultSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<id<SPMediaItem>> *items;
@property (nonatomic, assign) BOOL isTrackSection;
@end

@implementation SPSearchResultSection
@end

@interface SPSearchViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
                                      UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,
                                      UIGestureRecognizerDelegate, SPPlayerObserver>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *searchContainer;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) SPScaleButton *clearButton;
@property (nonatomic, strong) UIActivityIndicatorView *searchSpinner;
@property (nonatomic, strong) SPScaleButton *cancelButton;
@property (nonatomic, strong) MASConstraint *searchRightToContainer;
@property (nonatomic, strong) MASConstraint *searchRightToCancel;

@property (nonatomic, strong) UICollectionView *categoryCollectionView;
@property (nonatomic, strong) UIControl *searchDismissScrim;
@property (nonatomic, strong) UITableView *resultTableView;
@property (nonatomic, strong) UIView *topBarHairline;
@property (nonatomic, strong) UILabel *emptyLabel;

@property (nonatomic, copy) NSArray<SPSearchCategory *> *categories;
@property (nonatomic, copy) NSArray<SPSearchResultSection *> *resultSections;
@property (nonatomic, copy) NSString *latestKeyword;
@property (nonatomic, copy, nullable) dispatch_block_t pendingSearchBlock;
@property (nonatomic, assign) BOOL isSearchFocused;
@property (nonatomic, assign) CGFloat keyboardOverlap;
@end

@implementation SPSearchViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    _categories = @[];
    _resultSections = @[];
    [self setupViews];
    [[SPPlayerService shared] addObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(musicSourceDidChange)
                                                 name:SPMusicSourceDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    [self loadCategories];
}

- (void)musicSourceDidChange {
    self.categories = @[];
    [self.categoryCollectionView reloadData];
    self.searchField.text = @"";
    [self performSearchWithKeyword:@""];
    [self loadCategories];
}

- (void)setupViews {
    SPUserAvatarButton *avatarButton = [[SPUserAvatarButton alloc] initWithDiameter:34];
    [self.view addSubview:avatarButton];

    _titleLabel = [UILabel new];
    _titleLabel.text = @"搜索";
    _titleLabel.font = SPTheme.largeTitleFont;
    _titleLabel.textColor = SPTheme.textPrimaryColor;
    [self.view addSubview:_titleLabel];

    _searchContainer = [UIView new];
    _searchContainer.backgroundColor = UIColor.whiteColor;
    _searchContainer.layer.cornerRadius = 8;
    _searchContainer.layer.cornerCurve = kCACornerCurveContinuous;
    [self updateSearchBarAppearance];
    [self.view addSubview:_searchContainer];

    UIImageView *searchIcon = [[UIImageView alloc] initWithImage:[SPTheme symbol:@"magnifyingglass" size:18 weight:UIImageSymbolWeightMedium]];
    searchIcon.tintColor = [UIColor sp_colorWithHex:0x121212];
    [_searchContainer addSubview:searchIcon];

    _searchField = [UITextField new];
    _searchField.textColor = [UIColor sp_colorWithHex:0x121212];
    _searchField.tintColor = [UIColor sp_colorWithHex:0x121212];
    _searchField.font = [SPTheme fontOfSize:15 weight:UIFontWeightMedium];
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.delegate = self;
    _searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"你想听什么？"
                                                                       attributes:@{
        NSForegroundColorAttributeName: [UIColor sp_colorWithHex:0x535353],
        NSFontAttributeName: [SPTheme fontOfSize:15 weight:UIFontWeightMedium],
    }];
    [_searchField addTarget:self action:@selector(textDidChange:) forControlEvents:UIControlEventEditingChanged];
    [_searchContainer addSubview:_searchField];

    _clearButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_clearButton sp_setSymbol:@"xmark.circle.fill" size:17 weight:UIImageSymbolWeightMedium animated:NO];
    _clearButton.tintColor = [UIColor sp_colorWithHex:0x535353];
    _clearButton.hidden = YES;
    [_clearButton addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
    [_searchContainer addSubview:_clearButton];

    _searchSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _searchSpinner.color = [UIColor sp_colorWithHex:0x535353];
    _searchSpinner.transform = CGAffineTransformMakeScale(0.76, 0.76);
    _searchSpinner.hidesWhenStopped = YES;
    _searchSpinner.userInteractionEnabled = NO;
    [_searchContainer addSubview:_searchSpinner];

    _cancelButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    _cancelButton.titleLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightMedium];
    _cancelButton.tintColor = SPTheme.textPrimaryColor;
    _cancelButton.alpha = 0;
    _cancelButton.hidden = YES;
    [_cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelButton];

    UICollectionViewFlowLayout *flow = [UICollectionViewFlowLayout new];
    flow.minimumInteritemSpacing = 12;
    flow.minimumLineSpacing = 12;
    flow.sectionInset = UIEdgeInsetsMake(4, SPMarginHorizontal, 24, SPMarginHorizontal);
    _categoryCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:flow];
    _categoryCollectionView.backgroundColor = SPTheme.backgroundColor;
    _categoryCollectionView.showsVerticalScrollIndicator = NO;
    _categoryCollectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _categoryCollectionView.dataSource = self;
    _categoryCollectionView.delegate = self;
    [_categoryCollectionView registerClass:SPSearchCategoryCell.class forCellWithReuseIdentifier:[SPSearchCategoryCell reuseId]];
    [_categoryCollectionView registerClass:SPHomeSectionHeaderView.class
                forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                       withReuseIdentifier:[SPHomeSectionHeaderView reuseId]];
    [self.view addSubview:_categoryCollectionView];

    // 搜索聚焦遮罩层：键盘弹出且未输入关键词时，点击屏幕任意浏览区立即收回键盘
    _searchDismissScrim = [UIControl new];
    _searchDismissScrim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.42];
    _searchDismissScrim.alpha = 0.0;
    _searchDismissScrim.hidden = YES;
    [_searchDismissScrim addTarget:self action:@selector(scrimTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_searchDismissScrim];

    _resultTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _resultTableView.backgroundColor = SPTheme.backgroundColor;
    _resultTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _resultTableView.contentInset = UIEdgeInsetsMake(0, 0, 16, 0);
    _resultTableView.scrollIndicatorInsets = _resultTableView.contentInset;
    _resultTableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _resultTableView.dataSource = self;
    _resultTableView.delegate = self;
    _resultTableView.hidden = YES;
    [_resultTableView registerClass:SPMediaRowCell.class forCellReuseIdentifier:[SPMediaRowCell reuseId]];
    [self.view addSubview:_resultTableView];

    _emptyLabel = [UILabel new];
    _emptyLabel.text = @"没有找到相关内容";
    _emptyLabel.font = [SPTheme fontOfSize:15 weight:UIFontWeightMedium];
    _emptyLabel.textColor = SPTheme.textSecondaryColor;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    _topBarHairline = [UIView new];
    _topBarHairline.backgroundColor = SPTheme.separatorColor;
    _topBarHairline.alpha = 0.0;
    _topBarHairline.userInteractionEnabled = NO;
    [self.view addSubview:_topBarHairline];

    // 视图空白区域轻点收回键盘（展示搜索结果时点空白区/Header 也能随时收起键盘）
    UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackgroundTap)];
    bgTap.cancelsTouchesInView = NO;
    bgTap.delegate = self;
    [self.view addGestureRecognizer:bgTap];

    [avatarButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(10);
        make.left.equalTo(self.view).offset(SPMarginHorizontal);
        make.size.mas_equalTo(CGSizeMake(34, 34));
    }];
    [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(avatarButton.mas_right).offset(12);
        make.centerY.equalTo(avatarButton);
        make.right.equalTo(self.view).offset(-SPMarginHorizontal);
    }];
    [_cancelButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.view).offset(-SPMarginHorizontal);
        make.centerY.equalTo(self.searchContainer);
    }];
    [_searchContainer mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(avatarButton.mas_bottom).offset(14);
        make.left.equalTo(self.view).offset(SPMarginHorizontal);
        make.height.mas_equalTo(42);
        self.searchRightToContainer = make.right.equalTo(self.view).offset(-SPMarginHorizontal);
        self.searchRightToCancel = make.right.equalTo(self.cancelButton.mas_left).offset(-10);
    }];
    [self.searchRightToCancel uninstall];

    [searchIcon mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.searchContainer).offset(12);
        make.centerY.equalTo(self.searchContainer);
        make.size.mas_equalTo(CGSizeMake(20, 20));
    }];
    [_clearButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.searchContainer).offset(-6);
        make.centerY.equalTo(self.searchContainer);
        make.size.mas_equalTo(CGSizeMake(32, 32));
    }];
    [_searchSpinner mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.clearButton);
    }];
    [_searchField mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(searchIcon.mas_right).offset(8);
        make.right.equalTo(self.clearButton.mas_left).offset(-4);
        make.top.bottom.equalTo(self.searchContainer);
    }];
    [_categoryCollectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.searchContainer.mas_bottom).offset(12);
        make.left.right.bottom.equalTo(self.view);
    }];
    [_topBarHairline mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.categoryCollectionView.mas_top);
        make.left.right.equalTo(self.view);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];
    [_searchDismissScrim mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.categoryCollectionView);
    }];
    [_resultTableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.categoryCollectionView);
    }];
    [_emptyLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.resultTableView);
        make.centerY.equalTo(self.resultTableView).offset(-40);
    }];
}

- (void)updateSearchBarAppearance {
    UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self.view];
    BOOL isLight = (tc.userInterfaceStyle == UIUserInterfaceStyleLight);
    self.searchContainer.layer.borderWidth = isLight ? (1.0 / UIScreen.mainScreen.scale) : 0;
    self.searchContainer.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:tc].CGColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateSearchBarAppearance];
    }
}

#pragma mark - Data

- (void)loadCategories {
    __weak typeof(self) weakSelf = self;
    [[SPMusicRepository shared] fetchSearchCategoriesWithCompletion:^(NSArray<SPSearchCategory *> *categories, NSError *error) {
        if (error) return;
        weakSelf.categories = categories ?: @[];
        [weakSelf.categoryCollectionView reloadData];
    }];
}

- (void)scheduleDebouncedSearchForKeyword:(NSString *)keyword {
    if (self.pendingSearchBlock) {
        dispatch_block_cancel(self.pendingSearchBlock);
        self.pendingSearchBlock = nil;
    }

    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    self.clearButton.hidden = (trimmed.length == 0);
    if (trimmed.length == 0) {
        [self performSearchWithKeyword:@""];
        return;
    }
    [self updateSearchScrimAnimated:YES];

    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        [weakSelf performSearchWithKeyword:trimmed];
    });
    self.pendingSearchBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (void)performSearchWithKeyword:(NSString *)keyword {
    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    self.latestKeyword = trimmed;

    if (trimmed.length == 0) {
        [self.searchSpinner stopAnimating];
        self.clearButton.hidden = YES;
        self.resultSections = @[];
        self.resultTableView.hidden = YES;
        self.emptyLabel.hidden = YES;
        self.categoryCollectionView.hidden = NO;
        [self.resultTableView reloadData];
        [self updateTopBarHairlineForScrollView:self.categoryCollectionView];
        [self updateSearchScrimAnimated:YES];
        return;
    }

    [self updateSearchScrimAnimated:YES];
    self.categoryCollectionView.hidden = YES;
    self.resultTableView.hidden = NO;
    [self updateTopBarHairlineForScrollView:self.resultTableView];
    self.emptyLabel.hidden = YES;
    self.clearButton.hidden = YES;
    [self.searchSpinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [[SPMusicRepository shared] searchWithKeyword:trimmed completion:^(SPSearchResult *result, NSError *error) {
        if (![weakSelf.latestKeyword isEqualToString:trimmed]) return;
        [weakSelf.searchSpinner stopAnimating];
        weakSelf.clearButton.hidden = (trimmed.length == 0);
        if (error) {
            [SPToast showMessage:error.localizedDescription ?: @"搜索失败"];
            return;
        }
        [weakSelf applySearchResult:result];
    }];
}

- (void)applySearchResult:(SPSearchResult *)result {
    NSMutableArray<SPSearchResultSection *> *sections = [NSMutableArray array];
    if (result.tracks.count > 0) {
        SPSearchResultSection *sec = [SPSearchResultSection new];
        sec.title = @"歌曲";
        sec.items = result.tracks;
        sec.isTrackSection = YES;
        [sections addObject:sec];
    }
    if (result.artists.count > 0) {
        SPSearchResultSection *sec = [SPSearchResultSection new];
        sec.title = @"艺人";
        sec.items = result.artists;
        [sections addObject:sec];
    }
    if (result.albums.count > 0) {
        SPSearchResultSection *sec = [SPSearchResultSection new];
        sec.title = @"专辑";
        sec.items = result.albums;
        [sections addObject:sec];
    }
    if (result.playlists.count > 0) {
        SPSearchResultSection *sec = [SPSearchResultSection new];
        sec.title = @"歌单";
        sec.items = result.playlists;
        [sections addObject:sec];
    }
    self.resultSections = sections;
    self.emptyLabel.hidden = (sections.count > 0);
    [self.resultTableView reloadData];
}

- (void)updateSearchScrimAnimated:(BOOL)animated {
    BOOL showScrim = self.isSearchFocused
        && (self.latestKeyword.length == 0)
        && ((self.searchField.text ?: @"").length == 0);

    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    if (showScrim) {
        self.searchDismissScrim.hidden = NO;
    }
    NSTimeInterval dur = showScrim ? 0.20 : 0.15;
    void (^work)(void) = ^{
        self.searchDismissScrim.alpha = showScrim ? 1.0 : 0.0;
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (!showScrim && self.searchDismissScrim.alpha < 0.01) {
            self.searchDismissScrim.hidden = YES;
        }
    };
    if (animated && !reduceMotion) {
        [UIView animateWithDuration:dur
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:work
                         completion:done];
    } else {
        work();
        done(YES);
    }
}

- (void)setSearchActive:(BOOL)active {
    self.cancelButton.hidden = NO;
    if (active) {
        [self.searchRightToContainer uninstall];
        [self.searchRightToCancel install];
    } else {
        [self.searchRightToCancel uninstall];
        [self.searchRightToContainer install];
    }
    [UIView animateWithDuration:0.24
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.cancelButton.alpha = active ? 1 : 0;
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (!active) self.cancelButton.hidden = YES;
    }];
}

#pragma mark - Keyboard & Dismissal

- (void)keyboardWillChangeFrame:(NSNotification *)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted));
    [self applyResultTableKeyboardInsetForOverlap:overlap];
}

- (void)keyboardWillHide:(NSNotification *)note {
    [self applyResultTableKeyboardInsetForOverlap:0.0];
}

- (void)applyResultTableKeyboardInsetForOverlap:(CGFloat)overlap {
    self.keyboardOverlap = overlap;
    CGFloat extraBottom = MAX(0.0, overlap - self.view.safeAreaInsets.bottom);
    CGFloat bottom = MAX(16.0, extraBottom + (extraBottom > 0 ? 12.0 : 0.0));
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, bottom, 0);
    self.resultTableView.contentInset = insets;
    self.resultTableView.scrollIndicatorInsets = insets;
}

- (void)scrimTapped {
    [SPHaptics light];
    [self cancelTapped];
}

- (void)handleBackgroundTap {
    if (self.searchField.isFirstResponder) {
        [self.searchField resignFirstResponder];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (!self.searchField.isFirstResponder) return NO;
    UIView *v = touch.view;
    while (v && v != self.view) {
        if (v == self.searchContainer || v == self.cancelButton || v == self.searchDismissScrim) {
            return NO;
        }
        if (!self.resultTableView.hidden && ([v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UIControl.class])) {
            return NO;
        }
        v = v.superview;
    }
    return YES;
}

#pragma mark - Actions

- (void)textDidChange:(UITextField *)field {
    [self scheduleDebouncedSearchForKeyword:field.text ?: @""];
}

- (void)clearTapped {
    if (self.pendingSearchBlock) dispatch_block_cancel(self.pendingSearchBlock);
    [self.searchSpinner stopAnimating];
    self.searchField.text = @"";
    [self performSearchWithKeyword:@""];
}

- (void)cancelTapped {
    if (self.pendingSearchBlock) dispatch_block_cancel(self.pendingSearchBlock);
    [self.searchSpinner stopAnimating];
    self.isSearchFocused = NO;
    self.searchField.text = @"";
    [self.searchField resignFirstResponder];
    [self setSearchActive:NO];
    [self performSearchWithKeyword:@""];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.isSearchFocused = YES;
    [self setSearchActive:YES];
    [self updateSearchScrimAnimated:YES];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.isSearchFocused = NO;
    [self updateSearchScrimAnimated:YES];
    if (self.latestKeyword.length == 0 && (self.searchField.text ?: @"").length == 0) {
        [self setSearchActive:NO];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - UICollectionView (Categories)

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.categories.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SPSearchCategoryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[SPSearchCategoryCell reuseId] forIndexPath:indexPath];
    [cell configureWithCategory:self.categories[indexPath.item]];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    SPHomeSectionHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                         withReuseIdentifier:[SPHomeSectionHeaderView reuseId]
                                                                                forIndexPath:indexPath];
    header.horizontalInset = SPMarginHorizontal;
    header.titleLabel.text = @"浏览全部";
    header.titleLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    return header;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
referenceSizeForHeaderInSection:(NSInteger)section {
    return CGSizeMake(CGRectGetWidth(collectionView.bounds), 40);
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = floor((CGRectGetWidth(collectionView.bounds) - SPMarginHorizontal * 2 - 12) / 2.0);
    return CGSizeMake(MAX(width, 100), 96);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [SPHaptics light];
    SPSearchCategory *cat = self.categories[indexPath.item];
    self.searchField.text = cat.name;
    [self setSearchActive:YES];
    [self performSearchWithKeyword:cat.name];
}

#pragma mark - UITableView (Search Results)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.resultSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.resultSections[section].items.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [UIView new];
    UILabel *label = [UILabel new];
    label.text = self.resultSections[section].title;
    label.font = [SPTheme fontOfSize:18 weight:UIFontWeightBold];
    label.textColor = SPTheme.textPrimaryColor;
    [header addSubview:label];
    [label mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(header).offset(SPMarginHorizontal);
        make.right.equalTo(header).offset(-SPMarginHorizontal);
        make.bottom.equalTo(header).offset(-6);
    }];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 38; }
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return 8; }
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section { return [UIView new]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPMediaRowCell *cell = [tableView dequeueReusableCellWithIdentifier:[SPMediaRowCell reuseId] forIndexPath:indexPath];
    SPSearchResultSection *sec = self.resultSections[indexPath.section];
    id<SPMediaItem> item = sec.items[indexPath.row];
    cell.rowView.coverSize = 52;
    [cell.rowView configureWithItem:item];
    SPPlayerService *player = [SPPlayerService shared];
    cell.showsMoreButton = sec.isTrackSection;
    [cell.rowView setActive:(sec.isTrackSection && [item isEqual:player.currentTrack]) isPlaying:player.isPlaying];
    __weak typeof(self) weakSelf = self;
    cell.moreHandler = ^{
        if (sec.isTrackSection && [item isKindOfClass:SPTrack.class]) {
            [weakSelf showActionSheetForTrack:(SPTrack *)item
                                     inTracks:(NSArray<SPTrack *> *)sec.items
                                      atIndex:indexPath.row];
        }
    };
    return cell;
}

- (void)showActionSheetForTrack:(SPTrack *)track inTracks:(NSArray<SPTrack *> *)tracks atIndex:(NSInteger)index {
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
        NSUInteger currentIdx = [tracks indexOfObject:track];
        if (currentIdx == NSNotFound && tracks.count > 0) {
            currentIdx = (NSUInteger)MIN(MAX(index, 0), (NSInteger)tracks.count - 1);
        }
        if (currentIdx < tracks.count) {
            [[SPPlayerService shared] playTracks:tracks startIndex:currentIdx contextTitle:@"搜索结果"];
        }
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchField resignFirstResponder];
    SPSearchResultSection *sec = self.resultSections[indexPath.section];
    id<SPMediaItem> item = sec.items[indexPath.row];
    if (sec.isTrackSection) {
        NSArray<SPTrack *> *tracks = (NSArray<SPTrack *> *)sec.items;
        [[SPPlayerService shared] playTracks:tracks startIndex:indexPath.row contextTitle:@"搜索结果"];
    } else {
        SPDetailViewController *detail = [[SPDetailViewController alloc] initWithMediaItem:item];
        [self.navigationController pushViewController:detail animated:YES];
    }
}

- (void)updateTopBarHairlineForScrollView:(UIScrollView *)scrollView {
    CGFloat offsetY = MAX(0.0, scrollView.contentOffset.y);
    self.topBarHairline.alpha = MIN(MAX(offsetY / 20.0, 0.0), 1.0);
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if ((scrollView == self.categoryCollectionView && !self.categoryCollectionView.hidden)
        || (scrollView == self.resultTableView && !self.resultTableView.hidden)) {
        [self updateTopBarHairlineForScrollView:scrollView];
    }
}

#pragma mark - SPPlayerObserver

- (void)updateVisibleRowStates {
    if (self.resultTableView.hidden) return;
    SPPlayerService *player = [SPPlayerService shared];
    for (NSIndexPath *indexPath in self.resultTableView.indexPathsForVisibleRows) {
        if (indexPath.section >= (NSInteger)self.resultSections.count) continue;
        SPSearchResultSection *sec = self.resultSections[indexPath.section];
        if (!sec.isTrackSection || indexPath.row >= (NSInteger)sec.items.count) continue;
        SPMediaRowCell *cell = [self.resultTableView cellForRowAtIndexPath:indexPath];
        if (![cell isKindOfClass:SPMediaRowCell.class]) continue;
        [cell.rowView setActive:[sec.items[indexPath.row] isEqual:player.currentTrack] isPlaying:player.isPlaying];
    }
}

- (void)playerDidChangeTrack:(SPPlayerService *)player {
    [self updateVisibleRowStates];
}

- (void)playerDidChangeState:(SPPlayerService *)player {
    [self updateVisibleRowStates];
}

@end
