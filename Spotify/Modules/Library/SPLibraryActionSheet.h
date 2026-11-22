//
//  SPLibraryActionSheet.h
//  Spotify
//
//  新建歌单与收藏歌曲到指定歌单的统一交互入口。
//

#import <UIKit/UIKit.h>
#import "SPPlaylist.h"
#import "SPTrack.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPLibraryActionSheet : NSObject

+ (void)presentCreatePlaylistAlertFrom:(UIViewController *)vc
                            completion:(void (^ _Nullable)(SPPlaylist *created))completion;

+ (void)presentAddTrack:(SPTrack *)track
         toPlaylistFrom:(UIViewController *)vc;

@end

NS_ASSUME_NONNULL_END
