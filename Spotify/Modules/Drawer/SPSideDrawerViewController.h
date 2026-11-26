//
//  SPSideDrawerViewController.h
//  Spotify
//
//  左侧滑入个人抽屉界面：个人资料卡片、个人音乐库速览、睡眠定时、快捷主题开关与账号管理。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPDrawerMenuAction) {
    SPDrawerMenuActionAuth = 0,
    SPDrawerMenuActionSwitchAccount,
    SPDrawerMenuActionLikedSongs,
    SPDrawerMenuActionLibrary,
    SPDrawerMenuActionActivity,
    SPDrawerMenuActionHistory,
    SPDrawerMenuActionSettings,
};

@interface SPSideDrawerViewController : UIViewController

@property (nonatomic, copy, nullable) void (^menuSelectionHandler)(SPDrawerMenuAction action);

- (void)refreshContent;

@end

NS_ASSUME_NONNULL_END
