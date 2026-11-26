//
//  SPScaleButton.m
//  Spotify
//

#import "SPScaleButton.h"

@interface SPScaleButton ()
@property (nonatomic, copy, nullable) NSString *currentSymbolName;
@end

@implementation SPScaleButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat minSize = 44.0;
    CGFloat widthDelta = MAX(minSize - CGRectGetWidth(self.bounds), 0);
    CGFloat heightDelta = MAX(minSize - CGRectGetHeight(self.bounds), 0);
    CGRect expanded = CGRectInset(self.bounds, -widthDelta * 0.5, -heightDelta * 0.5);
    return CGRectContainsPoint(expanded, point);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.opticalHorizontalOffset != 0 && self.imageView) {
        CGPoint center = self.imageView.center;
        center.x += self.opticalHorizontalOffset;
        self.imageView.center = center;
    }
}

- (void)setOpticalHorizontalOffset:(CGFloat)opticalHorizontalOffset {
    if (_opticalHorizontalOffset == opticalHorizontalOffset) return;
    _opticalHorizontalOffset = opticalHorizontalOffset;
    [self setNeedsLayout];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (self.isStatic || UIAccessibilityIsReduceMotionEnabled()) return;

    CGAffineTransform target = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
    [UIView animateWithDuration:0.15
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.transform = target;
    } completion:nil];
}

- (void)sp_setSymbol:(NSString *)symbolName
                size:(CGFloat)size
              weight:(UIImageSymbolWeight)weight
            animated:(BOOL)animated {
    BOOL hasImage = ([self imageForState:UIControlStateNormal] != nil);
    BOOL changed = ![self.currentSymbolName isEqualToString:symbolName];
    self.currentSymbolName = symbolName;

    if (!changed && hasImage) return;

    UIImage *img = [SPTheme symbol:symbolName size:size weight:weight];
    UIImageView *outgoingSnapshot = nil;
    if (animated && changed && hasImage && !UIAccessibilityIsReduceMotionEnabled() && self.imageView.image) {
        outgoingSnapshot = [[UIImageView alloc] initWithFrame:self.imageView.frame];
        outgoingSnapshot.image = self.imageView.image;
        outgoingSnapshot.tintColor = self.tintColor;
        outgoingSnapshot.contentMode = UIViewContentModeCenter;
        [self addSubview:outgoingSnapshot];
    }

    [self setImage:img forState:UIControlStateNormal];

    if (!animated || !changed || UIAccessibilityIsReduceMotionEnabled()) return;

    [self layoutIfNeeded];
    self.imageView.alpha = 0;
    self.imageView.transform = CGAffineTransformMakeScale(0.25, 0.25);

    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:1.0
          initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.imageView.alpha = 1.0;
        self.imageView.transform = CGAffineTransformIdentity;
        outgoingSnapshot.alpha = 0;
        outgoingSnapshot.transform = CGAffineTransformMakeScale(0.25, 0.25);
    } completion:^(BOOL finished) {
        [outgoingSnapshot removeFromSuperview];
    }];
}

@end

@implementation SPProgressSlider

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat heightDelta = MAX(44.0 - CGRectGetHeight(self.bounds), 0);
    CGRect expanded = CGRectInset(self.bounds, -10.0, -heightDelta * 0.5);
    return CGRectContainsPoint(expanded, point);
}

@end
