//
//  SPMusicDataSource.h
//  Spotify
//
//  音乐数据源协议 —— 数据层的"插座"。
//  Mock、网易云、以后任何音乐源都实现这个协议；UI 与播放器只依赖它，切换数据源零改动。
//  约定：实现方可以在任意线程回调，由 SPMusicRepository 统一切回主线程。
//

#import <Foundation/Foundation.h>
#import "SPFeedModels.h"
#import "SPTrack.h"
#import "SPAlbum.h"
#import "SPPlaylist.h"
#import "SPArtist.h"
#import "SPLyricModel.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const SPMusicErrorDomain;

typedef NS_ERROR_ENUM(SPMusicErrorDomain, SPMusicErrorCode) {
    SPMusicErrorUnknown = -1,
    SPMusicErrorNotFound = 404,
    SPMusicErrorNoCopyright = 451,  ///< 无版权 / 无播放地址
    SPMusicErrorNetwork = 1000,
};

@protocol SPMusicDataSource <NSObject>

/// 数据源名称，便于调试展示
- (NSString *)sourceName;

- (void)fetchHomeSectionsWithCompletion:(void (^)(NSArray<SPHomeSection *> *_Nullable sections, NSError *_Nullable error))completion;

/// 按首页顶部分类标签（全部 / 音乐 / 播客）获取差异化分区
- (void)fetchHomeSectionsForCategory:(SPHomeCategory)category
                          completion:(void (^)(NSArray<SPHomeSection *> *_Nullable sections, NSError *_Nullable error))completion;

/// 首页上滑渐进加载更多分区（page 从 1 开始）
- (void)fetchHomeMoreSectionsForPage:(NSInteger)page
                          completion:(void (^)(NSArray<SPHomeSection *> *_Nullable sections, BOOL hasMore, NSError *_Nullable error))completion;

- (void)fetchHomeMoreSectionsForCategory:(SPHomeCategory)category
                                    page:(NSInteger)page
                              completion:(void (^)(NSArray<SPHomeSection *> *_Nullable sections, BOOL hasMore, NSError *_Nullable error))completion;

- (void)fetchSearchCategoriesWithCompletion:(void (^)(NSArray<SPSearchCategory *> *_Nullable categories, NSError *_Nullable error))completion;

- (void)searchWithKeyword:(NSString *)keyword
               completion:(void (^)(SPSearchResult *_Nullable result, NSError *_Nullable error))completion;

- (void)fetchPlaylistWithId:(NSString *)playlistId
                 completion:(void (^)(SPPlaylist *_Nullable playlist, NSError *_Nullable error))completion;

- (void)fetchAlbumWithId:(NSString *)albumId
              completion:(void (^)(SPAlbum *_Nullable album, NSError *_Nullable error))completion;

- (void)fetchArtistTopTracksWithId:(NSString *)artistId
                        completion:(void (^)(SPArtist *_Nullable artist, NSArray<SPTrack *> *_Nullable tracks, NSError *_Nullable error))completion;

- (void)fetchLibraryItemsWithCompletion:(void (^)(NSArray<id<SPMediaItem>> *_Nullable items, NSError *_Nullable error))completion;

/// 获取歌曲的可播放地址（真实音乐源的 URL 通常有时效，必须在播放前实时获取）
- (void)fetchPlayURLForTrack:(SPTrack *)track
                  completion:(void (^)(NSURL *_Nullable url, NSError *_Nullable error))completion;

/// 获取歌曲 LRC 同步歌词与双语翻译
- (void)fetchLyricsForTrack:(SPTrack *)track
                 completion:(void (^)(SPLyricDocument *_Nullable lyrics, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
