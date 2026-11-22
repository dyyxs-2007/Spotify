//
//  SPCoverPreviewViewController.h
//  Spotify
//
//  QQ 音乐风格长按高清封面大图浏览器：支持双指缩放、双击放大、下拉关闭与保存高清封面到系统相册。
//

#import <UIKit/UIKit.h>
#import "SPTrack.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPCoverPreviewViewController : UIViewController

- (instancetype)initWithTrack:(SPTrack *)track
             placeholderImage:(nullable UIImage *)placeholderImage
                   themeColor:(nullable UIColor *)themeColor;

@end

NS_ASSUME_NONNULL_END
