//
//  SPToast.h
//  Spotify
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPToastPosition) {
    SPToastPositionAuto = 0, // 自动避让键盘：键盘弹起时悬浮在顶部，平时显示在底部
    SPToastPositionBottom,
    SPToastPositionTop,
};

@interface SPToast : NSObject

/// 默认轻提示（自动感知键盘位置，持续 2.2 秒）
+ (void)showMessage:(NSString *)message;

/// 自定义时长与位置的轻提示（如登录页顶部验证码横幅）
+ (void)showMessage:(NSString *)message
           duration:(NSTimeInterval)duration
           position:(SPToastPosition)position;

@end

NS_ASSUME_NONNULL_END
