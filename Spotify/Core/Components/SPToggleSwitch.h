//
//  SPToggleSwitch.h
//  Spotify
//
//  全项目统一的静音自定义开关（避免系统 UISwitch 强制震动、仅响应横向滑动不抢列表竖滑、支持 44pt 垂直触控区与动态语义色）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPToggleSwitch : UIControl

@property (nonatomic, assign, getter=isOn) BOOL on;
@property (nonatomic, strong, nullable) UIColor *onTintColor;

- (void)setOn:(BOOL)on animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
