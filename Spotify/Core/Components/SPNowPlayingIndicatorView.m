//
//  SPNowPlayingIndicatorView.m
//  Spotify
//

#import "SPNowPlayingIndicatorView.h"

@interface SPNowPlayingIndicatorView ()
@property (nonatomic, copy) NSArray<CALayer *> *bars;
@end

@implementation SPNowPlayingIndicatorView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = NO;
        NSMutableArray *layers = [NSMutableArray arrayWithCapacity:3];
        CGFloat xOffsets[] = { 0.0, 4.5, 9.0 };
        CGFloat idleHeights[] = { 4.0, 8.0, 5.0 };

        for (int i = 0; i < 3; i++) {
            CALayer *bar = [CALayer layer];
            bar.backgroundColor = SPTheme.accentColor.CGColor;
            bar.cornerRadius = 1.25;
            bar.anchorPoint = CGPointMake(0.5, 1.0);
            bar.bounds = CGRectMake(0, 0, 2.5, idleHeights[i]);
            bar.position = CGPointMake(xOffsets[i] + 1.25, 12.0);
            [self.layer addSublayer:bar];
            [layers addObject:bar];
        }
        _bars = [layers copy];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(12, 12);
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && self.animating) {
        [self startAnimations];
    }
}

- (void)setAnimating:(BOOL)animating {
    if (_animating == animating) return;
    _animating = animating;
    if (animating) {
        [self startAnimations];
    } else {
        [self stopAnimations];
    }
}

- (void)startAnimations {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self stopAnimations];
        return;
    }
    CFTimeInterval durations[] = { 0.42, 0.58, 0.49 };
    CFTimeInterval offsets[] = { 0.0, 0.18, 0.09 };
    for (NSInteger i = 0; i < (NSInteger)self.bars.count; i++) {
        CALayer *bar = self.bars[i];
        [bar removeAnimationForKey:@"wave"];
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"bounds.size.height"];
        anim.fromValue = @(3.0);
        anim.toValue = @(12.0);
        anim.duration = durations[i];
        anim.beginTime = CACurrentMediaTime() + offsets[i];
        anim.autoreverses = YES;
        anim.repeatCount = HUGE_VALF;
        anim.removedOnCompletion = NO;
        anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [bar addAnimation:anim forKey:@"wave"];
    }
}

- (void)stopAnimations {
    CGFloat idleHeights[] = { 4.0, 8.0, 5.0 };
    for (NSInteger i = 0; i < (NSInteger)self.bars.count; i++) {
        CALayer *bar = self.bars[i];
        [bar removeAnimationForKey:@"wave"];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        bar.bounds = CGRectMake(0, 0, 2.5, idleHeights[i]);
        [CATransaction commit];
    }
}

@end
