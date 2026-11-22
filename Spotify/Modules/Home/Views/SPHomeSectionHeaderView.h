//
//  SPHomeSectionHeaderView.h
//  Spotify
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPHomeSectionHeaderView : UICollectionReusableView

+ (NSString *)reuseId;
@property (nonatomic, strong, readonly) UILabel *titleLabel;

@end

NS_ASSUME_NONNULL_END
