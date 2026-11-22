//
//  SPSearchCategoryCell.h
//  Spotify
//

#import <UIKit/UIKit.h>
#import "SPFeedModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPSearchCategoryCell : UICollectionViewCell

+ (NSString *)reuseId;
- (void)configureWithCategory:(SPSearchCategory *)category;

@end

NS_ASSUME_NONNULL_END
