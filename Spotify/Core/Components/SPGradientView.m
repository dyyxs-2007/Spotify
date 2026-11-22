//
//  SPGradientView.m
//  Spotify
//

#import "SPGradientView.h"

@implementation SPGradientView

+ (Class)layerClass { return CAGradientLayer.class; }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = NO;
        [self setStartPoint:CGPointMake(0.5, 0) endPoint:CGPointMake(0.5, 1)];
    }
    return self;
}

- (CAGradientLayer *)gradientLayer { return (CAGradientLayer *)self.layer; }

- (void)setColors:(NSArray<UIColor *> *)colors {
    [self setColors:colors animated:NO];
}

- (void)setColors:(NSArray<UIColor *> *)colors animated:(BOOL)animated {
    _colors = [colors copy];
    NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
    for (UIColor *c in colors) {
        UIColor *resolved = [c resolvedColorWithTraitCollection:self.traitCollection];
        [cgColors addObject:(__bridge id)resolved.CGColor];
    }

    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"colors"];
        anim.fromValue = self.gradientLayer.presentationLayer.colors ?: self.gradientLayer.colors;
        anim.toValue = cgColors;
        anim.duration = 0.45;
        anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.gradientLayer addAnimation:anim forKey:@"colors"];
    }
    self.gradientLayer.colors = cgColors;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] && self.colors.count > 0) {
        [self setColors:self.colors animated:NO];
    }
}

- (void)setLocations:(NSArray<NSNumber *> *)locations {
    _locations = [locations copy];
    self.gradientLayer.locations = locations;
}

- (void)setStartPoint:(CGPoint)start endPoint:(CGPoint)end {
    self.gradientLayer.startPoint = start;
    self.gradientLayer.endPoint = end;
}

@end
