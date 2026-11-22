//
//  SceneDelegate.m
//  Spotify
//

#import "SceneDelegate.h"
#import "SPRootViewController.h"
#import "SPNavigationController.h"
#import "SPOnboardingViewController.h"
#import "SPAuthWelcomeViewController.h"
#import "SPAuthService.h"
#import "SPSelfTestRunner.h"

static NSString * const SPOnboardingCompletedDefaultsKey = @"sp_onboarding_completed_v1";
static NSString * const SPGuestModeEnteredDefaultsKey = @"sp_guest_mode_entered_v1";

@implementation SceneDelegate

+ (instancetype)shared {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if ([scene.delegate isKindOfClass:SceneDelegate.class]) {
            return (SceneDelegate *)scene.delegate;
        }
    }
    return nil;
}

+ (BOOL)hasCompletedOnboarding {
    return [[NSUserDefaults standardUserDefaults] boolForKey:SPOnboardingCompletedDefaultsKey];
}

+ (void)setHasCompletedOnboarding:(BOOL)completed {
    [[NSUserDefaults standardUserDefaults] setBool:completed forKey:SPOnboardingCompletedDefaultsKey];
}

+ (BOOL)hasEnteredGuestMode {
    return [[NSUserDefaults standardUserDefaults] boolForKey:SPGuestModeEnteredDefaultsKey];
}

+ (void)setHasEnteredGuestMode:(BOOL)entered {
    [[NSUserDefaults standardUserDefaults] setBool:entered forKey:SPGuestModeEnteredDefaultsKey];
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.backgroundColor = SPTheme.backgroundColor;
    self.window.tintColor = SPTheme.textPrimaryColor;
    self.window.overrideUserInterfaceStyle = SPTheme.interfaceStyle;

    BOOL isSelfTest = [NSProcessInfo.processInfo.arguments containsObject:@"-SPSelfTest"];
    UIViewController *initialRoot = nil;

    if (isSelfTest) {
        initialRoot = [SPRootViewController new];
    } else if (![SceneDelegate hasCompletedOnboarding]) {
        initialRoot = [[SPNavigationController alloc] initWithRootViewController:[SPOnboardingViewController new]];
    } else if (![SPAuthService shared].isLoggedIn && ![SceneDelegate hasEnteredGuestMode]) {
        SPAuthWelcomeViewController *welcome = [[SPAuthWelcomeViewController alloc] initWithContext:SPAuthPresentationContextGate];
        initialRoot = [[SPNavigationController alloc] initWithRootViewController:welcome];
    } else {
        initialRoot = [SPRootViewController new];
    }

    self.window.rootViewController = initialRoot;
    [self.window makeKeyAndVisible];

    if (isSelfTest && [initialRoot isKindOfClass:SPRootViewController.class]) {
        SPRootViewController *root = (SPRootViewController *)initialRoot;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [SPSelfTestRunner runWithRootViewController:root completion:nil];
        });
    }
}

#pragma mark - Root Transitions

- (void)transitionToMainAppAnimated:(BOOL)animated {
    [self transitionToRootViewController:[SPRootViewController new] animated:animated];
}

- (void)transitionToOnboardingAnimated:(BOOL)animated {
    SPNavigationController *nav = [[SPNavigationController alloc] initWithRootViewController:[SPOnboardingViewController new]];
    [self transitionToRootViewController:nav animated:animated];
}

- (void)transitionToAuthWelcomeAnimated:(BOOL)animated {
    SPAuthWelcomeViewController *welcome = [[SPAuthWelcomeViewController alloc] initWithContext:SPAuthPresentationContextGate];
    SPNavigationController *nav = [[SPNavigationController alloc] initWithRootViewController:welcome];
    [self transitionToRootViewController:nav animated:animated];
}

- (void)transitionToRootViewController:(UIViewController *)newRoot animated:(BOOL)animated {
    if (!self.window) return;
    self.window.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    [UIView performWithoutAnimation:^{
        [self.window endEditing:YES];
        newRoot.view.frame = self.window.bounds;
        [newRoot.view layoutIfNeeded];
    }];
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:^{
            self.window.rootViewController = newRoot;
            newRoot.view.frame = self.window.bounds;
            [self.window layoutIfNeeded];
            [newRoot.view layoutIfNeeded];
        }];
        return;
    }
    [UIView transitionWithView:self.window
                      duration:0.30
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        [UIView performWithoutAnimation:^{
            self.window.rootViewController = newRoot;
            newRoot.view.frame = self.window.bounds;
            [self.window layoutIfNeeded];
            [newRoot.view layoutIfNeeded];
        }];
    } completion:nil];
}

@end
