//
//  SPPlaylist.h
//  Spotify
//

#import <Foundation/Foundation.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@class SPTrack;

/// "已点赞的歌曲" 这个特殊歌单的固定 id
FOUNDATION_EXPORT NSString * const SPLikedSongsPlaylistId;

@interface SPPlaylist : NSObject <SPMediaItem>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *desc;
@property (nonatomic, copy, nullable) NSString *coverURL;
@property (nonatomic, copy, nullable) NSString *colorHex;
@property (nonatomic, copy, nullable) NSString *creatorName;
@property (nonatomic, copy, nullable) NSString *creatorUserId;
@property (nonatomic, assign) NSInteger followerCount;
@property (nonatomic, copy, nullable) NSArray<SPTrack *> *tracks;

@property (nonatomic, readonly, getter=isLikedSongs) BOOL likedSongs;
@property (nonatomic, readonly, getter=isPodcast) BOOL podcast;

@end

NS_ASSUME_NONNULL_END
