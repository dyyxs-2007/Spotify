//
//  SPToast.m
//  Spotify
//

#import "SPToast.h"
#import "SceneDelegate.h"

@implementation SPToast

static __weak UIView *sCurrentToast;
static NSUInteger sCurrentToastToken = 0;
static CGFloat sCurrentKeyboardOverlap = 0.0;

+ (void)dismissToastView:(UIView *)toast upward:(BOOL)upward {
    if (!toast || !toast.superview) return;
    if (toast == sCurrentToast) {
        sCurrentToastToken += 1;
        sCurrentToast = nil;
    }
    toast.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.18
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        toast.alpha = 0;
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            toast.transform = CGAffineTransformMakeTranslation(0, upward ? -12.0 : 8.0);
        }
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

+ (void)handleToastDismissGesture:(UIGestureRecognizer *)gesture {
    [self dismissToastView:gesture.view upward:YES];
}

+ (void)load {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardFrameChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

+ (void)handleKeyboardFrameChange:(NSNotification *)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect screenBounds = UIScreen.mainScreen.bounds;
    CGFloat overlap = MAX(0.0, CGRectGetMaxY(screenBounds) - CGRectGetMinY(endFrame));
    sCurrentKeyboardOverlap = overlap;
}

+ (void)handleKeyboardWillHide:(NSNotification *)note {
    sCurrentKeyboardOverlap = 0.0;
}

+ (UIWindow *)keyWindow {
    UIWindow *mainWindow = [SceneDelegate shared].window;
    if (mainWindow) return mainWindow;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if ([window isMemberOfClass:UIWindow.class] && window.isKeyWindow) return window;
        }
    }
    return nil;
}

+ (void)showMessage:(NSString *)message {
    [self showMessage:message duration:2.2 position:SPToastPositionAuto];
}

+ (void)showMessage:(NSString *)message
           duration:(NSTimeInterval)duration
           position:(SPToastPosition)position {
    if (message.length == 0) return;
    if (!NSThread.isMainThread) {
        NSString *copied = [message copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessage:copied duration:duration position:position];
        });
        return;
    }

    UIWindow *window = [self keyWindow];
    if (!window) return;

    [sCurrentToast removeFromSuperview];
    sCurrentToastToken += 1;
    NSUInteger token = sCurrentToastToken;

    BOOL showAtTop = (position == SPToastPositionTop)
        || (position == SPToastPositionAuto && sCurrentKeyboardOverlap > 60.0);

    UIView *toast = [UIView new];
    toast.backgroundColor = SPTheme.toastBackgroundColor;
    toast.layer.cornerRadius = 14;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    toast.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    toast.layer.borderColor = [[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return (tc.userInterfaceStyle == UIUserInterfaceStyleLight)
            ? [UIColor colorWithWhite:1.0 alpha:0.12]
            : [UIColor colorWithWhite:0.0 alpha:0.10];
    }] resolvedColorWithTraitCollection:window.traitCollection].CGColor;
    toast.layer.shadowColor = UIColor.blackColor.CGColor;
    toast.layer.shadowOpacity = (window.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) ? 0.22 : 0.34;
    toast.layer.shadowRadius = 14;
    toast.layer.shadowOffset = CGSizeMake(0, 4);

    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleToastDismissGesture:)];
    [toast addGestureRecognizer:dismissTap];
    if (showAtTop) {
        UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleToastDismissGesture:)];
        swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
        [toast addGestureRecognizer:swipeUp];
    }

    UILabel *label = [UILabel new];
    label.text = message;
    label.textColor = SPTheme.toastTextColor;
    label.font = [SPTheme fontOfSize:13.5 weight:UIFontWeightSemibold];
    label.numberOfLines = 3;
    label.textAlignment = NSTextAlignmentCenter;
    label.lineBreakStrategy = NSLineBreakStrategyStandard;
    [toast addSubview:label];
    [window addSubview:toast];
    sCurrentToast = toast;

    [label mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.mas_equalTo(UIEdgeInsetsMake(10, 14, 10, 14));
    }];
    [toast mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(window);
        if (showAtTop) {
            // 下移至 48pt 自定义导航栏下方，避免遮挡返回按钮与页面标题，点击或上滑可提前收起
            make.left.greaterThanOrEqualTo(window).offset(20);
            make.right.lessThanOrEqualTo(window).offset(-20);
            make.top.equalTo(window.mas_safeAreaLayoutGuideTop).offset(52);
        } else {
            make.left.greaterThanOrEqualTo(window).offset(20);
            make.right.lessThanOrEqualTo(window).offset(-20);
            make.bottom.equalTo(window.mas_safeAreaLayoutGuideBottom).offset(-134);
        }
    }];
    [UIView performWithoutAnimation:^{
        [window layoutIfNeeded];
    }];
    toast.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:toast.bounds cornerRadius:14].CGPath;

    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    CGFloat entryOffsetY = (reduceMotion ? 0.0 : (showAtTop ? -14.0 : 12.0));
    toast.alpha = 0;
    toast.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, entryOffsetY);
    [UIView animateWithDuration:reduceMotion ? 0.16 : 0.28
                          delay:0
         usingSpringWithDamping:reduceMotion ? 1.0 : 0.86
          initialSpringVelocity:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        toast.alpha = 1;
        toast.transform = CGAffineTransformIdentity;
    } completion:nil];

    NSTimeInterval stayDuration = MAX(1.2, duration);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(stayDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sCurrentToastToken != token || !toast.superview) return;
        [self dismissToastView:toast upward:showAtTop];
    });
}

@end
