//
//  SPNowPlayingTransition.m
//  Spotify
//

#import "SPNowPlayingTransition.h"
#import "SPNowPlayingViewController.h"

@interface SPNowPlayingAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic, assign) BOOL presenting;
@property (nonatomic, weak) UIView *miniPlayerView;
@property (nonatomic, weak, nullable) UIView *backdropDimView;
@property (nonatomic, copy) UIView *(^sourceCoverProvider)(void);
@property (nonatomic, copy, nullable) void (^backdropCreatedHandler)(UIView *backdrop);
@end

@implementation SPNowPlayingAnimator

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext {
    return self.presenting ? 0.42 : 0.36;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIView *container = transitionContext.containerView;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();

    if (self.presenting) {
        [self.backdropDimView removeFromSuperview];
        UIView *dimView = [[UIView alloc] initWithFrame:container.bounds];
        dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        dimView.backgroundColor = UIColor.blackColor;
        dimView.alpha = 0.0;
        dimView.userInteractionEnabled = NO;
        [container addSubview:dimView];
        if (self.backdropCreatedHandler) {
            self.backdropCreatedHandler(dimView);
        }

        SPNowPlayingViewController *toVC = (SPNowPlayingViewController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
        toVC.view.frame = [transitionContext finalFrameForViewController:toVC];
        [container addSubview:toVC.view];
        [toVC.view layoutIfNeeded];

        UIView *sourceCover = self.sourceCoverProvider ? self.sourceCoverProvider() : nil;
        UIImageView *targetCover = toVC.coverView;
        UIView *targetCoverHost = toVC.coverShadowContainer ?: targetCover;
        UIImage *coverImage = [sourceCover isKindOfClass:UIImageView.class] ? ((UIImageView *)sourceCover).image : targetCover.image;

        BOOL targetCoverReady = targetCover && !targetCover.isHidden && !targetCoverHost.isHidden && !targetCoverHost.superview.isHidden
            && !CGRectIsEmpty(targetCover.bounds) && targetCover.image != nil;
        if (reduceMotion || !sourceCover || CGRectIsEmpty(sourceCover.bounds) || !targetCoverReady || !coverImage) {
            toVC.view.alpha = 0;
            toVC.view.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, 44);
            [UIView animateWithDuration:reduceMotion ? 0.18 : 0.28
                                  delay:0
                 usingSpringWithDamping:reduceMotion ? 1.0 : 0.92
                  initialSpringVelocity:reduceMotion ? 0.0 : 0.1
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                dimView.alpha = 0.48;
                toVC.view.alpha = 1;
                toVC.view.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished) {
                [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
            }];
            return;
        }

        CGRect sourceFrame = [sourceCover convertRect:sourceCover.bounds toView:container];
        CGRect targetFrame = [targetCover convertRect:targetCover.bounds toView:container];

        UIImageView *floatingCover = [self floatingCoverWithImage:coverImage frame:sourceFrame cornerRadius:4];
        [container addSubview:floatingCover];

        sourceCover.hidden = YES;
        targetCoverHost.hidden = YES;
        toVC.view.alpha = 0;
        toVC.view.transform = CGAffineTransformMakeTranslation(0, 40);

        [UIView animateWithDuration:[self transitionDuration:transitionContext]
                              delay:0
             usingSpringWithDamping:0.88
              initialSpringVelocity:0.2
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            dimView.alpha = 0.48;
            toVC.view.alpha = 1;
            toVC.view.transform = CGAffineTransformIdentity;
            floatingCover.frame = targetFrame;
            floatingCover.layer.cornerRadius = 8;
        } completion:^(BOOL finished) {
            sourceCover.hidden = NO;
            targetCoverHost.hidden = NO;
            [floatingCover removeFromSuperview];
            [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
        }];
    } else {
        SPNowPlayingViewController *fromVC = (SPNowPlayingViewController *)[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
        UIView *sourceCover = self.sourceCoverProvider ? self.sourceCoverProvider() : nil;
        UIImageView *fromCover = fromVC.coverView;
        UIView *fromCoverHost = fromVC.coverShadowContainer ?: fromCover;
        UIView *dimView = self.backdropDimView;

        CGRect coverRectInContainer = (fromCover != nil)
            ? [fromCover convertRect:fromCover.bounds toView:container]
            : CGRectZero;
        BOOL fromCoverReady = fromCover && !fromCover.isHidden && !fromCoverHost.isHidden && !fromCoverHost.superview.isHidden
            && fromCoverHost.alpha > 0.75
            && !CGRectIsEmpty(fromCover.bounds) && fromCover.image != nil
            && CGRectIntersectsRect(container.bounds, coverRectInContainer);
        if (reduceMotion || !sourceCover || CGRectIsEmpty(sourceCover.bounds) || !fromCoverReady) {
            CGAffineTransform currentTransform = fromVC.view.transform;
            CGAffineTransform endTransform = reduceMotion
                ? currentTransform
                : CGAffineTransformConcat(CGAffineTransformScale(currentTransform, 0.94, 0.94),
                                          CGAffineTransformMakeTranslation(0, 88));
            if (!reduceMotion) {
                fromVC.view.clipsToBounds = YES;
                fromVC.view.layer.cornerCurve = kCACornerCurveContinuous;
            }
            [UIView animateWithDuration:reduceMotion ? 0.18 : 0.24
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                dimView.alpha = 0.0;
                fromVC.view.alpha = 0.0;
                fromVC.view.transform = endTransform;
                if (!reduceMotion) {
                    fromVC.view.layer.cornerRadius = 32.0;
                }
            } completion:^(BOOL finished) {
                fromVC.view.transform = CGAffineTransformIdentity;
                fromVC.view.layer.cornerRadius = 0.0;
                fromVC.view.layer.borderWidth = 0.0;
                fromVC.view.clipsToBounds = NO;
                [dimView removeFromSuperview];
                [fromVC.view removeFromSuperview];
                [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
            }];
            return;
        }

        // 先读取实时封面坐标（自动承接手势缩放/位移后的屏幕位置）
        CGRect currentFrame = [fromCover convertRect:fromCover.bounds toView:container];
        CGRect destFrame = [sourceCover convertRect:sourceCover.bounds toView:container];

        UIImageView *floatingCover = [self floatingCoverWithImage:fromCover.image frame:currentFrame cornerRadius:8];
        [container addSubview:floatingCover];

        fromCoverHost.hidden = YES;
        sourceCover.hidden = YES;
        fromVC.view.clipsToBounds = YES;
        fromVC.view.layer.cornerCurve = kCACornerCurveContinuous;

        CGFloat springVel = MIN(MAX(fromVC.dismissVelocityY / 900.0, 0.20), 1.35);
        CGAffineTransform tuckTransform = CGAffineTransformConcat(CGAffineTransformScale(fromVC.view.transform, 0.92, 0.92),
                                                                  CGAffineTransformMakeTranslation(0, 72));

        // 第 1 层：实体卡面向下方微缩收纳并清理背板暗度（快速柔和 ease-out，绝不在全屏下直愣愣半透明渐变）
        [UIView animateWithDuration:0.20
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            dimView.alpha = 0.0;
            fromVC.view.transform = tuckTransform;
            fromVC.view.layer.cornerRadius = 32.0;
            fromVC.view.alpha = 0.0;
        } completion:nil];

        // 第 2 层：独立实体专辑封面沿弹簧轨迹飞回左下角迷你播放条（衔接手势释放初速度）
        [UIView animateWithDuration:[self transitionDuration:transitionContext]
                              delay:0
             usingSpringWithDamping:0.88
              initialSpringVelocity:springVel
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            floatingCover.frame = destFrame;
            floatingCover.layer.cornerRadius = 4.0;
        } completion:^(BOOL finished) {
            sourceCover.hidden = NO;
            fromCoverHost.hidden = NO;
            fromVC.view.transform = CGAffineTransformIdentity;
            fromVC.view.layer.cornerRadius = 0.0;
            fromVC.view.layer.borderWidth = 0.0;
            fromVC.view.clipsToBounds = NO;
            [floatingCover removeFromSuperview];
            [dimView removeFromSuperview];
            [fromVC.view removeFromSuperview];
            [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
        }];
    }
}

- (UIImageView *)floatingCoverWithImage:(UIImage *)image frame:(CGRect)frame cornerRadius:(CGFloat)radius {
    UIImageView *iv = [[UIImageView alloc] initWithFrame:frame];
    iv.image = image;
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.clipsToBounds = YES;
    iv.layer.cornerRadius = radius;
    iv.layer.cornerCurve = kCACornerCurveContinuous;
    iv.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    iv.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    return iv;
}

@end

@interface SPNowPlayingTransition ()
@property (nonatomic, weak) UIView *miniPlayerView;
@property (nonatomic, weak, nullable) UIView *backdropDimView;
@property (nonatomic, copy) UIView *(^sourceCoverProvider)(void);
@end

@implementation SPNowPlayingTransition

- (instancetype)initWithMiniPlayerView:(UIView *)miniPlayerView
                   sourceCoverProvider:(UIView *(^)(void))sourceCoverProvider {
    if (self = [super init]) {
        _miniPlayerView = miniPlayerView;
        _sourceCoverProvider = [sourceCoverProvider copy];
    }
    return self;
}

- (void)updateBackdropForDismissProgress:(CGFloat)progress {
    CGFloat clamped = MIN(MAX(progress, 0.0), 1.0);
    self.backdropDimView.alpha = 0.48 * (1.0 - clamped);
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source {
    SPNowPlayingAnimator *anim = [SPNowPlayingAnimator new];
    anim.presenting = YES;
    anim.miniPlayerView = self.miniPlayerView;
    anim.backdropDimView = self.backdropDimView;
    anim.sourceCoverProvider = self.sourceCoverProvider;
    __weak typeof(self) weakSelf = self;
    anim.backdropCreatedHandler = ^(UIView *backdrop) {
        weakSelf.backdropDimView = backdrop;
    };
    return anim;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    SPNowPlayingAnimator *anim = [SPNowPlayingAnimator new];
    anim.presenting = NO;
    anim.miniPlayerView = self.miniPlayerView;
    anim.backdropDimView = self.backdropDimView;
    anim.sourceCoverProvider = self.sourceCoverProvider;
    return anim;
}

@end
