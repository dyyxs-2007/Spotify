//
//  SPLibraryStore.h
//  Spotify
//
//  个人音乐库本地持久化仓库：已点赞歌曲、自建歌单与关注的艺人。
//

#import <Foundation/Foundation.h>
#import "SPTrack.h"
#import "SPPlaylist.h"
#import "SPArtist.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SPLibraryDidUpdateNotification;

@interface SPLibraryStore : NSObject

+ (instancetype)shared;

/// 当前生效的账号隔离作用域标识（如 @"u_demo_001" 或未登录时 @"guest"）
@property (nonatomic, copy, readonly) NSString *currentScopeKey;
/// 当前生效账号对应的磁盘 JSON 文件绝对路径
@property (nonatomic, copy, readonly) NSString *currentStorageFilePath;
/// 当登录态或当前账号切换时重新加载对应账号的独立音乐库
- (void)reloadForCurrentUser;

#pragma mark - Liked Songs
@property (nonatomic, copy, readonly) NSArray<SPTrack *> *likedTracks;
- (SPPlaylist *)likedSongsPlaylist;
- (BOOL)isTrackLiked:(nullable NSString *)trackId;
- (BOOL)toggleLikeTrack:(SPTrack *)track;

#pragma mark - User Playlists
@property (nonatomic, copy, readonly) NSArray<SPPlaylist *> *userPlaylists;
- (SPPlaylist *)createPlaylistWithName:(NSString *)name desc:(nullable NSString *)desc;
- (BOOL)deletePlaylistWithId:(NSString *)playlistId;
- (BOOL)addTrack:(SPTrack *)track toPlaylistId:(NSString *)playlistId;
- (BOOL)removeTrackId:(NSString *)trackId fromPlaylistId:(NSString *)playlistId;
- (nullable SPPlaylist *)localPlaylistWithId:(nullable NSString *)playlistId;
- (BOOL)isUserCreatedPlaylistId:(nullable NSString *)playlistId;

#pragma mark - Followed Artists
@property (nonatomic, copy, readonly) NSArray<SPArtist *> *followedArtists;
- (BOOL)isArtistFollowed:(nullable NSString *)artistId;
- (BOOL)toggleFollowArtist:(SPArtist *)artist;

#pragma mark - Saved Collections (Playlists / Albums)
- (BOOL)isCollectionSaved:(nullable NSString *)collectionId;
- (BOOL)toggleSaveCollectionWithId:(NSString *)collectionId;

@end

NS_ASSUME_NONNULL_END
