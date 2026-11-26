//
//  SPListeningStatsViewController.m
//  Spotify
//
//  「听歌统计」页面：原生编辑式排版、单调三次样条趋势曲线、24h 声波节律条、常听歌手与真实单曲排行。
//

#import "SPListeningStatsViewController.h"
#import "SPListeningStatsStore.h"
#import "SPAuthService.h"
#import "SPGradientView.h"
#import "SPScaleButton.h"
#import "SPDetailViewController.h"
#import "SPMusicRepository.h"
#import "SPPlayerService.h"
#import "UIImage+SPDominantColor.h"
#import "UIImageView+SPCover.h"
#import "SPHaptics.h"
#import "SPToast.h"

#pragma mark - Honest Duration Formatters & Row Helper

static NSString *SPStatsFormatCompactDuration(NSTimeInterval seconds) {
    if (seconds <= 0.5) return @"—";
    if (seconds < 60.0) {
        return [NSString stringWithFormat:@"%ld秒", (long)MAX(1, llround(seconds))];
    }
    if (seconds < 7200.0) {
        return [NSString stringWithFormat:@"%ld分钟", (long)MAX(1, llround(seconds / 60.0))];
    }
    return [NSString stringWithFormat:@"%.1f小时", seconds / 3600.0];
}

static NSString *SPStatsFormatSpacedDuration(NSTimeInterval seconds) {
    if (seconds <= 0.5) return @"0 分钟";
    if (seconds < 60.0) {
        return [NSString stringWithFormat:@"%ld 秒", (long)MAX(1, llround(seconds))];
    }
    if (seconds < 7200.0) {
        return [NSString stringWithFormat:@"%ld 分钟", (long)MAX(1, llround(seconds / 60.0))];
    }
    return [NSString stringWithFormat:@"%.1f 小时", seconds / 3600.0];
}

@interface SPHighlightRowButton : SPScaleButton
@end

@implementation SPHighlightRowButton

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    UIColor *target = highlighted ? SPTheme.highlightColor : UIColor.clearColor;
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.backgroundColor = target;
    } else {
        [UIView animateWithDuration:0.12
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.backgroundColor = target;
        } completion:nil];
    }
}

@end

#pragma mark - Monotone Cubic Spline Interactive Curve View

@interface SPListeningCurveChartView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSArray<SPListeningChartPoint *> *points;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy, nullable) void (^selectionChangedHandler)(SPListeningChartPoint *point, NSInteger index);

@property (nonatomic, strong) CAShapeLayer *gridLayer;
@property (nonatomic, strong) CAGradientLayer *areaGradientLayer;
@property (nonatomic, strong) CAShapeLayer *areaMaskLayer;
@property (nonatomic, strong) CAShapeLayer *lineLayer;
@property (nonatomic, strong) CAShapeLayer *dotsLayer;
@property (nonatomic, strong) CAShapeLayer *cursorLineLayer;
@property (nonatomic, strong) UIView *cursorHaloView;
@property (nonatomic, strong) UIView *cursorDotView;

@property (nonatomic, copy) NSArray<UILabel *> *yAxisLabels;
@property (nonatomic, strong) UIView *xAxisContainer;
@property (nonatomic, copy) NSArray<UILabel *> *xAxisLabels;
@property (nonatomic, copy) NSArray<NSValue *> *cachedPlotPoints;
@property (nonatomic, assign) CGRect lastRenderedBounds;
@property (nonatomic, assign) NSUInteger previousPointCount;
@property (nonatomic, assign) BOOL hasPlayedEntrance;
@property (nonatomic, assign) BOOL pendingEntranceAnimation;
@end

@implementation SPListeningCurveChartView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;
        [self setupLayersAndControls];
    }
    return self;
}

- (void)setupLayersAndControls {
    _gridLayer = [CAShapeLayer layer];
    _gridLayer.fillColor = UIColor.clearColor.CGColor;
    _gridLayer.lineWidth = 1.0 / UIScreen.mainScreen.scale;
    [self.layer addSublayer:_gridLayer];

    _areaGradientLayer = [CAGradientLayer layer];
    _areaGradientLayer.startPoint = CGPointMake(0.5, 0.0);
    _areaGradientLayer.endPoint = CGPointMake(0.5, 1.0);
    _areaMaskLayer = [CAShapeLayer layer];
    _areaGradientLayer.mask = _areaMaskLayer;
    [self.layer addSublayer:_areaGradientLayer];

    _cursorLineLayer = [CAShapeLayer layer];
    _cursorLineLayer.fillColor = UIColor.clearColor.CGColor;
    _cursorLineLayer.lineWidth = 1.0 / UIScreen.mainScreen.scale;
    [self.layer addSublayer:_cursorLineLayer];

    _lineLayer = [CAShapeLayer layer];
    _lineLayer.fillColor = UIColor.clearColor.CGColor;
    _lineLayer.lineWidth = 2.5;
    _lineLayer.lineCap = kCALineCapRound;
    _lineLayer.lineJoin = kCALineJoinRound;
    [self.layer addSublayer:_lineLayer];

    _dotsLayer = [CAShapeLayer layer];
    _dotsLayer.strokeColor = UIColor.clearColor.CGColor;
    [self.layer addSublayer:_dotsLayer];

    NSMutableArray<UILabel *> *yLabels = [NSMutableArray arrayWithCapacity:3];
    for (int i = 0; i < 3; i++) {
        UILabel *lbl = [UILabel new];
        lbl.font = [SPTheme monospacedDigitFontOfSize:10.5 weight:UIFontWeightMedium];
        lbl.textColor = SPTheme.textTertiaryColor;
        lbl.textAlignment = NSTextAlignmentRight;
        [self addSubview:lbl];
        [yLabels addObject:lbl];
    }
    _yAxisLabels = yLabels;

    _xAxisContainer = [UIView new];
    _xAxisContainer.userInteractionEnabled = NO;
    [self addSubview:_xAxisContainer];

    _cursorHaloView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 16)];
    _cursorHaloView.layer.cornerRadius = 8;
    _cursorHaloView.userInteractionEnabled = NO;
    [self addSubview:_cursorHaloView];

    _cursorDotView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 9, 9)];
    _cursorDotView.layer.cornerRadius = 4.5;
    _cursorDotView.layer.borderWidth = 2.5;
    _cursorDotView.userInteractionEnabled = NO;
    [self addSubview:_cursorDotView];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleScrubGesture:)];
    pan.delegate = self;
    [self addGestureRecognizer:pan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleScrubGesture:)];
    [self addGestureRecognizer:tap];

    [self updateLayerColors];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class]) {
        CGPoint v = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
        return fabs(v.x) >= fabs(v.y) * 0.65;
    }
    return YES;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateLayerColors];
    }
}

- (void)updateLayerColors {
    UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self];
    BOOL isLight = (tc.userInterfaceStyle == UIUserInterfaceStyleLight);
    UIColor *accent = [SPTheme.accentColor resolvedColorWithTraitCollection:tc];
    UIColor *sep = [SPTheme.separatorColor resolvedColorWithTraitCollection:tc];
    UIColor *textPrimary = [SPTheme.textPrimaryColor resolvedColorWithTraitCollection:tc];
    UIColor *bg = [SPTheme.backgroundColor resolvedColorWithTraitCollection:tc];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.gridLayer.strokeColor = [sep colorWithAlphaComponent:(isLight ? 0.70 : 0.55)].CGColor;
    self.lineLayer.strokeColor = accent.CGColor;
    self.lineLayer.shadowOpacity = 0.0f;
    self.dotsLayer.fillColor = accent.CGColor;

    self.areaGradientLayer.colors = @[
        (__bridge id)[accent colorWithAlphaComponent:(isLight ? 0.14 : 0.18)].CGColor,
        (__bridge id)[accent colorWithAlphaComponent:(isLight ? 0.03 : 0.04)].CGColor,
        (__bridge id)[accent colorWithAlphaComponent:0.0].CGColor,
    ];
    self.areaGradientLayer.locations = @[@0.0, @0.65, @1.0];
    self.cursorLineLayer.strokeColor = [textPrimary colorWithAlphaComponent:(isLight ? 0.22 : 0.24)].CGColor;
    [CATransaction commit];

    self.cursorHaloView.backgroundColor = [accent colorWithAlphaComponent:(isLight ? 0.14 : 0.20)];
    self.cursorDotView.backgroundColor = bg;
    self.cursorDotView.layer.borderColor = accent.CGColor;
}

- (CGRect)plotRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(12, SPMarginHorizontal, 30, 50));
}

- (void)setPoints:(NSArray<SPListeningChartPoint *> *)points
         animated:(BOOL)animated
preserveSelection:(BOOL)preserveSelection {
    BOOL sameCount = (_points.count == points.count);
    _points = [points copy] ?: @[];
    if (!(preserveSelection && sameCount && _selectedIndex >= 0 && _selectedIndex < (NSInteger)_points.count)) {
        NSInteger focusIdx = MAX(0, (NSInteger)_points.count - 1);
        for (NSInteger i = 0; i < (NSInteger)_points.count; i++) {
            if (_points[i].isDefaultFocus) {
                focusIdx = i;
                break;
            }
        }
        _selectedIndex = focusIdx;
    }
    self.lastRenderedBounds = CGRectZero;
    [self rebuildChartLayoutAnimated:animated];
}

- (void)playEntranceAnimationIfNeeded {
    if (self.hasPlayedEntrance || self.points.count == 0) return;
    if (self.lineLayer.path == NULL) {
        self.pendingEntranceAnimation = YES;
        return;
    }
    self.hasPlayedEntrance = YES;
    self.pendingEntranceAnimation = NO;
    if (UIAccessibilityIsReduceMotionEnabled()) return;

    [self.lineLayer removeAllAnimations];
    [self.areaGradientLayer removeAllAnimations];
    [self.dotsLayer removeAllAnimations];

    CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    draw.fromValue = @0.0;
    draw.toValue = @1.0;
    draw.duration = 0.48;
    draw.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [self.lineLayer addAnimation:draw forKey:@"sp_drawStroke"];

    CABasicAnimation *fadeArea = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeArea.fromValue = @0.0;
    fadeArea.toValue = @1.0;
    fadeArea.duration = 0.36;
    fadeArea.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [self.areaGradientLayer addAnimation:fadeArea forKey:@"sp_areaFade"];
    [self.dotsLayer addAnimation:fadeArea forKey:@"sp_dotsFade"];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGRectEqualToRect(self.bounds, self.lastRenderedBounds) && !CGRectIsEmpty(self.bounds)) {
        self.lastRenderedBounds = self.bounds;
        [self rebuildChartLayoutAnimated:NO];
    }
}

+ (CGFloat)niceCeilingForMaxMinutes:(CGFloat)rawMax hasAnyPlay:(BOOL)hasAnyPlay {
    if (rawMax <= 0.01) {
        return hasAnyPlay ? (20.0 / 60.0) : 10.0;
    }
    if (rawMax <= 0.30) return 20.0 / 60.0;
    if (rawMax <= 0.60) return 40.0 / 60.0;
    if (rawMax <= 0.90) return 1.0;
    if (rawMax <= 1.5) return 2.0;
    if (rawMax <= 5.5) return 6.0;
    if (rawMax <= 9.5) return 10.0;
    if (rawMax <= 19.0) return 20.0;
    if (rawMax <= 28.0) return 30.0;
    if (rawMax <= 40.0) return 40.0;
    if (rawMax <= 60.0) return 60.0;
    if (rawMax <= 90.0) return 90.0;
    if (rawMax <= 120.0) return 120.0;
    return ceil(rawMax / 40.0) * 40.0;
}

+ (UIBezierPath *)monotoneCubicPathWithPoints:(NSArray<NSValue *> *)pts {
    UIBezierPath *path = [UIBezierPath bezierPath];
    NSUInteger n = pts.count;
    if (n == 0) return path;
    CGPoint p0 = [pts[0] CGPointValue];
    [path moveToPoint:p0];
    if (n == 1) return path;
    if (n == 2) {
        [path addLineToPoint:[pts[1] CGPointValue]];
        return path;
    }

    double *xs = calloc(n, sizeof(double));
    double *ys = calloc(n, sizeof(double));
    double *deltas = calloc(n - 1, sizeof(double));
    double *ms = calloc(n, sizeof(double));
    if (!xs || !ys || !deltas || !ms) {
        free(xs); free(ys); free(deltas); free(ms);
        for (NSUInteger i = 1; i < n; i++) [path addLineToPoint:[pts[i] CGPointValue]];
        return path;
    }

    for (NSUInteger i = 0; i < n; i++) {
        CGPoint p = [pts[i] CGPointValue];
        xs[i] = p.x;
        ys[i] = p.y;
    }
    for (NSUInteger k = 0; k < n - 1; k++) {
        double dx = xs[k + 1] - xs[k];
        deltas[k] = (dx > 1e-4) ? ((ys[k + 1] - ys[k]) / dx) : 0.0;
    }
    ms[0] = deltas[0];
    ms[n - 1] = deltas[n - 2];
    for (NSUInteger k = 1; k < n - 1; k++) {
        ms[k] = (deltas[k - 1] * deltas[k] <= 0.0) ? 0.0 : 0.5 * (deltas[k - 1] + deltas[k]);
    }
    for (NSUInteger k = 0; k < n - 1; k++) {
        if (fabs(deltas[k]) < 1e-5) {
            ms[k] = 0.0;
            ms[k + 1] = 0.0;
        } else {
            double alpha = ms[k] / deltas[k];
            double beta = ms[k + 1] / deltas[k];
            double sq = alpha * alpha + beta * beta;
            if (sq > 9.0) {
                double tau = 3.0 / sqrt(sq);
                ms[k] = tau * alpha * deltas[k];
                ms[k + 1] = tau * beta * deltas[k];
            }
        }
    }

    for (NSUInteger k = 0; k < n - 1; k++) {
        double dx = xs[k + 1] - xs[k];
        CGPoint cp1 = CGPointMake(xs[k] + dx / 3.0, ys[k] + ms[k] * dx / 3.0);
        CGPoint cp2 = CGPointMake(xs[k + 1] - dx / 3.0, ys[k + 1] - ms[k + 1] * dx / 3.0);
        [path addCurveToPoint:[pts[k + 1] CGPointValue] controlPoint1:cp1 controlPoint2:cp2];
    }

    free(xs);
    free(ys);
    free(deltas);
    free(ms);
    return path;
}

- (void)rebuildChartLayoutAnimated:(BOOL)animated {
    CGRect b = self.bounds;
    if (CGRectIsEmpty(b)) return;
    if (self.points.count == 0) {
        [self.lineLayer removeAllAnimations];
        [self.areaMaskLayer removeAllAnimations];
        [self.areaGradientLayer removeAllAnimations];
        [self.dotsLayer removeAllAnimations];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.gridLayer.path = NULL;
        self.lineLayer.path = NULL;
        self.areaMaskLayer.path = NULL;
        self.dotsLayer.path = NULL;
        self.cursorLineLayer.path = NULL;
        [CATransaction commit];
        self.cursorHaloView.hidden = YES;
        self.cursorDotView.hidden = YES;
        for (UIView *sub in self.xAxisContainer.subviews) [sub removeFromSuperview];
        self.xAxisLabels = @[];
        self.cachedPlotPoints = @[];
        self.previousPointCount = 0;
        return;
    }

    CGRect plotRect = [self plotRectForBounds:b];
    if (CGRectGetWidth(plotRect) <= 20 || CGRectGetHeight(plotRect) <= 20) return;

    self.cursorHaloView.hidden = NO;
    self.cursorDotView.hidden = NO;

    CGFloat rawMax = 0.0;
    BOOL hasAnyPlay = NO;
    for (SPListeningChartPoint *pt in self.points) {
        if (pt.minutes > rawMax) rawMax = pt.minutes;
        if (pt.playCount > 0) hasAnyPlay = YES;
    }
    CGFloat yMax = [SPListeningCurveChartView niceCeilingForMaxMinutes:rawMax hasAnyPlay:hasAnyPlay];

    // 1. 水平参考细线 + 右对齐等宽 Y 轴刻度
    UIBezierPath *gridPath = [UIBezierPath bezierPath];
    NSArray<NSNumber *> *ratios = @[@0.0, @0.5, @1.0];
    NSArray<NSString *> *yTexts = nil;
    if (yMax < 1.05) {
        NSInteger topSec = (NSInteger)llround(yMax * 60.0);
        yTexts = @[
            [NSString stringWithFormat:@"%lds", (long)topSec],
            [NSString stringWithFormat:@"%lds", (long)(topSec / 2)],
            @"0s",
        ];
    } else {
        yTexts = @[
            [NSString stringWithFormat:@"%.0fm", yMax],
            [NSString stringWithFormat:@"%.0fm", yMax * 0.5],
            @"0m",
        ];
    }
    for (NSUInteger i = 0; i < 3; i++) {
        CGFloat y = CGRectGetMinY(plotRect) + CGRectGetHeight(plotRect) * ratios[i].doubleValue;
        [gridPath moveToPoint:CGPointMake(CGRectGetMinX(plotRect), y)];
        [gridPath addLineToPoint:CGPointMake(CGRectGetMaxX(plotRect), y)];

        UILabel *lbl = self.yAxisLabels[i];
        lbl.text = yTexts[i];
        lbl.frame = CGRectMake(CGRectGetMaxX(plotRect) + 6, y - 7, 30, 14);
    }

    // 2. 数据节点坐标、点标与 X 轴刻度
    for (UIView *sub in self.xAxisContainer.subviews) [sub removeFromSuperview];
    self.xAxisContainer.frame = CGRectMake(0, CGRectGetMaxY(plotRect) + 8, CGRectGetWidth(b), 18);

    NSUInteger count = self.points.count;
    NSMutableArray<NSValue *> *coords = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<UILabel *> *xLabels = [NSMutableArray array];
    UIBezierPath *dotsPath = [UIBezierPath bezierPath];

    for (NSUInteger i = 0; i < count; i++) {
        CGFloat t = (count > 1) ? ((CGFloat)i / (CGFloat)(count - 1)) : 0.5;
        CGFloat x = CGRectGetMinX(plotRect) + t * CGRectGetWidth(plotRect);
        CGFloat norm = MIN(MAX(self.points[i].minutes / yMax, 0.0), 1.0);
        if (norm <= 0.001 && self.points[i].playCount > 0) {
            norm = 0.04; // 有真实播放但不足 1 秒时给出轻微基线抬升以区别于空日
        }
        CGFloat y = CGRectGetMaxY(plotRect) - norm * CGRectGetHeight(plotRect);
        [coords addObject:[NSValue valueWithCGPoint:CGPointMake(x, y)]];

        if (self.points[i].minutes > 0.01 || self.points[i].playCount > 0) {
            [dotsPath appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x - 2.0, y - 2.0, 4.0, 4.0)]];
        }

        NSString *xText = self.points[i].axisLabel;
        if (xText.length > 0) {
            BOOL selected = ((NSInteger)i == self.selectedIndex);
            UILabel *xl = [UILabel new];
            xl.tag = (NSInteger)i;
            xl.text = xText;
            xl.font = [SPTheme monospacedDigitFontOfSize:10.5 weight:(selected ? UIFontWeightBold : UIFontWeightMedium)];
            xl.textColor = selected ? SPTheme.accentColor : SPTheme.textTertiaryColor;
            xl.textAlignment = NSTextAlignmentCenter;
            [xl sizeToFit];
            CGFloat w = MAX(CGRectGetWidth(xl.bounds) + 4, 24);
            CGFloat clampedX = MIN(MAX(x - w * 0.5, CGRectGetMinX(plotRect) - 4.0), CGRectGetMaxX(plotRect) - w + 6.0);
            xl.frame = CGRectMake(clampedX, 0, w, 15);
            [self.xAxisContainer addSubview:xl];
            [xLabels addObject:xl];
        }
    }
    self.xAxisLabels = xLabels;
    self.cachedPlotPoints = coords;

    // 3. 单调三次样条曲线与渐变闭合路径
    UIBezierPath *curvePath = [SPListeningCurveChartView monotoneCubicPathWithPoints:coords];
    UIBezierPath *areaPath = [curvePath copy];
    CGPoint firstPt = [coords.firstObject CGPointValue];
    CGPoint lastPt = [coords.lastObject CGPointValue];
    [areaPath addLineToPoint:CGPointMake(lastPt.x, CGRectGetMaxY(plotRect))];
    [areaPath addLineToPoint:CGPointMake(firstPt.x, CGRectGetMaxY(plotRect))];
    [areaPath closePath];

    BOOL useAnim = animated && !UIAccessibilityIsReduceMotionEnabled();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.gridLayer.path = gridPath.CGPath;
    self.areaGradientLayer.frame = b;
    self.areaMaskLayer.frame = b;
    self.lineLayer.frame = b;
    self.dotsLayer.frame = b;
    [self updateLayerColors];
    [CATransaction commit];

    [self.lineLayer removeAllAnimations];
    [self.areaMaskLayer removeAllAnimations];
    [self.areaGradientLayer removeAllAnimations];
    [self.dotsLayer removeAllAnimations];

    BOOL canMorphPath = (self.lineLayer.path != NULL && self.previousPointCount == count && self.hasPlayedEntrance);
    if (useAnim && canMorphPath) {
        CABasicAnimation *lineMorph = [CABasicAnimation animationWithKeyPath:@"path"];
        lineMorph.fromValue = (__bridge id)self.lineLayer.path;
        lineMorph.toValue = (__bridge id)curvePath.CGPath;
        lineMorph.duration = 0.26;
        lineMorph.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [self.lineLayer addAnimation:lineMorph forKey:@"sp_pathMorph"];

        CABasicAnimation *areaMorph = [CABasicAnimation animationWithKeyPath:@"path"];
        areaMorph.fromValue = (__bridge id)self.areaMaskLayer.path;
        areaMorph.toValue = (__bridge id)areaPath.CGPath;
        areaMorph.duration = 0.26;
        areaMorph.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [self.areaMaskLayer addAnimation:areaMorph forKey:@"sp_areaMorph"];
    } else if (useAnim && self.hasPlayedEntrance) {
        CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        draw.fromValue = @0.0;
        draw.toValue = @1.0;
        draw.duration = 0.38;
        draw.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [self.lineLayer addAnimation:draw forKey:@"sp_drawStroke"];

        CABasicAnimation *fadeArea = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fadeArea.fromValue = @0.0;
        fadeArea.toValue = @1.0;
        fadeArea.duration = 0.30;
        fadeArea.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [self.areaGradientLayer addAnimation:fadeArea forKey:@"sp_areaFade"];
        [self.dotsLayer addAnimation:fadeArea forKey:@"sp_dotsFade"];
    }
    self.previousPointCount = count;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.lineLayer.path = curvePath.CGPath;
    self.areaMaskLayer.path = areaPath.CGPath;
    self.dotsLayer.path = dotsPath.CGPath;
    [CATransaction commit];

    [self updateCursorAtIndex:self.selectedIndex plotBottomY:CGRectGetMaxY(plotRect) plotTopY:CGRectGetMinY(plotRect) animated:NO];
    if (self.pendingEntranceAnimation) {
        [self playEntranceAnimationIfNeeded];
    }
}

- (void)updateCursorAtIndex:(NSInteger)index plotBottomY:(CGFloat)bottomY plotTopY:(CGFloat)topY animated:(BOOL)animated {
    if (index < 0 || index >= (NSInteger)self.cachedPlotPoints.count) return;
    CGPoint pt = [self.cachedPlotPoints[index] CGPointValue];

    for (UILabel *xl in self.xAxisLabels) {
        BOOL selected = (xl.tag == index);
        xl.font = [SPTheme monospacedDigitFontOfSize:10.5 weight:(selected ? UIFontWeightBold : UIFontWeightMedium)];
        xl.textColor = selected ? SPTheme.accentColor : SPTheme.textTertiaryColor;
    }

    UIBezierPath *vLine = [UIBezierPath bezierPath];
    [vLine moveToPoint:CGPointMake(pt.x, topY)];
    [vLine addLineToPoint:CGPointMake(pt.x, bottomY)];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.cursorLineLayer.path = vLine.CGPath;
    [CATransaction commit];

    void (^moveDot)(void) = ^{
        self.cursorHaloView.center = pt;
        self.cursorDotView.center = pt;
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.14
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:moveDot
                         completion:nil];
    } else {
        moveDot();
    }
}

- (void)handleScrubGesture:(UIGestureRecognizer *)gesture {
    if (self.cachedPlotPoints.count == 0) return;
    CGPoint loc = [gesture locationInView:self];
    NSInteger bestIdx = 0;
    CGFloat bestDist = CGFLOAT_MAX;
    for (NSInteger i = 0; i < (NSInteger)self.cachedPlotPoints.count; i++) {
        CGPoint pt = [self.cachedPlotPoints[i] CGPointValue];
        CGFloat d = fabs(pt.x - loc.x);
        if (d < bestDist) {
            bestDist = d;
            bestIdx = i;
        }
    }

    CGRect plotRect = [self plotRectForBounds:self.bounds];
    if (bestIdx != self.selectedIndex) {
        self.selectedIndex = bestIdx;
        [SPHaptics selection];
        [self updateCursorAtIndex:bestIdx
                      plotBottomY:CGRectGetMaxY(plotRect)
                         plotTopY:CGRectGetMinY(plotRect)
                         animated:YES];
        if (self.selectionChangedHandler && bestIdx < (NSInteger)self.points.count) {
            self.selectionChangedHandler(self.points[bestIdx], bestIdx);
        }
    } else if (gesture.state == UIGestureRecognizerStateBegan || [gesture isKindOfClass:UITapGestureRecognizer.class]) {
        if (self.selectionChangedHandler && bestIdx < (NSInteger)self.points.count) {
            self.selectionChangedHandler(self.points[bestIdx], bestIdx);
        }
    }
}

@end

#pragma mark - 24-Hour Acoustic Equalizer Skyline View

@interface SPAcousticRhythmView : UIView
@property (nonatomic, copy) NSArray<NSNumber *> *hourlyMinutes;
@property (nonatomic, copy) NSArray<NSNumber *> *hourlyPlays;
@property (nonatomic, assign) NSInteger peakHour;
@property (nonatomic, copy) NSArray<UIView *> *barViews;
@property (nonatomic, copy) NSArray<UILabel *> *axisLabels;
@property (nonatomic, copy) NSArray<NSNumber *> *axisHours;
@end

@implementation SPAcousticRhythmView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _peakHour = -1;
        NSMutableArray<UIView *> *bars = [NSMutableArray arrayWithCapacity:24];
        for (NSInteger h = 0; h < 24; h++) {
            UIView *bar = [UIView new];
            bar.layer.cornerCurve = kCACornerCurveContinuous;
            [self addSubview:bar];
            [bars addObject:bar];
        }
        _barViews = bars;

        _axisHours = @[@0, @6, @12, @18, @23];
        NSArray<NSString *> *titles = @[@"00:00", @"06:00", @"12:00", @"18:00", @"23:00"];
        NSMutableArray<UILabel *> *labels = [NSMutableArray arrayWithCapacity:titles.count];
        for (NSString *title in titles) {
            UILabel *lbl = [UILabel new];
            lbl.text = title;
            lbl.font = [SPTheme monospacedDigitFontOfSize:10 weight:UIFontWeightMedium];
            lbl.textColor = SPTheme.textTertiaryColor;
            [lbl sizeToFit];
            [self addSubview:lbl];
            [labels addObject:lbl];
        }
        _axisLabels = labels;
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self setNeedsLayout];
    }
}

- (void)configureWithHourlyMinutes:(NSArray<NSNumber *> *)hourlyMinutes
                       hourlyPlays:(NSArray<NSNumber *> *)hourlyPlays
                          peakHour:(NSInteger)peakHour {
    self.hourlyMinutes = hourlyMinutes ?: @[];
    self.hourlyPlays = hourlyPlays ?: @[];
    self.peakHour = peakHour;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    if (w <= 48 || h <= 24) return;

    UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self];
    BOOL isLight = (tc.userInterfaceStyle == UIUserInterfaceStyleLight);
    UIColor *accent = [SPTheme.accentColor resolvedColorWithTraitCollection:tc];
    UIColor *textPrimary = [SPTheme.textPrimaryColor resolvedColorWithTraitCollection:tc];

    UIColor *idleBarColor = [textPrimary colorWithAlphaComponent:(isLight ? 0.08 : 0.10)];
    UIColor *midBarColor = [accent colorWithAlphaComponent:(isLight ? 0.36 : 0.44)];

    CGFloat plotH = MAX(18.0, h - 20.0);
    CGFloat barW = MIN(6.0, MAX(3.5, floor(w / 52.0)));
    CGFloat maxBarH = plotH - 4.0;
    CGFloat minIdleH = 4.0;
    CGFloat minActiveH = 10.0;

    double maxMins = 0.0;
    NSUInteger maxPlays = 0;
    for (NSUInteger i = 0; i < 24; i++) {
        double m = (i < self.hourlyMinutes.count) ? MAX(0.0, self.hourlyMinutes[i].doubleValue) : 0.0;
        NSUInteger p = (i < self.hourlyPlays.count) ? self.hourlyPlays[i].unsignedIntegerValue : 0;
        if (m > maxMins) maxMins = m;
        if (p > maxPlays) maxPlays = p;
    }
    BOOL useMinutes = (maxMins > 0.01);
    double denom = useMinutes ? maxMins : MAX(1.0, (double)maxPlays);

    for (NSUInteger i = 0; i < 24; i++) {
        double m = (i < self.hourlyMinutes.count) ? MAX(0.0, self.hourlyMinutes[i].doubleValue) : 0.0;
        NSUInteger p = (i < self.hourlyPlays.count) ? self.hourlyPlays[i].unsignedIntegerValue : 0;
        BOOL isActive = (m > 0.005 || p > 0);
        double val = useMinutes ? m : (double)p;
        CGFloat ratio = isActive ? MIN(1.0, MAX(0.0, (CGFloat)(val / denom))) : 0.0;
        CGFloat barH = isActive ? (minActiveH + ratio * MAX(0.0, maxBarH - minActiveH)) : minIdleH;
        CGFloat x = (w - barW) * ((CGFloat)i / 23.0);

        UIView *bar = self.barViews[i];
        bar.frame = CGRectMake(x, plotH - barH, barW, barH);
        bar.layer.cornerRadius = barW * 0.5;
        if (!isActive) {
            bar.backgroundColor = idleBarColor;
        } else if ((NSInteger)i == self.peakHour || ratio >= 0.88) {
            bar.backgroundColor = accent;
        } else {
            bar.backgroundColor = midBarColor;
        }
    }

    for (NSUInteger i = 0; i < self.axisLabels.count; i++) {
        UILabel *lbl = self.axisLabels[i];
        NSInteger hourIdx = self.axisHours[i].integerValue;
        CGFloat barCenterX = (w - barW) * ((CGFloat)hourIdx / 23.0) + barW * 0.5;
        CGFloat lw = CGRectGetWidth(lbl.bounds);
        CGFloat lh = CGRectGetHeight(lbl.bounds);
        CGFloat clampedX = MIN(MAX(barCenterX - lw * 0.5, 0.0), w - lw);
        lbl.frame = CGRectMake(clampedX, plotH + 6.0, lw, lh);
    }
}

@end

#pragma mark - SPListeningStatsViewController

@interface SPListeningStatsViewController () <UIScrollViewDelegate, SPAuthObserver>
@property (nonatomic, strong) SPGradientView *ambientGradient;
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UILabel *navTitleLabel;
@property (nonatomic, strong) SPScaleButton *moreButton;
@property (nonatomic, strong) UIView *navDivider;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UILabel *pageTitleLabel;
@property (nonatomic, strong) UILabel *pageSubtitleLabel;

@property (nonatomic, strong) UIView *tabContainer;
@property (nonatomic, strong) UIView *tabHairline;
@property (nonatomic, strong) UIView *tabUnderlineView;
@property (nonatomic, copy) NSArray<SPScaleButton *> *rangeTabButtons;

@property (nonatomic, strong) UILabel *focusHeroLabel;
@property (nonatomic, strong) UILabel *focusDetailLabel;
@property (nonatomic, strong) SPListeningCurveChartView *curveChartView;

@property (nonatomic, strong) UIView *statStripContainer;
@property (nonatomic, copy) NSArray<UIView *> *statStripHairlines;
@property (nonatomic, strong) UILabel *statMinutesValueLabel;
@property (nonatomic, strong) UILabel *statPlaysValueLabel;
@property (nonatomic, strong) UILabel *statPeriodValueLabel;

@property (nonatomic, strong) UIView *rhythmSectionView;
@property (nonatomic, strong) UILabel *rhythmSubtitleLabel;
@property (nonatomic, strong) UIView *rhythmCard;
@property (nonatomic, strong) SPAcousticRhythmView *rhythmSkylineView;
@property (nonatomic, strong) UIView *rhythmDivider;
@property (nonatomic, copy) NSArray<UILabel *> *rhythmPercentLabels;

@property (nonatomic, strong) UIView *artistsSectionView;
@property (nonatomic, strong) UIScrollView *artistsScrollView;
@property (nonatomic, strong) UIStackView *artistsStack;

@property (nonatomic, strong) UIView *tracksSectionView;
@property (nonatomic, strong) UIStackView *tracksStack;

@property (nonatomic, assign, readwrite) SPListeningChartRange selectedRange;
@property (nonatomic, strong) SPListeningStatsSnapshot *activeSnapshot;
@property (nonatomic, copy, nullable) NSString *ambientTrackId;
@property (nonatomic, strong, nullable) UIColor *extractedAmbientColor;
@property (nonatomic, assign) CGRect lastUnderlineTargetFrame;
@property (nonatomic, copy, nullable) NSString *lastRankedSignature;
@end

@implementation SPListeningStatsViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return [SPTheme preferredStatusBarStyle]; }

- (void)dealloc {
    [[SPAuthService shared] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SPTheme.backgroundColor;
    [self setupViews];

    [[SPAuthService shared] addObserver:self];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(statsDidUpdate) name:SPListeningStatsDidUpdateNotification object:nil];
    [nc addObserver:self selector:@selector(themeDidChange) name:SPThemeDidChangeNotification object:nil];

    self.selectedRange = [self defaultRangeForSnapshot:[[SPListeningStatsStore shared] currentSnapshot]];
    [self updateRangeTabStyles];
    [self reloadSnapshotAnimated:NO preserveSelection:NO];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.curveChartView playEntranceAnimationIfNeeded];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutTabUnderlineAnimated:NO];
}

- (SPListeningChartRange)defaultRangeForSnapshot:(SPListeningStatsSnapshot *)snap {
    if (snap.activeDaysCount >= 2) return SPListeningChartRange7Days;
    if (snap.totalPlayCount > 0) return SPListeningChartRangeHourly;
    return SPListeningChartRange7Days;
}

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    self.ambientTrackId = nil;
    self.extractedAmbientColor = nil;
    SPListeningStatsSnapshot *real = [[SPListeningStatsStore shared] currentSnapshot];
    self.selectedRange = [self defaultRangeForSnapshot:real];
    [self updateRangeTabStyles];
    [self reloadSnapshotAnimated:NO preserveSelection:NO];
    [self layoutTabUnderlineAnimated:NO];
}

#pragma mark - UI Construction

- (void)setupViews {
    _ambientGradient = [SPGradientView new];
    [self.view addSubview:_ambientGradient];

    _navBar = [UIView new];
    _navBar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_navBar];

    SPScaleButton *backBtn = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [backBtn sp_setSymbol:@"chevron.left" size:18 weight:UIImageSymbolWeightSemibold animated:NO];
    backBtn.tintColor = SPTheme.textPrimaryColor;
    backBtn.accessibilityLabel = @"返回";
    [backBtn addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBar addSubview:backBtn];

    _navTitleLabel = [UILabel new];
    _navTitleLabel.text = @"听歌统计";
    _navTitleLabel.font = [SPTheme fontOfSize:17 weight:UIFontWeightBold];
    _navTitleLabel.textColor = SPTheme.textPrimaryColor;
    _navTitleLabel.alpha = 0.0;
    [_navBar addSubview:_navTitleLabel];

    _moreButton = [SPScaleButton buttonWithType:UIButtonTypeSystem];
    [_moreButton sp_setSymbol:@"ellipsis" size:18 weight:UIImageSymbolWeightMedium animated:NO];
    _moreButton.tintColor = SPTheme.textPrimaryColor;
    _moreButton.accessibilityLabel = @"更多选项";
    [_moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBar addSubview:_moreButton];

    _navDivider = [UIView new];
    _navDivider.backgroundColor = SPTheme.separatorColor;
    _navDivider.alpha = 0.0;
    [_navBar addSubview:_navDivider];

    _scrollView = [UIScrollView new];
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.delegate = self;
    _scrollView.contentInset = UIEdgeInsetsMake(4, 0, 36, 0);
    [self.view addSubview:_scrollView];

    _contentView = [UIView new];
    [_scrollView addSubview:_contentView];

    // 1. 开放式编辑页眉
    UIView *headerView = [UIView new];
    _pageTitleLabel = [UILabel new];
    _pageTitleLabel.text = @"听歌统计";
    _pageTitleLabel.font = [SPTheme fontOfSize:28 weight:UIFontWeightBold];
    _pageTitleLabel.textColor = SPTheme.textPrimaryColor;
    [headerView addSubview:_pageTitleLabel];

    _pageSubtitleLabel = [UILabel new];
    _pageSubtitleLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightMedium];
    _pageSubtitleLabel.textColor = SPTheme.textSecondaryColor;
    [headerView addSubview:_pageSubtitleLabel];

    [_pageTitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(headerView);
        make.left.equalTo(headerView).offset(SPMarginHorizontal);
        make.right.equalTo(headerView).offset(-SPMarginHorizontal);
    }];
    [_pageSubtitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.pageTitleLabel.mas_bottom).offset(4);
        make.left.right.equalTo(self.pageTitleLabel);
        make.bottom.equalTo(headerView);
    }];

    // 2. 下划线式时间范围标签页
    _tabContainer = [UIView new];
    NSArray<NSString *> *rangeTitles = @[@"近 7 日", @"24 小时", @"近 14 日"];
    NSMutableArray<SPScaleButton *> *tabs = [NSMutableArray arrayWithCapacity:rangeTitles.count];
    for (NSInteger i = 0; i < (NSInteger)rangeTitles.count; i++) {
        SPScaleButton *tab = [SPScaleButton buttonWithType:UIButtonTypeCustom];
        tab.isStatic = YES;
        tab.tag = i;
        [tab setTitle:rangeTitles[i] forState:UIControlStateNormal];
        [tab addTarget:self action:@selector(rangeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [tabs addObject:tab];
    }
    _rangeTabButtons = tabs;

    UIStackView *tabStack = [[UIStackView alloc] initWithArrangedSubviews:tabs];
    tabStack.axis = UILayoutConstraintAxisHorizontal;
    tabStack.alignment = UIStackViewAlignmentFill;
    tabStack.spacing = 24;
    [_tabContainer addSubview:tabStack];

    _tabHairline = [UIView new];
    _tabHairline.backgroundColor = SPTheme.separatorColor;
    [_tabContainer addSubview:_tabHairline];

    _tabUnderlineView = [UIView new];
    _tabUnderlineView.backgroundColor = SPTheme.accentColor;
    _tabUnderlineView.layer.cornerRadius = 1.25;
    [_tabContainer addSubview:_tabUnderlineView];

    [tabStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(self.tabContainer);
        make.left.equalTo(self.tabContainer).offset(SPMarginHorizontal);
        make.height.mas_equalTo(42);
    }];
    [_tabHairline mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.tabContainer);
        make.height.mas_equalTo(1.0 / UIScreen.mainScreen.scale);
    }];

    // 3. 开放式主读数 + 无框单调三次样条曲线
    UIView *chartSection = [UIView new];
    _focusHeroLabel = [UILabel new];
    _focusHeroLabel.adjustsFontSizeToFitWidth = YES;
    _focusHeroLabel.minimumScaleFactor = 0.8;
    [chartSection addSubview:_focusHeroLabel];

    _focusDetailLabel = [UILabel new];
    _focusDetailLabel.font = [SPTheme monospacedDigitFontOfSize:13 weight:UIFontWeightRegular];
    _focusDetailLabel.textColor = SPTheme.textSecondaryColor;
    [chartSection addSubview:_focusDetailLabel];

    _curveChartView = [SPListeningCurveChartView new];
    __weak typeof(self) weakSelf = self;
    _curveChartView.selectionChangedHandler = ^(SPListeningChartPoint *point, NSInteger index) {
        [weakSelf updateFocusReadoutWithPoint:point];
    };
    [chartSection addSubview:_curveChartView];

    [_focusHeroLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(chartSection).offset(6);
        make.left.equalTo(chartSection).offset(SPMarginHorizontal);
        make.right.equalTo(chartSection).offset(-SPMarginHorizontal);
    }];
    [_focusDetailLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.focusHeroLabel.mas_bottom).offset(4);
        make.left.right.equalTo(self.focusHeroLabel);
    }];
    [_curveChartView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.focusDetailLabel.mas_bottom).offset(12);
        make.left.right.bottom.equalTo(chartSection);
        make.height.mas_equalTo(194);
    }];

    // 4. 无框细线三栏摘要带
    _statStripContainer = [UIView new];
    UILabel *minVal = nil, *playVal = nil, *periodVal = nil;
    UIView *col1 = [self makeStatStripColumnWithCaption:@"累计聆听" valueLabel:&minVal];
    UIView *col2 = [self makeStatStripColumnWithCaption:@"播放次数" valueLabel:&playVal];
    UIView *col3 = [self makeStatStripColumnWithCaption:@"活跃时段" valueLabel:&periodVal];
    _statMinutesValueLabel = minVal;
    _statPlaysValueLabel = playVal;
    _statPeriodValueLabel = periodVal;
    _statPeriodValueLabel.font = [SPTheme fontOfSize:16.5 weight:UIFontWeightBold];

    UIStackView *stripCols = [[UIStackView alloc] initWithArrangedSubviews:@[col1, col2, col3]];
    stripCols.axis = UILayoutConstraintAxisHorizontal;
    stripCols.distribution = UIStackViewDistributionFillEqually;
    [_statStripContainer addSubview:stripCols];

    UIView *topRule = [UIView new];
    UIView *bottomRule = [UIView new];
    UIView *vRule1 = [UIView new];
    UIView *vRule2 = [UIView new];
    _statStripHairlines = @[topRule, bottomRule, vRule1, vRule2];
    for (UIView *r in _statStripHairlines) {
        r.backgroundColor = SPTheme.separatorColor;
        [_statStripContainer addSubview:r];
    }

    CGFloat px = 1.0 / UIScreen.mainScreen.scale;
    [topRule mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.statStripContainer);
        make.left.equalTo(self.statStripContainer).offset(SPMarginHorizontal);
        make.right.equalTo(self.statStripContainer).offset(-SPMarginHorizontal);
        make.height.mas_equalTo(px);
    }];
    [bottomRule mas_makeConstraints:^(MASConstraintMaker *make) {
        make.bottom.equalTo(self.statStripContainer);
        make.left.right.equalTo(topRule);
        make.height.mas_equalTo(px);
    }];
    [stripCols mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(self.statStripContainer);
        make.left.right.equalTo(topRule);
        make.height.mas_equalTo(72);
    }];
    [vRule1 mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(col1.mas_right);
        make.centerY.equalTo(stripCols);
        make.width.mas_equalTo(px);
        make.height.mas_equalTo(28);
    }];
    [vRule2 mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(col2.mas_right);
        make.centerY.equalTo(stripCols);
        make.width.mas_equalTo(px);
        make.height.mas_equalTo(28);
    }];

    // 5. 「时段分布」标题 + 24h 声波节律卡片（全页面唯一承载图形化分布的柔和面）
    _rhythmSectionView = [UIView new];
    UILabel *rhythmHeader = [UILabel new];
    rhythmHeader.text = @"时段分布";
    rhythmHeader.font = [SPTheme fontOfSize:19 weight:UIFontWeightBold];
    rhythmHeader.textColor = SPTheme.textPrimaryColor;
    [_rhythmSectionView addSubview:rhythmHeader];

    _rhythmSubtitleLabel = [UILabel new];
    _rhythmSubtitleLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightRegular];
    _rhythmSubtitleLabel.textColor = SPTheme.textSecondaryColor;
    _rhythmSubtitleLabel.numberOfLines = 2;
    [_rhythmSectionView addSubview:_rhythmSubtitleLabel];

    _rhythmCard = [UIView new];
    _rhythmCard.backgroundColor = SPTheme.elevatedColor;
    _rhythmCard.layer.cornerRadius = 18;
    _rhythmCard.layer.cornerCurve = kCACornerCurveContinuous;
    [_rhythmSectionView addSubview:_rhythmCard];

    _rhythmSkylineView = [SPAcousticRhythmView new];
    [_rhythmCard addSubview:_rhythmSkylineView];

    _rhythmDivider = [UIView new];
    _rhythmDivider.backgroundColor = SPTheme.separatorColor;
    [_rhythmCard addSubview:_rhythmDivider];

    NSArray<NSString *> *slotNames = @[@"清晨", @"午后", @"傍晚", @"深夜"];
    NSMutableArray<UIView *> *slotItems = [NSMutableArray arrayWithCapacity:4];
    NSMutableArray<UILabel *> *pctLabels = [NSMutableArray arrayWithCapacity:4];
    for (NSString *slotName in slotNames) {
        UIView *col = [UIView new];
        UILabel *nl = [UILabel new];
        nl.text = slotName;
        nl.font = [SPTheme fontOfSize:11.5 weight:UIFontWeightMedium];
        nl.textColor = SPTheme.textSecondaryColor;
        [col addSubview:nl];

        UILabel *pl = [UILabel new];
        pl.font = [SPTheme monospacedDigitFontOfSize:14.5 weight:UIFontWeightBold];
        pl.textColor = SPTheme.textPrimaryColor;
        pl.text = @"0%";
        [col addSubview:pl];
        [pctLabels addObject:pl];

        [nl mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.left.right.equalTo(col);
        }];
        [pl mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(nl.mas_bottom).offset(4);
            make.left.right.bottom.equalTo(col);
        }];
        [slotItems addObject:col];
    }
    _rhythmPercentLabels = pctLabels;

    UIStackView *periodStack = [[UIStackView alloc] initWithArrangedSubviews:slotItems];
    periodStack.axis = UILayoutConstraintAxisHorizontal;
    periodStack.distribution = UIStackViewDistributionFillEqually;
    [_rhythmCard addSubview:periodStack];

    [rhythmHeader mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.rhythmSectionView);
        make.left.equalTo(self.rhythmSectionView).offset(SPMarginHorizontal);
        make.right.equalTo(self.rhythmSectionView).offset(-SPMarginHorizontal);
    }];
    [_rhythmSubtitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(rhythmHeader.mas_bottom).offset(4);
        make.left.right.equalTo(rhythmHeader);
    }];
    [_rhythmCard mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.rhythmSubtitleLabel.mas_bottom).offset(14);
        make.left.right.equalTo(rhythmHeader);
        make.bottom.equalTo(self.rhythmSectionView);
    }];
    [_rhythmSkylineView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.rhythmCard).offset(18);
        make.left.equalTo(self.rhythmCard).offset(16);
        make.right.equalTo(self.rhythmCard).offset(-16);
        make.height.mas_equalTo(82);
    }];
    [_rhythmDivider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.rhythmSkylineView.mas_bottom).offset(14);
        make.left.equalTo(self.rhythmCard).offset(16);
        make.right.equalTo(self.rhythmCard).offset(-16);
        make.height.mas_equalTo(px);
    }];
    [periodStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.rhythmDivider.mas_bottom).offset(14);
        make.left.equalTo(self.rhythmCard).offset(16);
        make.right.equalTo(self.rhythmCard).offset(-16);
        make.bottom.equalTo(self.rhythmCard).offset(-16);
    }];

    // 6. 「常听歌手」横向开放滑带
    _artistsSectionView = [UIView new];
    UILabel *artistsHeader = [UILabel new];
    artistsHeader.text = @"常听歌手";
    artistsHeader.font = [SPTheme fontOfSize:19 weight:UIFontWeightBold];
    artistsHeader.textColor = SPTheme.textPrimaryColor;
    [_artistsSectionView addSubview:artistsHeader];

    _artistsScrollView = [UIScrollView new];
    _artistsScrollView.showsHorizontalScrollIndicator = NO;
    _artistsScrollView.alwaysBounceHorizontal = YES;
    _artistsScrollView.contentInset = UIEdgeInsetsMake(0, SPMarginHorizontal, 0, SPMarginHorizontal);
    [_artistsSectionView addSubview:_artistsScrollView];

    _artistsStack = [UIStackView new];
    _artistsStack.axis = UILayoutConstraintAxisHorizontal;
    _artistsStack.spacing = 14;
    [_artistsScrollView addSubview:_artistsStack];

    [artistsHeader mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.artistsSectionView);
        make.left.equalTo(self.artistsSectionView).offset(SPMarginHorizontal);
        make.right.equalTo(self.artistsSectionView).offset(-SPMarginHorizontal);
    }];
    [_artistsScrollView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(artistsHeader.mas_bottom).offset(14);
        make.left.right.bottom.equalTo(self.artistsSectionView);
        make.height.mas_equalTo(116);
    }];
    [_artistsStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.artistsScrollView);
        make.height.equalTo(self.artistsScrollView);
    }];

    // 7. 「单曲排行」无框原生列表
    _tracksSectionView = [UIView new];
    UILabel *tracksHeader = [UILabel new];
    tracksHeader.text = @"单曲排行";
    tracksHeader.font = [SPTheme fontOfSize:19 weight:UIFontWeightBold];
    tracksHeader.textColor = SPTheme.textPrimaryColor;
    [_tracksSectionView addSubview:tracksHeader];

    _tracksStack = [UIStackView new];
    _tracksStack.axis = UILayoutConstraintAxisVertical;
    _tracksStack.spacing = 0;
    [_tracksSectionView addSubview:_tracksStack];

    [tracksHeader mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.tracksSectionView);
        make.left.equalTo(self.tracksSectionView).offset(SPMarginHorizontal);
        make.right.equalTo(self.tracksSectionView).offset(-SPMarginHorizontal);
    }];
    [_tracksStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(tracksHeader.mas_bottom).offset(10);
        make.left.right.bottom.equalTo(self.tracksSectionView);
    }];

    UIStackView *masterStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        headerView, _tabContainer, chartSection, _statStripContainer, _rhythmSectionView, _artistsSectionView, _tracksSectionView
    ]];
    masterStack.axis = UILayoutConstraintAxisVertical;
    masterStack.spacing = 22;
    [masterStack setCustomSpacing:14 afterView:headerView];
    [masterStack setCustomSpacing:12 afterView:_tabContainer];
    [masterStack setCustomSpacing:18 afterView:chartSection];
    [_contentView addSubview:masterStack];

    [_ambientGradient mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.height.mas_equalTo(260);
    }];
    [_navBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(48);
    }];
    [backBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.navBar).offset(8);
        make.bottom.equalTo(self.navBar).offset(-2);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [_navTitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.navBar);
        make.centerY.equalTo(backBtn);
    }];
    [_moreButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.navBar).offset(-8);
        make.centerY.equalTo(backBtn);
        make.size.mas_equalTo(CGSizeMake(44, 44));
    }];
    [_navDivider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.navBar);
        make.height.mas_equalTo(px);
    }];
    [_scrollView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.navBar.mas_bottom);
        make.left.right.bottom.equalTo(self.view);
    }];
    [_contentView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.scrollView);
        make.width.equalTo(self.scrollView);
    }];
    [masterStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.contentView).offset(4);
        make.left.right.equalTo(self.contentView);
        make.bottom.equalTo(self.contentView).offset(-12);
    }];

    [self updateSurfaceAppearancesAnimated:NO];
    [self updateRangeTabStyles];
}

- (UIView *)makeStatStripColumnWithCaption:(NSString *)caption valueLabel:(UILabel * __autoreleasing *)outVal {
    UIView *col = [UIView new];
    UILabel *cap = [UILabel new];
    cap.text = caption;
    cap.font = [SPTheme fontOfSize:11.5 weight:UIFontWeightMedium];
    cap.textColor = SPTheme.textSecondaryColor;
    [col addSubview:cap];

    UILabel *val = [UILabel new];
    val.font = [SPTheme monospacedDigitFontOfSize:18 weight:UIFontWeightBold];
    val.textColor = SPTheme.textPrimaryColor;
    val.adjustsFontSizeToFitWidth = YES;
    val.minimumScaleFactor = 0.78;
    [col addSubview:val];
    if (outVal) *outVal = val;

    [cap mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(col).offset(13);
        make.left.equalTo(col).offset(12);
        make.right.lessThanOrEqualTo(col).offset(-8);
    }];
    [val mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(cap.mas_bottom).offset(6);
        make.left.equalTo(cap);
        make.right.equalTo(col).offset(-10);
        make.bottom.lessThanOrEqualTo(col).offset(-12);
    }];
    return col;
}

#pragma mark - Theme, Ambient Wash & Range Tabs

- (void)updateSurfaceAppearancesAnimated:(BOOL)animated {
    UITraitCollection *tc = [SPTheme resolvedTraitCollectionForView:self.view];
    BOOL isLight = (tc.userInterfaceStyle == UIUserInterfaceStyleLight);
    UIColor *accent = [SPTheme.accentColor resolvedColorWithTraitCollection:tc];

    UIColor *ambientColor = self.extractedAmbientColor;
    UIColor *topGlow = nil;
    if (ambientColor) {
        topGlow = isLight
            ? [ambientColor colorWithAlphaComponent:0.10]
            : [ambientColor sp_darkenedBy:0.35];
    } else {
        topGlow = isLight
            ? [accent colorWithAlphaComponent:0.08]
            : [UIColor sp_colorWithHex:0x19231D];
    }
    [self.ambientGradient setColors:@[topGlow, SPTheme.backgroundColor] animated:(animated && !UIAccessibilityIsReduceMotionEnabled())];

    if (isLight) {
        self.rhythmCard.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.rhythmCard.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.05].CGColor;
        self.rhythmCard.layer.shadowColor = UIColor.blackColor.CGColor;
        self.rhythmCard.layer.shadowOpacity = 0.055f;
        self.rhythmCard.layer.shadowRadius = 12.0;
        self.rhythmCard.layer.shadowOffset = CGSizeMake(0, 4);
    } else {
        self.rhythmCard.layer.borderWidth = 0.0;
        self.rhythmCard.layer.borderColor = NULL;
        self.rhythmCard.layer.shadowOpacity = 0.0f;
    }

    [self.rhythmSkylineView setNeedsLayout];
}

- (void)refreshAmbientColorFromSnapshot:(SPListeningStatsSnapshot *)snap {
    SPTrack *topTrack = snap.topTracks.firstObject.track;
    NSString *trackId = topTrack.identifier;
    NSString *coverURL = topTrack.coverURL;
    if (trackId.length == 0 || coverURL.length == 0) {
        self.ambientTrackId = nil;
        self.extractedAmbientColor = nil;
        [self updateSurfaceAppearancesAnimated:NO];
        return;
    }
    if ([self.ambientTrackId isEqualToString:trackId] && self.extractedAmbientColor != nil) {
        return;
    }
    self.ambientTrackId = trackId;
    NSURL *url = [NSURL URLWithString:coverURL];
    if (!url) return;

    __weak typeof(self) weakSelf = self;
    [[SDWebImageManager sharedManager] loadImageWithURL:url options:SDWebImageRetryFailed progress:nil completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        if (!image || !weakSelf) return;
        [UIImage sp_extractDominantColorForImage:image cacheKey:coverURL completion:^(UIColor *color) {
            if (!weakSelf || ![weakSelf.ambientTrackId isEqualToString:trackId]) return;
            weakSelf.extractedAmbientColor = color;
            [weakSelf updateSurfaceAppearancesAnimated:YES];
        }];
    }];
}

- (void)updateRangeTabStyles {
    for (SPScaleButton *tab in self.rangeTabButtons) {
        BOOL sel = (tab.tag == self.selectedRange);
        tab.titleLabel.font = [SPTheme fontOfSize:14.5 weight:(sel ? UIFontWeightSemibold : UIFontWeightMedium)];
        [tab setTitleColor:(sel ? SPTheme.textPrimaryColor : SPTheme.textSecondaryColor) forState:UIControlStateNormal];
    }
    if (self.activeSnapshot.totalPlayCount == 0) {
        self.pageSubtitleLabel.text = @"实时记录你的真实聆听轨迹";
    } else if (self.selectedRange == SPListeningChartRangeHourly) {
        self.pageSubtitleLabel.text = @"今日 24 小时实时分布";
    } else if (self.selectedRange == SPListeningChartRange7Days) {
        self.pageSubtitleLabel.text = @"近 7 日真实聆听记录";
    } else {
        self.pageSubtitleLabel.text = @"近 14 日真实聆听记录";
    }
}

- (void)layoutTabUnderlineAnimated:(BOOL)animated {
    NSInteger idx = (NSInteger)self.selectedRange;
    if (idx < 0 || idx >= (NSInteger)self.rangeTabButtons.count) return;
    [self.tabContainer layoutIfNeeded];
    SPScaleButton *tab = self.rangeTabButtons[idx];
    if (CGRectIsEmpty(tab.bounds)) return;

    CGRect tabFrame = [tab convertRect:tab.bounds toView:self.tabContainer];
    NSString *title = [tab titleForState:UIControlStateNormal] ?: @"";
    CGFloat textW = [title sizeWithAttributes:@{NSFontAttributeName: tab.titleLabel.font ?: [SPTheme fontOfSize:14.5 weight:UIFontWeightSemibold]}].width;
    CGFloat underlineW = MAX(24.0, textW);
    CGRect targetFrame = CGRectMake(CGRectGetMidX(tabFrame) - underlineW * 0.5,
                                    CGRectGetHeight(self.tabContainer.bounds) - 2.5,
                                    underlineW,
                                    2.5);
    if (CGRectEqualToRect(targetFrame, self.lastUnderlineTargetFrame)) {
        return;
    }
    self.lastUnderlineTargetFrame = targetFrame;

    if (animated && !UIAccessibilityIsReduceMotionEnabled() && !CGRectIsEmpty(self.tabUnderlineView.frame)) {
        [UIView animateWithDuration:0.22
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.tabUnderlineView.frame = targetFrame;
        } completion:nil];
    } else {
        self.tabUnderlineView.frame = targetFrame;
    }
}

- (void)selectRange:(SPListeningChartRange)range animated:(BOOL)animated {
    if (self.selectedRange == range) return;
    self.selectedRange = range;
    [self updateRangeTabStyles];
    [self layoutTabUnderlineAnimated:animated];
    [self applyCurrentRangePointsAnimated:animated preserveSelection:NO];
}

- (void)themeDidChange {
    self.view.backgroundColor = SPTheme.backgroundColor;
    [self updateSurfaceAppearancesAnimated:NO];
    [self updateRangeTabStyles];
    [self.curveChartView updateLayerColors];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateSurfaceAppearancesAnimated:NO];
    }
}

- (void)statsDidUpdate {
    [self reloadSnapshotAnimated:YES preserveSelection:YES];
}

#pragma mark - Data Binding

- (NSString *)rankedSignatureForSnapshot:(SPListeningStatsSnapshot *)snap {
    NSMutableString *sig = [NSMutableString string];
    for (SPListeningTopArtistItem *a in snap.topArtists) {
        [sig appendFormat:@"A:%@:%lu:%@|",
         a.artist.identifier ?: a.artist.name ?: @"",
         (unsigned long)a.playCount,
         SPStatsFormatCompactDuration(a.totalSeconds)];
    }
    for (SPListeningTopTrackItem *t in snap.topTracks) {
        [sig appendFormat:@"T:%@:%lu:%@|",
         t.track.identifier ?: @"",
         (unsigned long)t.playCount,
         SPStatsFormatCompactDuration(t.totalSeconds)];
    }
    return [sig copy];
}

- (void)reloadSnapshotAnimated:(BOOL)animated preserveSelection:(BOOL)preserveSelection {
    self.activeSnapshot = [[SPListeningStatsStore shared] currentSnapshot];
    SPListeningStatsSnapshot *snap = self.activeSnapshot;
    BOOL hasData = (snap.totalPlayCount > 0 || snap.totalMinutes > 0.01);

    self.moreButton.hidden = !hasData;
    [self updateRangeTabStyles];
    [self refreshAmbientColorFromSnapshot:snap];

    self.statMinutesValueLabel.text = SPStatsFormatSpacedDuration(snap.totalMinutes * 60.0);
    self.statPlaysValueLabel.text = [NSString stringWithFormat:@"%lu 次", (unsigned long)snap.totalPlayCount];
    self.statPeriodValueLabel.text = snap.personaTitle ?: @"暂无记录";

    self.rhythmSubtitleLabel.text = snap.personaSummary;
    [self.rhythmSkylineView configureWithHourlyMinutes:snap.hourlyMinutes24
                                           hourlyPlays:snap.hourlyPlays24
                                              peakHour:snap.peakHour];

    UIColor *accent = SPTheme.accentColor;
    for (NSUInteger i = 0; i < MIN((NSUInteger)4, snap.periodShares.count); i++) {
        NSInteger pct = hasData ? (NSInteger)llround(snap.periodShares[i].doubleValue * 100.0) : 0;
        UILabel *lbl = self.rhythmPercentLabels[i];
        lbl.text = [NSString stringWithFormat:@"%ld%%", (long)pct];
        lbl.textColor = (hasData && (NSInteger)i == snap.dominantPeriodIndex) ? accent : SPTheme.textPrimaryColor;
    }

    [self applyCurrentRangePointsAnimated:animated preserveSelection:preserveSelection];
    NSString *sig = [self rankedSignatureForSnapshot:snap];
    if (![sig isEqualToString:self.lastRankedSignature]) {
        self.lastRankedSignature = sig;
        [self rebuildTopArtistsAndTracks];
    }
}

- (NSArray<SPListeningChartPoint *> *)pointsForRange:(SPListeningChartRange)range {
    if (range == SPListeningChartRangeHourly) return self.activeSnapshot.pointsHourly ?: @[];
    if (range == SPListeningChartRange14Days) return self.activeSnapshot.points14Days ?: @[];
    return self.activeSnapshot.points7Days ?: @[];
}

- (void)applyCurrentRangePointsAnimated:(BOOL)animated preserveSelection:(BOOL)preserveSelection {
    NSArray<SPListeningChartPoint *> *pts = [self pointsForRange:self.selectedRange];
    [self.curveChartView setPoints:pts animated:animated preserveSelection:preserveSelection];
    if (self.curveChartView.selectedIndex >= 0 && self.curveChartView.selectedIndex < (NSInteger)pts.count) {
        [self updateFocusReadoutWithPoint:pts[self.curveChartView.selectedIndex]];
    }
}

- (void)updateFocusReadoutWithPoint:(SPListeningChartPoint *)point {
    NSString *valueStr = @"0";
    NSString *unitStr = @" 分钟";
    if (point) {
        NSTimeInterval seconds = point.minutes * 60.0;
        if (seconds <= 0.5 && point.playCount > 0) {
            valueStr = @"<1";
            unitStr = @" 分钟";
        } else if (seconds > 0.5 && seconds < 60.0) {
            valueStr = [NSString stringWithFormat:@"%ld", (long)MAX(1, llround(seconds))];
            unitStr = @" 秒";
        } else if (seconds >= 60.0 && seconds < 7200.0) {
            valueStr = [NSString stringWithFormat:@"%ld", (long)MAX(1, llround(seconds / 60.0))];
            unitStr = @" 分钟";
        } else if (seconds >= 7200.0) {
            valueStr = [NSString stringWithFormat:@"%.1f", seconds / 3600.0];
            unitStr = @" 小时";
        }
    }

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:valueStr attributes:@{
        NSFontAttributeName: [SPTheme monospacedDigitFontOfSize:40 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: SPTheme.textPrimaryColor,
    }];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:unitStr attributes:@{
        NSFontAttributeName: [SPTheme fontOfSize:15 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: SPTheme.textSecondaryColor,
    }]];
    self.focusHeroLabel.attributedText = attr;

    if (point) {
        self.focusDetailLabel.text = [NSString stringWithFormat:@"%@ · 播放 %lu 次",
                                      point.detailTitle ?: @"", (unsigned long)point.playCount];
    } else {
        self.focusDetailLabel.text = @"暂无播放记录";
    }
}

- (void)rebuildTopArtistsAndTracks {
    for (UIView *v in self.artistsStack.arrangedSubviews) {
        [self.artistsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (UIView *v in self.tracksStack.arrangedSubviews) {
        [self.tracksStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSArray<SPListeningTopArtistItem *> *artists = self.activeSnapshot.topArtists;
    self.artistsSectionView.hidden = (artists.count == 0);
    for (NSUInteger i = 0; i < artists.count; i++) {
        SPListeningTopArtistItem *item = artists[i];
        SPScaleButton *col = [SPScaleButton buttonWithType:UIButtonTypeCustom];
        col.tag = (NSInteger)i;
        [col addTarget:self action:@selector(artistItemTapped:) forControlEvents:UIControlEventTouchUpInside];

        UIImageView *avatar = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 68, 68)];
        avatar.contentMode = UIViewContentModeScaleAspectFill;
        avatar.clipsToBounds = YES;
        avatar.layer.cornerRadius = 34;
        avatar.layer.cornerCurve = kCACornerCurveCircular;
        avatar.userInteractionEnabled = NO;
        [avatar sp_setCoverWithItem:item.artist];
        if (item.artist.coverURL.length == 0 && item.artist.name.length > 0) {
            NSRange seq = [item.artist.name rangeOfComposedCharacterSequenceAtIndex:0];
            UILabel *initialLbl = [UILabel new];
            initialLbl.text = [item.artist.name substringWithRange:seq].uppercaseString;
            initialLbl.font = [SPTheme fontOfSize:22 weight:UIFontWeightBold];
            initialLbl.textColor = SPTheme.textSecondaryColor;
            initialLbl.textAlignment = NSTextAlignmentCenter;
            [avatar addSubview:initialLbl];
            [initialLbl mas_makeConstraints:^(MASConstraintMaker *make) {
                make.center.equalTo(avatar);
            }];
        }
        [col addSubview:avatar];

        UILabel *nameLbl = [UILabel new];
        nameLbl.text = item.artist.name;
        nameLbl.font = [SPTheme fontOfSize:13 weight:UIFontWeightSemibold];
        nameLbl.textColor = SPTheme.textPrimaryColor;
        nameLbl.textAlignment = NSTextAlignmentCenter;
        nameLbl.userInteractionEnabled = NO;
        [col addSubview:nameLbl];

        UILabel *subLbl = [UILabel new];
        subLbl.text = [NSString stringWithFormat:@"%lu次 · %@",
                       (unsigned long)item.playCount,
                       SPStatsFormatCompactDuration(item.totalSeconds)];
        subLbl.font = [SPTheme monospacedDigitFontOfSize:11 weight:UIFontWeightMedium];
        subLbl.textColor = SPTheme.textSecondaryColor;
        subLbl.textAlignment = NSTextAlignmentCenter;
        subLbl.userInteractionEnabled = NO;
        [col addSubview:subLbl];

        [col mas_makeConstraints:^(MASConstraintMaker *make) {
            make.width.mas_equalTo(84);
        }];
        [avatar mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.centerX.equalTo(col);
            make.size.mas_equalTo(CGSizeMake(68, 68));
        }];
        [nameLbl mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(avatar.mas_bottom).offset(8);
            make.left.right.equalTo(col);
        }];
        [subLbl mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(nameLbl.mas_bottom).offset(2);
            make.left.right.equalTo(col);
            make.bottom.lessThanOrEqualTo(col);
        }];
        [self.artistsStack addArrangedSubview:col];
    }

    NSArray<SPListeningTopTrackItem *> *tracks = self.activeSnapshot.topTracks;
    if (tracks.count == 0) {
        UIView *emptyWrap = [UIView new];
        UIImageView *noteIcon = [[UIImageView alloc] initWithImage:[SPTheme symbol:@"music.note" size:28 weight:UIImageSymbolWeightLight]];
        noteIcon.tintColor = SPTheme.textTertiaryColor;
        [emptyWrap addSubview:noteIcon];

        UILabel *emptyTitle = [UILabel new];
        emptyTitle.text = @"还没有听歌记录";
        emptyTitle.font = [SPTheme fontOfSize:15 weight:UIFontWeightSemibold];
        emptyTitle.textColor = SPTheme.textPrimaryColor;
        emptyTitle.textAlignment = NSTextAlignmentCenter;
        [emptyWrap addSubview:emptyTitle];

        UILabel *emptySub = [UILabel new];
        emptySub.text = @"播放喜欢的歌曲后，这里会实时记录你的真实聆听轨迹";
        emptySub.font = [SPTheme fontOfSize:13 weight:UIFontWeightRegular];
        emptySub.textColor = SPTheme.textSecondaryColor;
        emptySub.textAlignment = NSTextAlignmentCenter;
        emptySub.numberOfLines = 0;
        [emptyWrap addSubview:emptySub];

        SPScaleButton *goHomeBtn = [SPScaleButton buttonWithType:UIButtonTypeCustom];
        goHomeBtn.backgroundColor = SPTheme.accentColor;
        goHomeBtn.layer.cornerRadius = 19;
        goHomeBtn.layer.cornerCurve = kCACornerCurveContinuous;
        [goHomeBtn setTitle:@"去首页发现音乐" forState:UIControlStateNormal];
        goHomeBtn.titleLabel.font = [SPTheme fontOfSize:13.5 weight:UIFontWeightBold];
        UIColor *fg = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return (tc.userInterfaceStyle == UIUserInterfaceStyleLight) ? UIColor.whiteColor : [UIColor sp_colorWithHex:0x0B0B0C];
        }];
        [goHomeBtn setTitleColor:fg forState:UIControlStateNormal];
        [goHomeBtn addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
        [emptyWrap addSubview:goHomeBtn];

        [noteIcon mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(emptyWrap).offset(18);
            make.centerX.equalTo(emptyWrap);
        }];
        [emptyTitle mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(noteIcon.mas_bottom).offset(10);
            make.left.equalTo(emptyWrap).offset(24);
            make.right.equalTo(emptyWrap).offset(-24);
        }];
        [emptySub mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(emptyTitle.mas_bottom).offset(4);
            make.left.right.equalTo(emptyTitle);
        }];
        [goHomeBtn mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(emptySub.mas_bottom).offset(16);
            make.centerX.equalTo(emptyWrap);
            make.height.mas_equalTo(38);
            make.width.mas_equalTo(148);
            make.bottom.equalTo(emptyWrap).offset(-14);
        }];
        [self.tracksStack addArrangedSubview:emptyWrap];
        return;
    }

    NSUInteger maxPlays = 1;
    for (SPListeningTopTrackItem *item in tracks) {
        if (item.playCount > maxPlays) maxPlays = item.playCount;
    }

    CGFloat px = 1.0 / UIScreen.mainScreen.scale;
    for (NSUInteger i = 0; i < tracks.count; i++) {
        SPListeningTopTrackItem *item = tracks[i];
        SPHighlightRowButton *rowBtn = [SPHighlightRowButton buttonWithType:UIButtonTypeCustom];
        rowBtn.isStatic = YES;
        rowBtn.tag = (NSInteger)i;
        [rowBtn addTarget:self action:@selector(trackRowTapped:) forControlEvents:UIControlEventTouchUpInside];

        UILabel *rankLbl = [UILabel new];
        rankLbl.text = [NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)];
        rankLbl.font = [SPTheme monospacedDigitFontOfSize:15 weight:UIFontWeightBold];
        rankLbl.textColor = (i == 0) ? SPTheme.accentColor : SPTheme.textTertiaryColor;
        rankLbl.textAlignment = NSTextAlignmentCenter;
        rankLbl.userInteractionEnabled = NO;
        [rowBtn addSubview:rankLbl];

        UIImageView *cover = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 46, 46)];
        cover.contentMode = UIViewContentModeScaleAspectFill;
        cover.clipsToBounds = YES;
        cover.layer.cornerRadius = 6;
        cover.userInteractionEnabled = NO;
        [cover sp_setCoverWithItem:item.track];
        [rowBtn addSubview:cover];

        UILabel *tName = [UILabel new];
        tName.text = item.track.name;
        tName.font = [SPTheme fontOfSize:15 weight:UIFontWeightSemibold];
        tName.textColor = SPTheme.textPrimaryColor;
        tName.userInteractionEnabled = NO;
        [rowBtn addSubview:tName];

        UILabel *tSub = [UILabel new];
        tSub.text = [item.track artistNames];
        tSub.font = [SPTheme fontOfSize:12.5 weight:UIFontWeightRegular];
        tSub.textColor = SPTheme.textSecondaryColor;
        tSub.userInteractionEnabled = NO;
        [rowBtn addSubview:tSub];

        UIView *barTrack = [UIView new];
        barTrack.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return [SPTheme.textPrimaryColor colorWithAlphaComponent:(tc.userInterfaceStyle == UIUserInterfaceStyleLight ? 0.06 : 0.07)];
        }];
        barTrack.layer.cornerRadius = 1.0;
        barTrack.userInteractionEnabled = NO;
        [rowBtn addSubview:barTrack];

        CGFloat ratio = MIN(1.0, MAX(0.08, (CGFloat)item.playCount / (CGFloat)maxPlays));
        UIView *barFill = [UIView new];
        barFill.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            if (i == 0) {
                return [[SPTheme.accentColor resolvedColorWithTraitCollection:tc] colorWithAlphaComponent:0.75];
            }
            return [SPTheme.textPrimaryColor colorWithAlphaComponent:(tc.userInterfaceStyle == UIUserInterfaceStyleLight ? 0.22 : 0.26)];
        }];
        barFill.layer.cornerRadius = 1.0;
        barFill.userInteractionEnabled = NO;
        [barTrack addSubview:barFill];

        UILabel *countLbl = [UILabel new];
        countLbl.text = [NSString stringWithFormat:@"%lu 次", (unsigned long)item.playCount];
        countLbl.font = [SPTheme monospacedDigitFontOfSize:13.5 weight:UIFontWeightSemibold];
        countLbl.textColor = SPTheme.textPrimaryColor;
        countLbl.textAlignment = NSTextAlignmentRight;
        countLbl.userInteractionEnabled = NO;
        [countLbl setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [countLbl setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [rowBtn addSubview:countLbl];

        UILabel *durLbl = [UILabel new];
        durLbl.text = SPStatsFormatCompactDuration(item.totalSeconds);
        durLbl.font = [SPTheme monospacedDigitFontOfSize:11 weight:UIFontWeightRegular];
        durLbl.textColor = SPTheme.textTertiaryColor;
        durLbl.textAlignment = NSTextAlignmentRight;
        durLbl.userInteractionEnabled = NO;
        [durLbl setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [durLbl setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [rowBtn addSubview:durLbl];

        [rowBtn mas_makeConstraints:^(MASConstraintMaker *make) {
            make.height.mas_equalTo(66);
        }];
        [rankLbl mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(rowBtn).offset(SPMarginHorizontal);
            make.centerY.equalTo(rowBtn);
            make.width.mas_equalTo(18);
        }];
        [cover mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(rankLbl.mas_right).offset(10);
            make.centerY.equalTo(rowBtn);
            make.size.mas_equalTo(CGSizeMake(46, 46));
        }];
        [countLbl mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(rowBtn).offset(-SPMarginHorizontal);
            make.bottom.equalTo(rowBtn.mas_centerY).offset(-1);
        }];
        [durLbl mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(countLbl);
            make.top.equalTo(rowBtn.mas_centerY).offset(2);
        }];
        [tName mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(cover.mas_right).offset(12);
            make.right.lessThanOrEqualTo(countLbl.mas_left).offset(-12);
            make.top.equalTo(cover).offset(1);
        }];
        [tSub mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(tName);
            make.right.lessThanOrEqualTo(durLbl.mas_left).offset(-12);
            make.top.equalTo(tName.mas_bottom).offset(2);
        }];
        [barTrack mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(tName);
            make.right.equalTo(countLbl.mas_left).offset(-16);
            make.bottom.equalTo(cover);
            make.height.mas_equalTo(2);
        }];
        [barFill mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.bottom.left.equalTo(barTrack);
            make.width.equalTo(barTrack).multipliedBy(ratio);
        }];

        if (i + 1 < tracks.count) {
            UIView *sep = [UIView new];
            sep.backgroundColor = SPTheme.separatorColor;
            sep.userInteractionEnabled = NO;
            [rowBtn addSubview:sep];
            [sep mas_makeConstraints:^(MASConstraintMaker *make) {
                make.left.equalTo(tName);
                make.right.equalTo(rowBtn).offset(-SPMarginHorizontal);
                make.bottom.equalTo(rowBtn);
                make.height.mas_equalTo(px);
            }];
        }

        [self.tracksStack addArrangedSubview:rowBtn];
    }
}

#pragma mark - Actions & Scroll

- (void)backTapped {
    [SPHaptics light];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)moreTapped {
    [SPHaptics medium];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"听歌统计"
                                                                   message:@"仅清除当前账号本地累计的听歌统计数据，不影响「最近收听」列表"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;
    [sheet addAction:[UIAlertAction actionWithTitle:@"清空本账号听歌统计"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [[SPListeningStatsStore shared] clearCurrentUserStats];
        [SPToast showMessage:@"已清空当前账号听歌统计"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:self.moreButton presentingVC:self];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)rangeButtonTapped:(SPScaleButton *)sender {
    if (sender.tag == self.selectedRange) return;
    [SPHaptics selection];
    [self selectRange:(SPListeningChartRange)sender.tag animated:YES];
}

- (void)artistItemTapped:(SPScaleButton *)sender {
    NSUInteger idx = (NSUInteger)sender.tag;
    if (idx >= self.activeSnapshot.topArtists.count) return;
    [SPHaptics light];
    SPArtist *artist = self.activeSnapshot.topArtists[idx].artist;
    if (artist.identifier.length == 0) {
        [SPToast showMessage:artist.name ?: @""];
        return;
    }
    SPDetailViewController *detail = [[SPDetailViewController alloc] initWithMediaItem:artist];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)trackRowTapped:(SPScaleButton *)sender {
    NSUInteger idx = (NSUInteger)sender.tag;
    if (idx >= self.activeSnapshot.topTracks.count) return;
    [SPHaptics light];
    NSMutableArray<SPTrack *> *tracks = [NSMutableArray array];
    for (SPListeningTopTrackItem *item in self.activeSnapshot.topTracks) {
        if (item.track) [tracks addObject:item.track];
    }
    if (idx < tracks.count) {
        [[SPPlayerService shared] playTracks:tracks startIndex:idx contextTitle:@"常听排行"];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offsetY = MAX(0.0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top);
    CGFloat navReveal = MIN(MAX((offsetY - 18.0) / 26.0, 0.0), 1.0);
    self.navTitleLabel.alpha = navReveal;
    self.navDivider.alpha = navReveal;
}

@end
