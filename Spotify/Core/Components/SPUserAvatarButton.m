//
//  SPUserAvatarButton.m
//  Spotify
//

#import "SPUserAvatarButton.h"
#import "SPAuthService.h"
#import "SPRootViewController.h"
#import "SPHaptics.h"

@interface SPUserAvatarButton () <SPAuthObserver>
@property (nonatomic, assign) CGFloat diameter;
@property (nonatomic, strong) UILabel *initialLabel;
@property (nonatomic, strong) UIImageView *guestIconView;
@end

@implementation SPUserAvatarButton

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithDiameter:34.0];
}

- (instancetype)initWithDiameter:(CGFloat)diameter {
    if (self = [super initWithFrame:CGRectMake(0, 0, diameter, diameter)]) {
        _diameter = diameter;
        self.layer.cornerRadius = diameter / 2.0;
        self.layer.cornerCurve = kCACornerCurveCircular;
        self.clipsToBounds = YES;

        _initialLabel = [UILabel new];
        _initialLabel.textAlignment = NSTextAlignmentCenter;
        _initialLabel.font = [SPTheme fontOfSize:round(diameter * 0.46) weight:UIFontWeightBold];
        _initialLabel.textColor = UIColor.blackColor;
        _initialLabel.userInteractionEnabled = NO;
        [self addSubview:_initialLabel];

        _guestIconView = [[UIImageView alloc] initWithImage:[SPTheme symbol:@"person.fill" size:round(diameter * 0.45) weight:UIImageSymbolWeightMedium]];
        _guestIconView.tintColor = SPTheme.textPrimaryColor;
        _guestIconView.userInteractionEnabled = NO;
        [self addSubview:_guestIconView];

        [_initialLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self);
        }];
        [_guestIconView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.center.equalTo(self);
        }];

        [self addTarget:self action:@selector(defaultTapped) forControlEvents:UIControlEventTouchUpInside];
        [[SPAuthService shared] addObserver:self];
        [self reloadAuthState];
    }
    return self;
}

- (void)reloadAuthState {
    SPAuthService *auth = [SPAuthService shared];
    if (auth.isLoggedIn) {
        self.backgroundColor = SPTheme.accentColor;
        self.layer.borderWidth = 0;
        self.initialLabel.hidden = NO;
        self.initialLabel.text = auth.currentUser.avatarInitial;
        self.guestIconView.hidden = YES;
    } else {
        self.backgroundColor = SPTheme.highlightColor;
        self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        self.initialLabel.hidden = YES;
        self.guestIconView.hidden = NO;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] && ![SPAuthService shared].isLoggedIn) {
        self.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    }
}

- (void)defaultTapped {
    // 若外部未另绑自定义 target，则自动展开左侧抽屉
    if ([self actionsForTarget:nil forControlEvent:UIControlEventTouchUpInside].count > 1) return;
    [SPHaptics light];
    UIViewController *root = self.window.rootViewController;
    if ([root isKindOfClass:SPRootViewController.class]) {
        [(SPRootViewController *)root openSideDrawer];
    }
}

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    [self reloadAuthState];
}

@end
