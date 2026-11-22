//
//  SPHomeShortcutCell.h
//  Spotify
//

#import <UIKit/UIKit.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPHomeShortcutCell : UICollectionViewCell

+ (NSString *)reuseId;
- (void)configureWithItem:(id<SPMediaItem>)item;

@end

NS_ASSUME_NONNULL_END
