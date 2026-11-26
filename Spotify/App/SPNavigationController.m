//
//  SPNavigationController.m
//  Spotify
//

#import "SPNavigationController.h"

@interface SPNavigationController () <UIGestureRecognizerDelegate, UINavigationControllerDelegate>
@property (nonatomic, assign) BOOL isTransitioning;
@end

@implementation SPNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationBarHidden = YES;
    self.view.backgroundColor = SPTheme.backgroundColor;
    self.delegate = self;
    // 隐藏导航栏后系统会禁用侧滑返回，这里接管 delegate 恢复它
    self.interactivePopGestureRecognizer.delegate = self;
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (animated) {
        self.isTransitioning = YES;
    }
    [super pushViewController:viewController animated:animated];
}

- (void)navigationController:(UINavigationController *)navigationController
       didShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated {
    self.isTransitioning = NO;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.interactivePopGestureRecognizer) {
        return self.viewControllers.count > 1 && !self.isTransitioning && self.transitionCoordinator == nil;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.interactivePopGestureRecognizer) {
        return YES;
    }
    return NO;
}

- (UIViewController *)childViewControllerForStatusBarStyle { return self.topViewController; }

@end
