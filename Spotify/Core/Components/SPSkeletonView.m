//
//  SPSkeletonView.m
//  Spotify
//

#import "SPSkeletonView.h"

@interface SPSkeletonBlockView ()
@property (nonatomic, strong) CAGradientLayer *shimmerLayer;
@end

@implementation SPSkeletonBlockView

- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight)
                ? [UIColor sp_colorWithHex:0xE5E7EB]
                : [UIColor sp_colorWithHex:0x222222];
        }];
        self.layer.cornerRadius = cornerRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;

        _shimmerLayer = [CAGradientLayer layer];
        _shimmerLayer.startPoint = CGPointMake(0, 0.5);
        _shimmerLayer.endPoint = CGPointMake(1, 0.5);
        _shimmerLayer.locations = @[@0.0, @0.5, @1.0];
        [self updateShimmerColors];
        [self.layer addSublayer:_shimmerLayer];
    }
    return self;
}

- (void)updateShimmerColors {
    BOOL isLight = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight);
    UIColor *base = [UIColor colorWithWhite:1.0 alpha:0.0];
    UIColor *glow = [UIColor colorWithWhite:1.0 alpha:isLight ? 0.55 : 0.08];
    self.shimmerLayer.colors = @[(__bridge id)base.CGColor, (__bridge id)glow.CGColor, (__bridge id)base.CGColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateShimmerColors];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    self.shimmerLayer.frame = CGRectMake(-w, 0, w * 3, h);
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self startShimmer];
    } else {
        [self.shimmerLayer removeAnimationForKey:@"shimmer"];
    }
}

- (void)startShimmer {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    if ([self.shimmerLayer animationForKey:@"shimmer"]) return;
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    anim.fromValue = @(-160);
    anim.toValue = @(320);
    anim.duration = 1.35;
    anim.repeatCount = HUGE_VALF;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.shimmerLayer addAnimation:anim forKey:@"shimmer"];
}

@end

@implementation SPSkeletonView

+ (instancetype)homeSkeletonView {
    SPSkeletonView *view = [SPSkeletonView new];
    view.backgroundColor = UIColor.clearColor;
    view.userInteractionEnabled = NO;

    UIView *lastAnchor = nil;
    // 8 个双列快捷入口骨架（4 行 × 2 列）
    for (int row = 0; row < 4; row++) {
        SPSkeletonBlockView *left = [[SPSkeletonBlockView alloc] initWithCornerRadius:4];
        SPSkeletonBlockView *right = [[SPSkeletonBlockView alloc] initWithCornerRadius:4];
        [view addSubview:left];
        [view addSubview:right];

        [left mas_makeConstraints:^(MASConstraintMaker *make) {
            if (lastAnchor) make.top.equalTo(lastAnchor.mas_bottom).offset(8);
            else make.top.equalTo(view).offset(8);
            make.left.equalTo(view).offset(SPMarginHorizontal);
            make.height.mas_equalTo(56);
        }];
        [right mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.height.equalTo(left);
            make.left.equalTo(left.mas_right).offset(8);
            make.right.equalTo(view).offset(-SPMarginHorizontal);
            make.width.equalTo(left);
        }];
        lastAnchor = left;
    }

    // 两组横向卡片骨架
    for (int sec = 0; sec < 2; sec++) {
        SPSkeletonBlockView *header = [[SPSkeletonBlockView alloc] initWithCornerRadius:6];
        [view addSubview:header];
        [header mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(lastAnchor.mas_bottom).offset(sec == 0 ? 24 : 28);
            make.left.equalTo(view).offset(SPMarginHorizontal);
            make.size.mas_equalTo(CGSizeMake(140, 22));
        }];

        UIView *prevCard = nil;
        for (int i = 0; i < 3; i++) {
            SPSkeletonBlockView *card = [[SPSkeletonBlockView alloc] initWithCornerRadius:6];
            SPSkeletonBlockView *line = [[SPSkeletonBlockView alloc] initWithCornerRadius:4];
            [view addSubview:card];
            [view addSubview:line];
            [card mas_makeConstraints:^(MASConstraintMaker *make) {
                make.top.equalTo(header.mas_bottom).offset(12);
                if (prevCard) make.left.equalTo(prevCard.mas_right).offset(12);
                else make.left.equalTo(view).offset(SPMarginHorizontal);
                make.size.mas_equalTo(CGSizeMake(148, 148));
            }];
            [line mas_makeConstraints:^(MASConstraintMaker *make) {
                make.top.equalTo(card.mas_bottom).offset(8);
                make.left.equalTo(card);
                make.size.mas_equalTo(CGSizeMake(110, 14));
            }];
            prevCard = card;
            lastAnchor = line;
        }
    }
    return view;
}

+ (instancetype)detailSkeletonView {
    SPSkeletonView *view = [SPSkeletonView new];
    view.backgroundColor = UIColor.clearColor;
    view.userInteractionEnabled = NO;

    UIView *prev = nil;
    for (int i = 0; i < 6; i++) {
        SPSkeletonBlockView *thumb = [[SPSkeletonBlockView alloc] initWithCornerRadius:4];
        SPSkeletonBlockView *title = [[SPSkeletonBlockView alloc] initWithCornerRadius:4];
        SPSkeletonBlockView *sub = [[SPSkeletonBlockView alloc] initWithCornerRadius:4];
        [view addSubview:thumb];
        [view addSubview:title];
        [view addSubview:sub];

        [thumb mas_makeConstraints:^(MASConstraintMaker *make) {
            if (prev) make.top.equalTo(prev.mas_bottom).offset(16);
            else make.top.equalTo(view).offset(8);
            make.left.equalTo(view).offset(SPMarginHorizontal);
            make.size.mas_equalTo(CGSizeMake(48, 48));
        }];
        [title mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(thumb.mas_right).offset(12);
            make.top.equalTo(thumb).offset(6);
            make.size.mas_equalTo(CGSizeMake(180 - (i % 3) * 28, 15));
        }];
        [sub mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(title);
            make.top.equalTo(title.mas_bottom).offset(8);
            make.size.mas_equalTo(CGSizeMake(110, 12));
        }];
        prev = thumb;
    }
    return view;
}

- (void)dismissAnimated:(BOOL)animated {
    if (!animated) {
        [self removeFromSuperview];
        return;
    }
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

@end
