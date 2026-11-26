//
//  SPNowPlayingViewController.h
//  Spotify
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPNowPlayingViewController : UIViewController

@property (nonatomic, strong, readonly) UIImageView *coverView;
/// 封面外层阴影容器（转场时需整体隐藏，避免残留空心黑影方块）
@property (nonatomic, strong, readonly) UIView *coverShadowContainer;
/// 下拉关闭释放瞬间的纵向初速度（pt/s），用于 Hero 封面收回动画衔接手势动量
@property (nonatomic, assign, readonly) CGFloat dismissVelocityY;
/// 交互下拉退出时回调拖拽进度（0..1），同步清理背景遮罩
@property (nonatomic, copy, nullable) void (^dismissDragProgressHandler)(CGFloat progress);
/// 在空白播放页点击引导按钮时回调需要跳转的主 Tab（0=首页，2=音乐库）
@property (nonatomic, copy, nullable) void (^emptyActionHandler)(NSInteger targetTabIndex);

@end

NS_ASSUME_NONNULL_END
