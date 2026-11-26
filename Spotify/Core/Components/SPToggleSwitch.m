//
//  SPToggleSwitch.m
//  Spotify
//

#import "SPToggleSwitch.h"

@interface SPToggleSwitch () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *thumbView;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@end

@implementation SPToggleSwitch

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:CGRectMake(0, 0, 51, 31)]) {
        [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        _trackView = [UIView new];
        _trackView.userInteractionEnabled = NO;
        _trackView.layer.cornerRadius = 15.5;
        _trackView.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_trackView];

        _thumbView = [UIView new];
        _thumbView.userInteractionEnabled = NO;
        _thumbView.backgroundColor = UIColor.whiteColor;
        _thumbView.layer.cornerRadius = 13.5;
        _thumbView.layer.cornerCurve = kCACornerCurveCircular;
        _thumbView.layer.shadowColor = UIColor.blackColor.CGColor;
        _thumbView.layer.shadowOpacity = 0.18;
        _thumbView.layer.shadowRadius = 2.5;
        _thumbView.layer.shadowOffset = CGSizeMake(0, 1.5);
        [self addSubview:_thumbView];

        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)]];
        _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        _panGesture.delegate = self;
        [self addGestureRecognizer:_panGesture];

        [self updateVisualStateAnimated:NO];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(51, 31);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat heightDelta = MAX(44.0 - CGRectGetHeight(self.bounds), 0);
    CGRect expanded = CGRectInset(self.bounds, 0, -heightDelta * 0.5);
    return CGRectContainsPoint(expanded, point);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = 51.0;
    CGFloat h = 31.0;
    CGFloat trackX = MAX(0.0, CGRectGetWidth(self.bounds) - w);
    CGFloat trackY = (CGRectGetHeight(self.bounds) - h) * 0.5;
    self.trackView.frame = CGRectMake(trackX, trackY, w, h);
    CGFloat thumbX = trackX + (self.on ? 22.0 : 2.0);
    CGFloat thumbY = trackY + 2.0;
    self.thumbView.frame = CGRectMake(thumbX, thumbY, 27, 27);
    self.thumbView.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:self.thumbView.bounds].CGPath;
}

- (void)setOnTintColor:(UIColor *)onTintColor {
    _onTintColor = onTintColor;
    [self updateVisualStateAnimated:NO];
}

- (void)setOn:(BOOL)on {
    [self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (_on == on) {
        [self updateVisualStateAnimated:NO];
        return;
    }
    _on = on;
    [self updateVisualStateAnimated:animated];
}

- (void)updateVisualStateAnimated:(BOOL)animated {
    void (^apply)(void) = ^{
        if (self.on) {
            self.trackView.backgroundColor = self.onTintColor ?: SPTheme.accentColor;
            self.trackView.layer.borderWidth = 0.0;
        } else {
            self.trackView.backgroundColor = SPTheme.highlightColor;
            self.trackView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
            self.trackView.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:[SPTheme resolvedTraitCollectionForView:self]].CGColor;
        }
        [self layoutSubviews];
    };

    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.22
                              delay:0
             usingSpringWithDamping:0.86
              initialSpringVelocity:0.2
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:apply
                         completion:nil];
    } else {
        apply();
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateVisualStateAnimated:NO];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.panGesture) {
        CGPoint v = [self.panGesture velocityInView:self];
        // 仅横向拖动时接管手势，竖向滚动交给外层 TableView / ScrollView
        return fabs(v.x) > fabs(v.y);
    }
    return YES;
}

- (void)handleTap {
    [self setOn:!self.on animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateEnded) {
        CGPoint v = [pan velocityInView:self];
        CGPoint t = [pan translationInView:self];
        BOOL targetOn = self.on;
        if (fabs(v.x) > 80) {
            targetOn = (v.x > 0);
        } else if (fabs(t.x) > 8) {
            targetOn = (t.x > 0);
        } else {
            targetOn = !self.on;
        }
        if (targetOn != self.on) {
            [self setOn:targetOn animated:YES];
            [self sendActionsForControlEvents:UIControlEventValueChanged];
        }
    }
}

@end
