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
    UIWindow *window = [self keyWindow];
    if (!window || message.length == 0) return;

    [sCurrentToast removeFromSuperview];
    sCurrentToastToken += 1;
    NSUInteger token = sCurrentToastToken;

    BOOL showAtTop = (position == SPToastPositionTop)
        || (position == SPToastPositionAuto && sCurrentKeyboardOverlap > 60.0);

    UIView *toast = [UIView new];
    toast.backgroundColor = SPTheme.toastBackgroundColor;
    toast.layer.cornerRadius = 12;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    toast.layer.shadowColor = UIColor.blackColor.CGColor;
    toast.layer.shadowOpacity = 0.30;
    toast.layer.shadowRadius = 14;
    toast.layer.shadowOffset = CGSizeMake(0, 4);

    UILabel *label = [UILabel new];
    label.text = message;
    label.textColor = SPTheme.toastTextColor;
    label.font = [SPTheme fontOfSize:14 weight:UIFontWeightSemibold];
    label.numberOfLines = 2;
    label.textAlignment = NSTextAlignmentCenter;
    [toast addSubview:label];
    [window addSubview:toast];
    sCurrentToast = toast;

    [label mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.mas_equalTo(UIEdgeInsetsMake(12, 16, 12, 16));
    }];
    [toast mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(window);
        make.left.greaterThanOrEqualTo(window).offset(20);
        make.right.lessThanOrEqualTo(window).offset(-20);
        if (showAtTop) {
            make.top.equalTo(window.mas_safeAreaLayoutGuideTop).offset(12);
        } else {
            make.bottom.equalTo(window.mas_safeAreaLayoutGuideBottom).offset(-134);
        }
    }];
    [UIView performWithoutAnimation:^{
        [window layoutIfNeeded];
    }];

    CGFloat entryOffsetY = showAtTop ? -14.0 : 12.0;
    toast.alpha = 0;
    toast.transform = CGAffineTransformMakeTranslation(0, entryOffsetY);
    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        toast.alpha = 1;
        toast.transform = CGAffineTransformIdentity;
    } completion:nil];

    NSTimeInterval stayDuration = MAX(1.2, duration);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(stayDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sCurrentToastToken != token || !toast.superview) return;
        [UIView animateWithDuration:0.18
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            toast.alpha = 0;
            toast.transform = CGAffineTransformMakeTranslation(0, showAtTop ? -10.0 : -8.0);
        } completion:^(BOOL finished) {
            [toast removeFromSuperview];
        }];
    });
}

@end
