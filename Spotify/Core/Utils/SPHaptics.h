//
//  SPHaptics.h
//  Spotify
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPHaptics : NSObject

@property (class, nonatomic, assign, getter=isEnabled) BOOL enabled;

+ (void)light;
+ (void)medium;
+ (void)selection;

@end

NS_ASSUME_NONNULL_END
