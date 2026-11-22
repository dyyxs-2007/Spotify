//
//  SPDetailViewController.h
//  Spotify
//

#import <UIKit/UIKit.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPDetailViewController : UIViewController

- (instancetype)initWithMediaItem:(id<SPMediaItem>)item;

@end

NS_ASSUME_NONNULL_END
