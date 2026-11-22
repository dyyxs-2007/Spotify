//
//  SPDetailHeaderView.h
//  Spotify
//

#import <UIKit/UIKit.h>
#import "SPMediaItem.h"
#import "SPTrack.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPDetailHeaderView : UIView

@property (nonatomic, strong, readonly) UIView *shadowContainer;
@property (nonatomic, copy, nullable) void (^playHandler)(void);
@property (nonatomic, copy, nullable) void (^shuffleHandler)(void);
@property (nonatomic, copy, nullable) void (^followHandler)(void);
@property (nonatomic, copy, nullable) void (^likeHandler)(void);
@property (nonatomic, copy, nullable) void (^moreHandler)(void);
@property (nonatomic, copy, nullable) void (^dominantColorHandler)(UIColor *color);

- (void)configureWithItem:(id<SPMediaItem>)item
                   tracks:(NSArray<SPTrack *> *)tracks
                isPlaying:(BOOL)isPlaying
           shuffleEnabled:(BOOL)shuffleEnabled;

- (void)updatePlaying:(BOOL)isPlaying shuffleEnabled:(BOOL)shuffleEnabled animated:(BOOL)animated;
- (void)updateFollowState:(BOOL)followed animated:(BOOL)animated;
- (void)updateLikeState:(BOOL)liked animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
