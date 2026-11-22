//
//  SPTheme.m
//  Spotify
//

#import "SPTheme.h"
#import "UIColor+SPHex.h"
#import "SceneDelegate.h"

NSNotificationName const SPThemeDidChangeNotification = @"com.dyyxs.spotify.theme.didChange";
static NSString * const SPThemeInterfaceStyleDefaultsKey = @"sp_interface_style_v1";

static UIColor *SPDynamicColor(UIColor *darkColor, UIColor *lightColor) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
        return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) ? lightColor : darkColor;
    }];
}

@implementation SPTheme

#pragma mark - Interface Style

+ (UIUserInterfaceStyle)interfaceStyle {
    NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:SPThemeInterfaceStyleDefaultsKey];
    if (saved == UIUserInterfaceStyleLight) {
        return UIUserInterfaceStyleLight;
    }
    return UIUserInterfaceStyleDark;
}

+ (BOOL)isDarkMode {
    return [self interfaceStyle] != UIUserInterfaceStyleLight;
}

+ (UIStatusBarStyle)preferredStatusBarStyle {
    return self.isDarkMode ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent;
}

+ (void)applyInterfaceStyle:(UIUserInterfaceStyle)style animated:(BOOL)animated {
    UIUserInterfaceStyle resolved = (style == UIUserInterfaceStyleLight) ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    [[NSUserDefaults standardUserDefaults] setInteger:resolved forKey:SPThemeInterfaceStyleDefaultsKey];

    void (^applyToWindows)(void) = ^{
        UIWindow *mainWindow = [SceneDelegate shared].window;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!mainWindow && [window isMemberOfClass:UIWindow.class]) {
                    mainWindow = window;
                }
                if (window != mainWindow) {
                    // 切勿给 UITextEffectsWindow / UIRemoteKeyboardWindow 等系统辅助窗口设置实心背景色，否则会遮挡整个屏幕造成黑白屏
                    window.overrideUserInterfaceStyle = resolved;
                    window.backgroundColor = UIColor.clearColor;
                }
            }
        }

        void (^applyThemeBlock)(void) = ^{
            [UIView performWithoutAnimation:^{
                if (mainWindow) {
                    mainWindow.overrideUserInterfaceStyle = resolved;
                    mainWindow.backgroundColor = self.backgroundColor;
                    mainWindow.tintColor = self.textPrimaryColor;

                    UIViewController *vc = mainWindow.rootViewController;
                    [vc setNeedsStatusBarAppearanceUpdate];
                    while (vc.presentedViewController) {
                        vc = vc.presentedViewController;
                        [vc setNeedsStatusBarAppearanceUpdate];
                    }
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:SPThemeDidChangeNotification object:self];
                [mainWindow layoutIfNeeded];
            }];
        };

        if (animated && mainWindow && !UIAccessibilityIsReduceMotionEnabled()) {
            [UIView transitionWithView:mainWindow
                              duration:0.24
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:applyThemeBlock
                            completion:nil];
        } else {
            applyThemeBlock();
        }
    };

    if (NSThread.isMainThread) {
        applyToWindows();
    } else {
        dispatch_async(dispatch_get_main_queue(), applyToWindows);
    }
}

#pragma mark - Dynamic Semantic Colors

+ (UIColor *)backgroundColor {
    return SPDynamicColor([UIColor sp_colorWithHex:0x121212], [UIColor sp_colorWithHex:0xF5F6F8]);
}

+ (UIColor *)elevatedColor {
    return SPDynamicColor([UIColor sp_colorWithHex:0x1B1B1E], UIColor.whiteColor);
}

+ (UIColor *)highlightColor {
    return SPDynamicColor([UIColor sp_colorWithHex:0x28282D], [UIColor sp_colorWithHex:0xEAECEF]);
}

+ (UIColor *)pressedColor {
    return SPDynamicColor([UIColor sp_colorWithHex:0x3A3A40], [UIColor sp_colorWithHex:0xDCE0E6]);
}

+ (UIColor *)accentColor {
    return SPDynamicColor([UIColor sp_colorWithHex:0x1ED760], [UIColor sp_colorWithHex:0x16A34A]);
}

+ (UIColor *)brandGreenColor {
    return [UIColor sp_colorWithHex:0x1ED760];
}

+ (UIColor *)textPrimaryColor {
    return SPDynamicColor(UIColor.whiteColor, [UIColor sp_colorWithHex:0x111214]);
}

+ (UIColor *)textSecondaryColor {
    return SPDynamicColor([UIColor sp_colorWithHex:0xB3B3B8], [UIColor sp_colorWithHex:0x5F636E]);
}

+ (UIColor *)textTertiaryColor {
    return SPDynamicColor([UIColor sp_colorWithHex:0x75757C], [UIColor sp_colorWithHex:0x8E939E]);
}

+ (UIColor *)separatorColor {
    return SPDynamicColor([UIColor colorWithWhite:1.0 alpha:0.09], [UIColor colorWithWhite:0.0 alpha:0.08]);
}

+ (UIColor *)coverBorderColor {
    return SPDynamicColor([UIColor colorWithWhite:1.0 alpha:0.10], [UIColor colorWithWhite:0.0 alpha:0.08]);
}

+ (UIColor *)toastBackgroundColor {
    return SPDynamicColor(UIColor.whiteColor, [UIColor sp_colorWithHex:0x18181B]);
}

+ (UIColor *)toastTextColor {
    return SPDynamicColor([UIColor sp_colorWithHex:0x111214], UIColor.whiteColor);
}

#pragma mark - Fonts

+ (UIFont *)fontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    return [UIFont systemFontOfSize:size weight:weight];
}

+ (UIFont *)monospacedDigitFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    return [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
}

+ (UIFont *)largeTitleFont   { return [self fontOfSize:24 weight:UIFontWeightBold]; }
+ (UIFont *)sectionTitleFont { return [self fontOfSize:22 weight:UIFontWeightBold]; }
+ (UIFont *)bodyFont         { return [self fontOfSize:16 weight:UIFontWeightRegular]; }
+ (UIFont *)captionFont      { return [self fontOfSize:13 weight:UIFontWeightRegular]; }

+ (UIImage *)symbol:(NSString *)name size:(CGFloat)size weight:(UIImageSymbolWeight)weight {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    return [UIImage systemImageNamed:name withConfiguration:config];
}

@end
