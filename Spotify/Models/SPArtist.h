//
//  SPArtist.h
//  Spotify
//

#import <Foundation/Foundation.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPArtist : NSObject <SPMediaItem>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *coverURL;

@end

NS_ASSUME_NONNULL_END
