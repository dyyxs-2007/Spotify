//
//  SceneDelegate.h
//  Spotify
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic, nullable) UIWindow *window;

+ (nullable instancetype)shared;
+ (BOOL)hasCompletedOnboarding;
+ (void)setHasCompletedOnboarding:(BOOL)completed;
+ (BOOL)hasEnteredGuestMode;
+ (void)setHasEnteredGuestMode:(BOOL)entered;

- (void)transitionToMainAppAnimated:(BOOL)animated;
- (void)transitionToOnboardingAnimated:(BOOL)animated;
- (void)transitionToAuthWelcomeAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
