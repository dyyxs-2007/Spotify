//
//  SPAuthWelcomeViewController.h
//  Spotify
//
//  原版 Spotify 风格 + 柔和高级美学欢迎页：品牌矢量徽章、大标题与多入口胶囊按钮，
//  在同一个导航栈内平滑 push 到密码登录 / 验证码登录 / 注册页。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPAuthPresentationContext) {
    SPAuthPresentationContextGate = 0,  ///< 首次启动 / 登出后根路由入口
    SPAuthPresentationContextModal,     ///< App 内从抽屉或设置页弹出的模态入口
};

@interface SPAuthWelcomeViewController : UIViewController

@property (nonatomic, assign, readonly) SPAuthPresentationContext context;
@property (nonatomic, copy, nullable) void (^authSuccessHandler)(void);

- (instancetype)initWithContext:(SPAuthPresentationContext)context;

@end

NS_ASSUME_NONNULL_END
