//
//  SPNowPlayingTransition.m
//  Spotify
//

#import "SPNowPlayingTransition.h"
#import "SPNowPlayingViewController.h"

@interface SPNowPlayingAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic, assign) BOOL presenting;
@property (nonatomic, weak) UIView *miniPlayerView;
@property (nonatomic, copy) UIView *(^sourceCoverProvider)(void);
@end

@implementation SPNowPlayingAnimator

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext {
    return self.presenting ? 0.42 : 0.32;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIView *container = transitionContext.containerView;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();

    if (self.presenting) {
        SPNowPlayingViewController *toVC = (SPNowPlayingViewController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
        toVC.view.frame = [transitionContext finalFrameForViewController:toVC];
        [container addSubview:toVC.view];
        [toVC.view layoutIfNeeded];

        UIView *sourceCover = self.sourceCoverProvider ? self.sourceCoverProvider() : nil;
        UIImageView *targetCover = toVC.coverView;
        UIImage *coverImage = [sourceCover isKindOfClass:UIImageView.class] ? ((UIImageView *)sourceCover).image : targetCover.image;

        if (reduceMotion || !sourceCover || CGRectIsEmpty(sourceCover.bounds)) {
            toVC.view.alpha = 0;
            [UIView animateWithDuration:0.22 animations:^{
                toVC.view.alpha = 1;
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
        targetCover.hidden = YES;
        toVC.view.alpha = 0;
        toVC.view.transform = CGAffineTransformMakeTranslation(0, 40);

        [UIView animateWithDuration:[self transitionDuration:transitionContext]
                              delay:0
             usingSpringWithDamping:0.88
              initialSpringVelocity:0.2
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            toVC.view.alpha = 1;
            toVC.view.transform = CGAffineTransformIdentity;
            floatingCover.frame = targetFrame;
            floatingCover.layer.cornerRadius = 8;
        } completion:^(BOOL finished) {
            sourceCover.hidden = NO;
            targetCover.hidden = NO;
            [floatingCover removeFromSuperview];
            [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
        }];
    } else {
        SPNowPlayingViewController *fromVC = (SPNowPlayingViewController *)[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
        UIView *sourceCover = self.sourceCoverProvider ? self.sourceCoverProvider() : nil;
        UIImageView *fromCover = fromVC.coverView;

        if (reduceMotion || !sourceCover || CGRectIsEmpty(sourceCover.bounds)) {
            [UIView animateWithDuration:0.20 animations:^{
                fromVC.view.alpha = 0;
            } completion:^(BOOL finished) {
                [fromVC.view removeFromSuperview];
                [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
            }];
            return;
        }

        CGRect currentFrame = [fromCover convertRect:fromCover.bounds toView:container];
        CGRect destFrame = [sourceCover convertRect:sourceCover.bounds toView:container];

        UIImageView *floatingCover = [self floatingCoverWithImage:fromCover.image frame:currentFrame cornerRadius:8];
        [container addSubview:floatingCover];

        fromCover.hidden = YES;
        sourceCover.hidden = YES;

        [UIView animateWithDuration:[self transitionDuration:transitionContext]
                              delay:0
             usingSpringWithDamping:0.92
              initialSpringVelocity:0.1
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            fromVC.view.alpha = 0;
            floatingCover.frame = destFrame;
            floatingCover.layer.cornerRadius = 4;
        } completion:^(BOOL finished) {
            sourceCover.hidden = NO;
            fromCover.hidden = NO;
            [floatingCover removeFromSuperview];
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

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source {
    SPNowPlayingAnimator *anim = [SPNowPlayingAnimator new];
    anim.presenting = YES;
    anim.miniPlayerView = self.miniPlayerView;
    anim.sourceCoverProvider = self.sourceCoverProvider;
    return anim;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    SPNowPlayingAnimator *anim = [SPNowPlayingAnimator new];
    anim.presenting = NO;
    anim.miniPlayerView = self.miniPlayerView;
    anim.sourceCoverProvider = self.sourceCoverProvider;
    return anim;
}

@end
