//
//  SPScaleButton.h
//  Spotify
//
//  具备 44×44 最小触控区、按下 0.96 缩放、光学居中微调与上下文图标切换动画的通用按钮。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPScaleButton : UIButton

/// 禁用按下缩放动画（默认 NO）
@property (nonatomic, assign) BOOL isStatic;
/// 水平光学偏移（如播放三角形设为 +2.0 使其视觉居中）
@property (nonatomic, assign) CGFloat opticalHorizontalOffset;

/// 设置 SF Symbol；当 animated == YES 且图标名称变化时执行无回弹缩放渐显过渡
- (void)sp_setSymbol:(NSString *)symbolName
                size:(CGFloat)size
              weight:(UIImageSymbolWeight)weight
            animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
