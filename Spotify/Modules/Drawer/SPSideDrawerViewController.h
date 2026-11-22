//
//  SPSideDrawerViewController.h
//  Spotify
//
//  左侧滑入个人抽屉界面：个人资料卡片、快捷导航（新动态/收听历史/设置/缓存）与登录退出操作。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPDrawerMenuAction) {
    SPDrawerMenuActionAuth = 0,
    SPDrawerMenuActionActivity,
    SPDrawerMenuActionHistory,
    SPDrawerMenuActionSettings,
};

@interface SPSideDrawerViewController : UIViewController

@property (nonatomic, copy, nullable) void (^menuSelectionHandler)(SPDrawerMenuAction action);

- (void)refreshContent;

@end

NS_ASSUME_NONNULL_END
