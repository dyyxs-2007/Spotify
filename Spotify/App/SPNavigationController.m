//
//  SPNavigationController.m
//  Spotify
//

#import "SPNavigationController.h"

@interface SPNavigationController () <UIGestureRecognizerDelegate>
@end

@implementation SPNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationBarHidden = YES;
    self.view.backgroundColor = SPTheme.backgroundColor;
    // 隐藏导航栏后系统会禁用侧滑返回，这里接管 delegate 恢复它
    self.interactivePopGestureRecognizer.delegate = self;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.interactivePopGestureRecognizer) {
        return self.viewControllers.count > 1;
    }
    return YES;
}

- (UIViewController *)childViewControllerForStatusBarStyle { return self.topViewController; }

@end
