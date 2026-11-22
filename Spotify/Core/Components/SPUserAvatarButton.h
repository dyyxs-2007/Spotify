//
//  SPUserAvatarButton.h
//  Spotify
//
//  全局同步的用户头像按钮：订阅 SPAuthService，点击默认展开左侧个人抽屉。
//

#import "SPScaleButton.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPUserAvatarButton : SPScaleButton

- (instancetype)initWithDiameter:(CGFloat)diameter;

@end

NS_ASSUME_NONNULL_END
