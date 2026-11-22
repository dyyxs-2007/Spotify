//
//  SPAuthViewController.h
//  Spotify
//
//  原版 Spotify 极简左对齐表单页（密码登录 / 6位验证码登录 / 创建账号）。
//

#import <UIKit/UIKit.h>
#import "SPAuthWelcomeViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPAuthMode) {
    SPAuthModePasswordLogin = 0,
    SPAuthModeCodeLogin,
    SPAuthModeRegister,
};

@interface SPAuthViewController : UIViewController

@property (nonatomic, assign, readonly) SPAuthMode mode;
@property (nonatomic, assign, readonly) SPAuthPresentationContext context;
@property (nonatomic, copy, nullable) void (^authSuccessHandler)(void);

- (instancetype)initWithMode:(SPAuthMode)mode
                     context:(SPAuthPresentationContext)context;

@end

NS_ASSUME_NONNULL_END
