//
//  SPAlbum.h
//  Spotify
//

#import <Foundation/Foundation.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@class SPArtist, SPTrack;

@interface SPAlbum : NSObject <SPMediaItem>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *coverURL;
@property (nonatomic, copy, nullable) NSString *colorHex;
@property (nonatomic, copy, nullable) NSArray<SPArtist *> *artists;
@property (nonatomic, assign) NSInteger releaseYear;
/// "专辑" / "EP" / "单曲"
@property (nonatomic, copy, nullable) NSString *albumType;
/// 列表接口里可能为空，详情接口才完整
@property (nonatomic, copy, nullable) NSArray<SPTrack *> *tracks;

- (NSString *)artistNames;

@end

NS_ASSUME_NONNULL_END
