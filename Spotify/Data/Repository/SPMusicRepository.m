//
//  SPMusicRepository.m
//  Spotify
//

#import "SPMusicRepository.h"
#import "SPLRUCache.h"
#import "SPAudioCacheManager.h"
#import "SPLibraryStore.h"

NSErrorDomain const SPMusicErrorDomain = @"com.dyyxs.spotify.music";
NSNotificationName const SPMusicSourceDidChangeNotification = @"com.dyyxs.spotify.music.sourceDidChange";

/// 把任意回调包装成主线程回调
#define SP_MAIN_WORK(block) \
    if (NSThread.isMainThread) { block(); } else { dispatch_async(dispatch_get_main_queue(), block); }

@interface SPMusicRepository ()
@property (nonatomic, strong) SPLRUCache<NSString *, SPPlaylist *> *playlistCache;
@property (nonatomic, strong) SPLRUCache<NSString *, SPAlbum *> *albumCache;
@property (nonatomic, strong) SPLRUCache<NSString *, NSArray<SPTrack *> *> *artistTracksCache;
@property (nonatomic, strong) SPLRUCache<NSString *, SPArtist *> *artistProfileCache;
@property (nonatomic, strong) SPLRUCache<NSString *, SPSearchResult *> *searchCache;
@property (nonatomic, strong) SPLRUCache<NSString *, SPLyricDocument *> *lyricsCache;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<SPHomeSection *> *> *cachedHomeSectionsByCategory;
@property (nonatomic, copy, nullable) NSArray<SPSearchCategory *> *cachedCategories;
@property (nonatomic, copy, nullable) NSArray<id<SPMediaItem>> *cachedLibraryItems;
@end

@implementation SPMusicRepository

@synthesize source = _source;
@synthesize cachedCategories = _cachedCategories;
@synthesize cachedLibraryItems = _cachedLibraryItems;

+ (instancetype)shared {
    static SPMusicRepository *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SPMusicRepository new]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _playlistCache = [[SPLRUCache alloc] initWithMaxCount:50];
        _albumCache = [[SPLRUCache alloc] initWithMaxCount:50];
        _artistTracksCache = [[SPLRUCache alloc] initWithMaxCount:40];
        _artistProfileCache = [[SPLRUCache alloc] initWithMaxCount:40];
        _searchCache = [[SPLRUCache alloc] initWithMaxCount:60];
        _lyricsCache = [[SPLRUCache alloc] initWithMaxCount:60];
        _cachedHomeSectionsByCategory = [NSMutableDictionary dictionary];
    }
    return self;
}

- (id<SPMusicDataSource>)source {
    @synchronized (self) {
        return _source;
    }
}

- (void)setSource:(id<SPMusicDataSource>)source {
    @synchronized (self) {
        if (_source == source) return;
        _source = source;
    }
    [self clearMetadataCaches];
    [[SPAudioCacheManager shared] clearMemoryCaches];
    SP_MAIN_WORK(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPMusicSourceDidChangeNotification object:self];
    });
}

- (NSArray<SPSearchCategory *> *)cachedCategories {
    @synchronized (self) {
        return _cachedCategories;
    }
}

- (void)setCachedCategories:(NSArray<SPSearchCategory *> *)cachedCategories {
    @synchronized (self) {
        _cachedCategories = [cachedCategories copy];
    }
}

- (NSArray<id<SPMediaItem>> *)cachedLibraryItems {
    @synchronized (self) {
        return _cachedLibraryItems;
    }
}

- (void)setCachedLibraryItems:(NSArray<id<SPMediaItem>> *)cachedLibraryItems {
    @synchronized (self) {
        _cachedLibraryItems = [cachedLibraryItems copy];
    }
}

- (NSString *)sourceName { return self.source.sourceName; }

- (NSUInteger)cacheHitCount {
    return self.playlistCache.hitCount
         + self.albumCache.hitCount
         + self.artistTracksCache.hitCount
         + self.artistProfileCache.hitCount
         + self.searchCache.hitCount
         + self.lyricsCache.hitCount;
}

- (NSUInteger)cachedEntryCount {
    return self.playlistCache.count
         + self.albumCache.count
         + self.artistTracksCache.count
         + self.artistProfileCache.count
         + self.searchCache.count
         + self.lyricsCache.count;
}

- (SPPlaylist *)cachedPlaylistForId:(NSString *)playlistId {
    SPPlaylist *local = [[SPLibraryStore shared] localPlaylistWithId:playlistId];
    if (local) return local;
    return [self.playlistCache objectForKey:playlistId];
}

- (SPAlbum *)cachedAlbumForId:(NSString *)albumId {
    return [self.albumCache objectForKey:albumId];
}

- (void)clearMetadataCaches {
    [self.playlistCache removeAllObjects];
    [self.albumCache removeAllObjects];
    [self.artistTracksCache removeAllObjects];
    [self.artistProfileCache removeAllObjects];
    [self.searchCache removeAllObjects];
    [self.lyricsCache removeAllObjects];
    @synchronized (self.cachedHomeSectionsByCategory) {
        [self.cachedHomeSectionsByCategory removeAllObjects];
    }
    self.cachedCategories = nil;
    self.cachedLibraryItems = nil;
}

#pragma mark - Home

- (void)fetchHomeSectionsWithCompletion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    [self fetchHomeSectionsForCategory:SPHomeCategoryAll completion:completion];
}

- (void)fetchHomeSectionsForCategory:(SPHomeCategory)category
                          completion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    NSArray<SPHomeSection *> *cached = nil;
    @synchronized (self.cachedHomeSectionsByCategory) {
        cached = self.cachedHomeSectionsByCategory[@(category)];
    }
    if (cached.count > 0) {
        SP_MAIN_WORK(^{ if (completion) completion(cached, nil); });
        return;
    }
    [self refreshHomeSectionsForCategory:category completion:completion];
}

- (void)refreshHomeSectionsWithCompletion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    [self refreshHomeSectionsForCategory:SPHomeCategoryAll completion:completion];
}

- (void)refreshHomeSectionsForCategory:(SPHomeCategory)category
                            completion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    id<SPMusicDataSource> currentSource = self.source;
    __weak typeof(self) weakSelf = self;
    [currentSource fetchHomeSectionsForCategory:category completion:^(NSArray<SPHomeSection *> *sections, NSError *error) {
        SP_MAIN_WORK(^{
            if (weakSelf.source != currentSource) return;
            if (!error && sections.count > 0) {
                @synchronized (weakSelf.cachedHomeSectionsByCategory) {
                    weakSelf.cachedHomeSectionsByCategory[@(category)] = sections;
                }
                [weakSelf warmCachesFromHomeSections:sections];
            }
            if (completion) completion(sections, error);
        });
    }];
}

- (void)fetchHomeMoreSectionsForPage:(NSInteger)page
                          completion:(void (^)(NSArray<SPHomeSection *> * _Nullable, BOOL, NSError * _Nullable))completion {
    [self fetchHomeMoreSectionsForCategory:SPHomeCategoryAll page:page completion:completion];
}

- (void)fetchHomeMoreSectionsForCategory:(SPHomeCategory)category
                                    page:(NSInteger)page
                              completion:(void (^)(NSArray<SPHomeSection *> * _Nullable, BOOL, NSError * _Nullable))completion {
    id<SPMusicDataSource> currentSource = self.source;
    __weak typeof(self) weakSelf = self;
    [currentSource fetchHomeMoreSectionsForCategory:category page:page completion:^(NSArray<SPHomeSection *> *sections, BOOL hasMore, NSError *error) {
        SP_MAIN_WORK(^{
            if (weakSelf.source != currentSource) return;
            if (!error && sections.count > 0) {
                [weakSelf warmCachesFromHomeSections:sections];
            }
            if (completion) completion(sections, hasMore, error);
        });
    }];
}

- (void)warmCachesFromHomeSections:(NSArray<SPHomeSection *> *)sections {
    for (SPHomeSection *section in sections) {
        for (id<SPMediaItem> item in section.items) {
            if ([item isKindOfClass:SPPlaylist.class]) {
                SPPlaylist *pl = (SPPlaylist *)item;
                if (pl.tracks.count > 0) [self.playlistCache setObject:pl forKey:pl.identifier];
            } else if ([item isKindOfClass:SPAlbum.class]) {
                SPAlbum *al = (SPAlbum *)item;
                if (al.tracks.count > 0) [self.albumCache setObject:al forKey:al.identifier];
            }
        }
    }
}

#pragma mark - Search & Categories

- (void)fetchSearchCategoriesWithCompletion:(void (^)(NSArray<SPSearchCategory *> *, NSError *))completion {
    if (self.cachedCategories.count > 0) {
        NSArray<SPSearchCategory *> *cached = self.cachedCategories;
        SP_MAIN_WORK(^{ if (completion) completion(cached, nil); });
        return;
    }
    id<SPMusicDataSource> currentSource = self.source;
    __weak typeof(self) weakSelf = self;
    [currentSource fetchSearchCategoriesWithCompletion:^(NSArray<SPSearchCategory *> *categories, NSError *error) {
        SP_MAIN_WORK(^{
            if (weakSelf.source != currentSource) return;
            if (!error && categories.count > 0) weakSelf.cachedCategories = categories;
            if (completion) completion(categories, error);
        });
    }];
}

- (void)searchWithKeyword:(NSString *)keyword completion:(void (^)(SPSearchResult *, NSError *))completion {
    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *cacheKey = trimmed.lowercaseString;
    if (cacheKey.length > 0) {
        SPSearchResult *cached = [self.searchCache objectForKey:cacheKey];
        if (cached) {
            SP_MAIN_WORK(^{ if (completion) completion(cached, nil); });
            return;
        }
    }
    id<SPMusicDataSource> currentSource = self.source;
    __weak typeof(self) weakSelf = self;
    [currentSource searchWithKeyword:trimmed completion:^(SPSearchResult *result, NSError *error) {
        SP_MAIN_WORK(^{
            if (weakSelf.source != currentSource) return;
            if (!error && result && cacheKey.length > 0) {
                [weakSelf.searchCache setObject:result forKey:cacheKey];
            }
            if (completion) completion(result, error);
        });
    }];
}

#pragma mark - Playlist / Album / Artist / Library / URL

- (void)fetchPlaylistWithId:(NSString *)playlistId completion:(void (^)(SPPlaylist *, NSError *))completion {
    SPPlaylist *local = [[SPLibraryStore shared] localPlaylistWithId:playlistId];
    if (local) {
        SP_MAIN_WORK(^{ if (completion) completion(local, nil); });
        return;
    }
    SPPlaylist *cached = [self.playlistCache objectForKey:playlistId];
    if (cached && cached.tracks.count > 0) {
        SP_MAIN_WORK(^{ if (completion) completion(cached, nil); });
        return;
    }
    id<SPMusicDataSource> currentSource = self.source;
    __weak typeof(self) weakSelf = self;
    [currentSource fetchPlaylistWithId:playlistId completion:^(SPPlaylist *playlist, NSError *error) {
        SP_MAIN_WORK(^{
            if (weakSelf.source != currentSource) return;
            if (!error && playlist) [weakSelf.playlistCache setObject:playlist forKey:playlistId];
            if (completion) completion(playlist, error);
        });
    }];
}

- (void)fetchAlbumWithId:(NSString *)albumId completion:(void (^)(SPAlbum *, NSError *))completion {
    SPAlbum *cached = [self.albumCache objectForKey:albumId];
    if (cached && cached.tracks.count > 0) {
        SP_MAIN_WORK(^{ if (completion) completion(cached, nil); });
        return;
    }
    id<SPMusicDataSource> currentSource = self.source;
    __weak typeof(self) weakSelf = self;
    [currentSource fetchAlbumWithId:albumId completion:^(SPAlbum *album, NSError *error) {
        SP_MAIN_WORK(^{
            if (weakSelf.source != currentSource) return;
            if (!error && album) [weakSelf.albumCache setObject:album forKey:albumId];
            if (completion) completion(album, error);
        });
    }];
}

- (void)fetchArtistTopTracksWithId:(NSString *)artistId
                        completion:(void (^)(SPArtist * _Nullable, NSArray<SPTrack *> * _Nullable, NSError * _Nullable))completion {
    NSArray<SPTrack *> *cached = [self.artistTracksCache objectForKey:artistId];
    if (cached.count > 0) {
        SPArtist *cachedArtist = [self.artistProfileCache objectForKey:artistId];
        SP_MAIN_WORK(^{ if (completion) completion(cachedArtist, cached, nil); });
        return;
    }
    id<SPMusicDataSource> currentSource = self.source;
    __weak typeof(self) weakSelf = self;
    [currentSource fetchArtistTopTracksWithId:artistId completion:^(SPArtist *artist, NSArray<SPTrack *> *tracks, NSError *error) {
        SP_MAIN_WORK(^{
            if (weakSelf.source != currentSource) return;
            if (!error && tracks.count > 0) {
                [weakSelf.artistTracksCache setObject:tracks forKey:artistId];
                if (artist) {
                    [weakSelf.artistProfileCache setObject:artist forKey:artistId];
                }
            }
            if (completion) completion(artist, tracks, error);
        });
    }];
}

- (void)fetchLibraryItemsWithCompletion:(void (^)(NSArray<id<SPMediaItem>> *, NSError *))completion {
    id<SPMusicDataSource> currentSource = self.source;
    __weak typeof(self) weakSelf = self;
    [currentSource fetchLibraryItemsWithCompletion:^(NSArray<id<SPMediaItem>> *items, NSError *error) {
        SP_MAIN_WORK(^{
            if (weakSelf.source != currentSource) return;
            if (!error && items) {
                weakSelf.cachedLibraryItems = items;
                for (id<SPMediaItem> item in items) {
                    if ([item isKindOfClass:SPPlaylist.class] && ((SPPlaylist *)item).tracks.count > 0) {
                        [weakSelf.playlistCache setObject:(SPPlaylist *)item forKey:item.identifier];
                    } else if ([item isKindOfClass:SPAlbum.class] && ((SPAlbum *)item).tracks.count > 0) {
                        [weakSelf.albumCache setObject:(SPAlbum *)item forKey:item.identifier];
                    }
                }
            }
            if (completion) completion(items, error);
        });
    }];
}

- (void)fetchPlayURLForTrack:(SPTrack *)track completion:(void (^)(NSURL *, NSError *))completion {
    [self.source fetchPlayURLForTrack:track completion:^(NSURL *url, NSError *error) {
        SP_MAIN_WORK(^{ if (completion) completion(url, error); });
    }];
}
//

- (void)fetchLyricsForTrack:(SPTrack *)track completion:(void (^)(SPLyricDocument *, NSError *))completion {
    NSString *trackId = track.identifier;
    if (trackId.length == 0) {
        SP_MAIN_WORK(^{ if (completion) completion([SPLyricDocument parseLRC:nil translationLRC:nil], nil); });
        return;
    }
    SPLyricDocument *cached = [self.lyricsCache objectForKey:trackId];
    if (cached) {
        SP_MAIN_WORK(^{ if (completion) completion(cached, nil); });
        return;
    }
    id<SPMusicDataSource> currentSource = self.source;
    __weak typeof(self) weakSelf = self;
    [currentSource fetchLyricsForTrack:track completion:^(SPLyricDocument *lyrics, NSError *error) {
        SP_MAIN_WORK(^{
            if (weakSelf.source != currentSource) return;
            if (!error && lyrics) {
                [weakSelf.lyricsCache setObject:lyrics forKey:trackId];
            }
            if (completion) completion(lyrics, error);
        });
    }];
}

@end
