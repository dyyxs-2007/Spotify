//
//  SPTheme.h
//  Spotify
//
//  设计 Token：颜色 / 字体 / 间距 / 动态深浅模式管理。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 深浅主题变化通知
extern NSNotificationName const SPThemeDidChangeNotification;

/// 页面左右边距
static const CGFloat SPMarginHorizontal = 16.0;
/// 迷你播放条高度
static const CGFloat SPMiniPlayerHeight = 56.0;

@interface SPTheme : NSObject

#pragma mark - Interface Style
@property (class, nonatomic, assign, readonly) UIUserInterfaceStyle interfaceStyle;
@property (class, nonatomic, assign, readonly) BOOL isDarkMode;
+ (void)applyInterfaceStyle:(UIUserInterfaceStyle)style animated:(BOOL)animated;
+ (UIStatusBarStyle)preferredStatusBarStyle;

#pragma mark - Dynamic Semantic Colors
@property (class, nonatomic, readonly) UIColor *backgroundColor;     ///< 主背景（Dark #121212 / Light #F5F6F8）
@property (class, nonatomic, readonly) UIColor *elevatedColor;       ///< 次级卡片（Dark #1B1B1E / Light #FFFFFF）
@property (class, nonatomic, readonly) UIColor *highlightColor;      ///< 高亮填充（Dark #28282D / Light #EAECEF）
@property (class, nonatomic, readonly) UIColor *pressedColor;        ///< 按压态（Dark #3A3A40 / Light #DCE0E6）
@property (class, nonatomic, readonly) UIColor *accentColor;         ///< 主题强调绿（Dark #1ED760 / Light #16A34A）
@property (class, nonatomic, readonly) UIColor *brandGreenColor;     ///< 恒定品牌绿 #1ED760（用于深色沉浸页）
@property (class, nonatomic, readonly) UIColor *textPrimaryColor;    ///< 主文字
@property (class, nonatomic, readonly) UIColor *textSecondaryColor;  ///< 次级文字
@property (class, nonatomic, readonly) UIColor *textTertiaryColor;   ///< 弱提示文字
@property (class, nonatomic, readonly) UIColor *separatorColor;      ///< 分割线与描边
@property (class, nonatomic, readonly) UIColor *coverBorderColor;    ///< 封面 1px 中性描边
@property (class, nonatomic, readonly) UIColor *toastBackgroundColor;
@property (class, nonatomic, readonly) UIColor *toastTextColor;

#pragma mark - Fonts
+ (UIFont *)fontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
/// 等宽数字（时间、进度、统计）
+ (UIFont *)monospacedDigitFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
@property (class, nonatomic, readonly) UIFont *largeTitleFont;   ///< 24 bold 页面大标题
@property (class, nonatomic, readonly) UIFont *sectionTitleFont; ///< 22 bold 分区标题
@property (class, nonatomic, readonly) UIFont *bodyFont;         ///< 16 regular
@property (class, nonatomic, readonly) UIFont *captionFont;      ///< 13 regular

#pragma mark - Helpers
/// 统一的 SF Symbol 图标
+ (UIImage *)symbol:(NSString *)name size:(CGFloat)size weight:(UIImageSymbolWeight)weight;

@end

NS_ASSUME_NONNULL_END
