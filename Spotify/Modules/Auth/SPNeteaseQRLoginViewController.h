//
//  SPNeteaseQRLoginViewController.h
//  Spotify
//
//  网易云音乐 App 扫码登录页：生成高清二维码并每 2 秒轮询扫码确认状态，
//  授权成功后同步真实网易云账号 Cookie 与个人歌单，避免密码风控。
//

#import <UIKit/UIKit.h>
#import "SPAuthWelcomeViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPNeteaseQRLoginViewController : UIViewController

@property (nonatomic, assign, readonly) SPAuthPresentationContext context;
@property (nonatomic, copy, nullable) void (^authSuccessHandler)(void);

- (instancetype)initWithContext:(SPAuthPresentationContext)context;

@end

NS_ASSUME_NONNULL_END
