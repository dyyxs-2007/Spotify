//
//  SPBrandMarkView.m
//  Spotify
//

#import "SPBrandMarkView.h"

@interface SPBrandMarkView ()
@property (nonatomic, strong) CAShapeLayer *circleLayer;
@property (nonatomic, copy) NSArray<CAShapeLayer *> *waveLayers;
@end

@implementation SPBrandMarkView

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithCircleColor:SPTheme.brandGreenColor waveColor:[UIColor sp_colorWithHex:0x0B0B0C]];
}

- (instancetype)initWithCircleColor:(UIColor *)circleColor waveColor:(UIColor *)waveColor {
    if (self = [super initWithFrame:CGRectZero]) {
        _circleColor = circleColor;
        _waveColor = waveColor;
        self.userInteractionEnabled = NO;

        _circleLayer = [CAShapeLayer layer];
        _circleLayer.fillColor = circleColor.CGColor;
        [self.layer addSublayer:_circleLayer];

        NSMutableArray<CAShapeLayer *> *waves = [NSMutableArray arrayWithCapacity:3];
        for (int i = 0; i < 3; i++) {
            CAShapeLayer *wave = [CAShapeLayer layer];
            wave.fillColor = UIColor.clearColor.CGColor;
            wave.strokeColor = waveColor.CGColor;
            wave.lineCap = kCALineCapRound;
            wave.lineJoin = kCALineJoinRound;
            [self.layer addSublayer:wave];
            [waves addObject:wave];
        }
        _waveLayers = [waves copy];
    }
    return self;
}

- (void)setCircleColor:(UIColor *)circleColor {
    _circleColor = circleColor;
    [self updateLayerColors];
}

- (void)setWaveColor:(UIColor *)waveColor {
    _waveColor = waveColor;
    [self updateLayerColors];
}

- (void)updateLayerColors {
    self.circleLayer.fillColor = [self.circleColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    CGColorRef stroke = [self.waveColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    for (CAShapeLayer *wave in self.waveLayers) {
        wave.strokeColor = stroke;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateLayerColors];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    if (side <= 0) return;

    CGRect circleRect = CGRectMake((CGRectGetWidth(self.bounds) - side) * 0.5,
                                   (CGRectGetHeight(self.bounds) - side) * 0.5,
                                   side, side);
    self.circleLayer.frame = self.bounds;
    self.circleLayer.path = [UIBezierPath bezierPathWithOvalInRect:circleRect].CGPath;

    // 柔和声波弧线（带微妙的有机倾斜角）
    struct {
        CGFloat x0, y0, cx, cy, x1, y1, widthFactor;
    } specs[3] = {
        {0.23, 0.36, 0.51, 0.25, 0.79, 0.40, 0.088},
        {0.27, 0.51, 0.50, 0.42, 0.74, 0.55, 0.078},
        {0.31, 0.65, 0.49, 0.58, 0.68, 0.68, 0.068},
    };

    CGFloat ox = CGRectGetMinX(circleRect);
    CGFloat oy = CGRectGetMinY(circleRect);
    for (int i = 0; i < 3; i++) {
        CAShapeLayer *wave = self.waveLayers[i];
        wave.frame = self.bounds;
        wave.lineWidth = side * specs[i].widthFactor;
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(ox + side * specs[i].x0, oy + side * specs[i].y0)];
        [path addQuadCurveToPoint:CGPointMake(ox + side * specs[i].x1, oy + side * specs[i].y1)
                     controlPoint:CGPointMake(ox + side * specs[i].cx, oy + side * specs[i].cy)];
        wave.path = path.CGPath;
    }
}

@end
