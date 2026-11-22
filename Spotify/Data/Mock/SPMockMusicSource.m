//
//  SPMockMusicSource.m
//  Spotify
//

#import "SPMockMusicSource.h"
#import <YYModel/YYModel.h>

@interface SPMockMusicSource ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, copy) NSDictionary<NSString *, SPPlaylist *> *playlists;
@property (nonatomic, copy) NSDictionary<NSString *, SPAlbum *> *albums;
@property (nonatomic, copy) NSDictionary<NSString *, SPArtist *> *artists;
@property (nonatomic, copy) NSArray<SPTrack *> *allTracks;
@property (nonatomic, copy) NSArray<SPHomeSection *> *homeSections;
@property (nonatomic, copy) NSArray<id<SPMediaItem>> *libraryItems;
@property (nonatomic, copy) NSArray<SPSearchCategory *> *categories;
@end

@implementation SPMockMusicSource

- (instancetype)init {
    if (self = [super init]) {
        _queue = dispatch_queue_create("com.dyyxs.spotify.mock", DISPATCH_QUEUE_SERIAL);
        _simulatedLatency = 0.4;
    }
    return self;
}

- (NSString *)sourceName { return @"Mock"; }

#pragma mark - Loading

/// 在串行队列上懒加载并解析 JSON，然后延迟回调模拟网络
- (void)performWithLatency:(NSTimeInterval)latency work:(void (^)(void))work {
    dispatch_async(self.queue, ^{
        [self loadIfNeeded];
        if (latency <= 0) {
            work();
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(latency * NSEC_PER_SEC)), self.queue, work);
        }
    });
}

- (void)perform:(void (^)(void))work {
    [self performWithLatency:self.simulatedLatency work:work];
}

- (void)loadIfNeeded {
    if (self.loaded) return;
    self.loaded = YES;

    NSString *path = [[NSBundle mainBundle] pathForResource:@"mock_data" ofType:@"json"];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:NSDictionary.class]) {
        NSLog(@"[Mock] mock_data.json 加载失败");
        return;
    }

    NSMutableDictionary *artists = [NSMutableDictionary dictionary];
    for (SPArtist *a in [NSArray yy_modelArrayWithClass:SPArtist.class json:json[@"artists"]]) artists[a.identifier] = a;

    NSMutableDictionary *albums = [NSMutableDictionary dictionary];
    NSMutableArray *tracks = [NSMutableArray array];
    for (SPAlbum *a in [NSArray yy_modelArrayWithClass:SPAlbum.class json:json[@"albums"]]) {
        albums[a.identifier] = a;
        [tracks addObjectsFromArray:a.tracks ?: @[]];
    }

    NSMutableDictionary *playlists = [NSMutableDictionary dictionary];
    for (SPPlaylist *p in [NSArray yy_modelArrayWithClass:SPPlaylist.class json:json[@"playlists"]]) playlists[p.identifier] = p;

    self.artists = artists;
    self.albums = albums;
    self.playlists = playlists;
    self.allTracks = tracks;

    NSMutableArray *sections = [NSMutableArray array];
    for (NSDictionary *s in json[@"home"]) {
        SPHomeSection *section = [SPHomeSection new];
        section.title = s[@"title"] ?: @"";
        NSString *style = s[@"style"];
        section.style = [style isEqualToString:@"shortcut"] ? SPHomeSectionStyleShortcut
                      : [style isEqualToString:@"artist"] ? SPHomeSectionStyleArtist : SPHomeSectionStyleCard;
        section.items = [self resolveRefs:s[@"items"]];
        [sections addObject:section];
    }
    self.homeSections = sections;
    self.libraryItems = [self resolveRefs:json[@"library"]];
    self.categories = [NSArray yy_modelArrayWithClass:SPSearchCategory.class json:json[@"categories"]];
}

- (NSArray<id<SPMediaItem>> *)resolveRefs:(NSArray<NSDictionary *> *)refs {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *ref in refs) {
        NSString *type = ref[@"type"], *identifier = ref[@"id"];
        id item = nil;
        if ([type isEqualToString:@"playlist"]) item = self.playlists[identifier];
        else if ([type isEqualToString:@"album"]) item = self.albums[identifier];
        else if ([type isEqualToString:@"artist"]) item = self.artists[identifier];
        if (item) [items addObject:item];
    }
    return items;
}

- (NSError *)notFoundError {
    return [NSError errorWithDomain:SPMusicErrorDomain code:SPMusicErrorNotFound
                           userInfo:@{NSLocalizedDescriptionKey: @"内容不存在"}];
}

#pragma mark - SPMusicDataSource

- (void)fetchHomeSectionsWithCompletion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    [self fetchHomeSectionsForCategory:SPHomeCategoryAll completion:completion];
}

- (void)fetchHomeSectionsForCategory:(SPHomeCategory)category
                          completion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    [self perform:^{
        if (category == SPHomeCategoryAll) {
            completion(self.homeSections, nil);
            return;
        }
        NSMutableArray<SPHomeSection *> *result = [NSMutableArray array];
        if (category == SPHomeCategoryMusic) {
            if (self.albums.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"新碟首发";
                sec.style = SPHomeSectionStyleCard;
                sec.items = [self.albums.allValues subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, self.albums.count))];
                [result addObject:sec];
            }
            if (self.artists.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"实力音乐人";
                sec.style = SPHomeSectionStyleArtist;
                sec.items = self.artists.allValues;
                [result addObject:sec];
            }
            if (self.playlists.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"精选音乐歌单";
                sec.style = SPHomeSectionStyleCard;
                sec.items = [self.playlists.allValues subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, self.playlists.count))];
                [result addObject:sec];
            }
        } else {
            NSArray<SPPlaylist *> *radios = [self mockPodcastRadios];
            if (radios.count > 0) {
                SPHomeSection *s1 = [SPHomeSection new];
                s1.title = @"热门播客电台";
                s1.style = SPHomeSectionStyleCard;
                s1.items = radios;
                [result addObject:s1];
            }
        }
        completion(result, nil);
    }];
}

- (NSArray<SPPlaylist *> *)mockPodcastRadios {
    NSMutableArray<SPPlaylist *> *list = [NSMutableArray array];
    NSArray<SPPlaylist *> *base = self.playlists.allValues;
    for (NSUInteger i = 0; i < MIN((NSUInteger)4, base.count); i++) {
        SPPlaylist *src = base[i];
        SPPlaylist *radio = [SPPlaylist new];
        radio.identifier = [@"dj:mock_" stringByAppendingString:src.identifier];
        radio.name = [NSString stringWithFormat:@"音乐随谈 · %@", src.name];
        radio.creatorName = @"声音电台主播";
        radio.coverURL = src.coverURL;
        radio.colorHex = src.colorHex;
        radio.desc = src.desc;
        radio.tracks = src.tracks;
        [list addObject:radio];
    }
    return list;
}

- (void)fetchHomeMoreSectionsForPage:(NSInteger)page
                          completion:(void (^)(NSArray<SPHomeSection *> *, BOOL, NSError *))completion {
    [self fetchHomeMoreSectionsForCategory:SPHomeCategoryAll page:page completion:completion];
}

- (void)fetchHomeMoreSectionsForCategory:(SPHomeCategory)category
                                    page:(NSInteger)page
                              completion:(void (^)(NSArray<SPHomeSection *> *, BOOL, NSError *))completion {
    [self performWithLatency:0.25 work:^{
        if (category == SPHomeCategoryPodcast || page < 1 || page > 2) {
            completion(@[], NO, nil);
            return;
        }
        NSArray<SPPlaylist *> *pls = self.playlists.allValues;
        NSArray<SPAlbum *> *als = self.albums.allValues;
        NSMutableArray<SPHomeSection *> *extra = [NSMutableArray array];

        if (page == 1) {
            if (pls.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"编辑严选歌单";
                sec.style = SPHomeSectionStyleCard;
                sec.items = [pls subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)6, pls.count))];
                [extra addObject:sec];
            }
            if (als.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"新专辑风向标";
                sec.style = SPHomeSectionStyleCard;
                sec.items = [als subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)6, als.count))];
                [extra addObject:sec];
            }
        } else if (page == 2) {
            NSArray<SPArtist *> *ars = self.artists.allValues;
            if (ars.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"更多音乐人";
                sec.style = SPHomeSectionStyleArtist;
                sec.items = ars;
                [extra addObject:sec];
            }
        }
        completion(extra, page < 2, nil);
    }];
}

- (void)fetchSearchCategoriesWithCompletion:(void (^)(NSArray<SPSearchCategory *> *, NSError *))completion {
    [self perform:^{ completion(self.categories, nil); }];
}

- (void)searchWithKeyword:(NSString *)keyword completion:(void (^)(SPSearchResult *, NSError *))completion {
    [self performWithLatency:0.06 work:^{
        NSString *kw = [keyword stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        SPSearchResult *result = [SPSearchResult new];
        result.keyword = kw;
        if (kw.length == 0) { completion(result, nil); return; }

        BOOL (^match)(NSString *) = ^BOOL(NSString *text) {
            return [text rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound;
        };
        result.tracks = [self.allTracks filteredArrayUsingPredicate:
                         [NSPredicate predicateWithBlock:^BOOL(SPTrack *t, id _) {
            return match(t.name) || match(t.artistNames) || match(t.album.name ?: @"");
        }]];
        result.artists = [self.artists.allValues filteredArrayUsingPredicate:
                          [NSPredicate predicateWithBlock:^BOOL(SPArtist *a, id _) { return match(a.name); }]];
        result.albums = [self.albums.allValues filteredArrayUsingPredicate:
                         [NSPredicate predicateWithBlock:^BOOL(SPAlbum *a, id _) {
            return match(a.name) || match(a.artistNames);
        }]];
        result.playlists = [self.playlists.allValues filteredArrayUsingPredicate:
                            [NSPredicate predicateWithBlock:^BOOL(SPPlaylist *p, id _) {
            return !p.isLikedSongs && (match(p.name) || match(p.desc ?: @""));
        }]];

        // 若搜索词匹配某个分类名但字面未命中，为该分类映射一组确定性精选曲目与歌单
        if (result.isEmpty && self.allTracks.count > 0) {
            NSUInteger catIdx = [self.categories indexOfObjectPassingTest:^BOOL(SPSearchCategory *cat, NSUInteger idx, BOOL *stop) {
                return [cat.name caseInsensitiveCompare:kw] == NSOrderedSame;
            }];
            if (catIdx != NSNotFound) {
                NSUInteger count = MIN((NSUInteger)10, self.allTracks.count);
                NSUInteger start = (catIdx * 4) % self.allTracks.count;
                NSMutableArray<SPTrack *> *picked = [NSMutableArray arrayWithCapacity:count];
                for (NSUInteger i = 0; i < count; i++) {
                    [picked addObject:self.allTracks[(start + i) % self.allTracks.count]];
                }
                result.tracks = picked;
                NSArray<SPPlaylist *> *nonLiked = [self.playlists.allValues filteredArrayUsingPredicate:
                                                   [NSPredicate predicateWithBlock:^BOOL(SPPlaylist *p, id _) { return !p.isLikedSongs; }]];
                if (nonLiked.count > 0) {
                    result.playlists = @[nonLiked[catIdx % nonLiked.count]];
                }
            }
        }
        completion(result, nil);
    }];
}

- (void)fetchPlaylistWithId:(NSString *)playlistId completion:(void (^)(SPPlaylist *, NSError *))completion {
    [self perform:^{
        if ([playlistId hasPrefix:@"dj:mock_"]) {
            NSString *raw = [playlistId substringFromIndex:8];
            SPPlaylist *src = self.playlists[raw];
            if (src) {
                SPPlaylist *radio = [SPPlaylist new];
                radio.identifier = playlistId;
                radio.name = [NSString stringWithFormat:@"音乐随谈 · %@", src.name];
                radio.creatorName = @"声音电台主播";
                radio.coverURL = src.coverURL;
                radio.colorHex = src.colorHex;
                radio.desc = src.desc;
                radio.tracks = src.tracks;
                completion(radio, nil);
                return;
            }
        }
        SPPlaylist *p = self.playlists[playlistId];
        completion(p, p ? nil : [self notFoundError]);
    }];
}

- (void)fetchAlbumWithId:(NSString *)albumId completion:(void (^)(SPAlbum *, NSError *))completion {
    [self perform:^{
        SPAlbum *a = self.albums[albumId];
        completion(a, a ? nil : [self notFoundError]);
    }];
}

- (void)fetchArtistTopTracksWithId:(NSString *)artistId
                        completion:(void (^)(SPArtist * _Nullable, NSArray<SPTrack *> * _Nullable, NSError * _Nullable))completion {
    [self perform:^{
        SPArtist *artist = self.artists[artistId];
        NSMutableArray<SPTrack *> *matched = [NSMutableArray array];
        for (SPTrack *track in self.allTracks) {
            for (SPArtist *ar in track.artists) {
                if ([ar.identifier isEqualToString:artistId] || (artist.name.length > 0 && [ar.name isEqualToString:artist.name])) {
                    [matched addObject:track];
                    break;
                }
            }
        }
        if (matched.count == 0 && self.allTracks.count > 0) {
            NSRange range = NSMakeRange(0, MIN((NSUInteger)10, self.allTracks.count));
            [matched addObjectsFromArray:[self.allTracks subarrayWithRange:range]];
        }
        completion(artist, matched, (artist || matched.count > 0) ? nil : [self notFoundError]);
    }];
}

- (void)fetchLibraryItemsWithCompletion:(void (^)(NSArray<id<SPMediaItem>> *, NSError *))completion {
    [self perform:^{ completion(self.libraryItems, nil); }];
}

- (void)fetchPlayURLForTrack:(SPTrack *)track completion:(void (^)(NSURL *, NSError *))completion {
    // mock 数据直接携带 audioURL，无需延迟
    dispatch_async(self.queue, ^{
        NSURL *url = track.audioURL.length ? [NSURL URLWithString:track.audioURL] : nil;
        completion(url, url ? nil : [NSError errorWithDomain:SPMusicErrorDomain code:SPMusicErrorNoCopyright
                                                   userInfo:@{NSLocalizedDescriptionKey: @"暂无播放地址"}]);
    });
}

- (void)fetchLyricsForTrack:(SPTrack *)track completion:(void (^)(SPLyricDocument *, NSError *))completion {
    [self performWithLatency:0.10 work:^{
        NSString *sampleLRC = [NSString stringWithFormat:
                               @"[00:00.00]%@\n"
                               "[00:04.00]深夜电台传来温柔的旋律\n"
                               "[00:09.00]耳机里的风声吹散了疲惫\n"
                               "[00:15.00]此刻只有节拍和星光作伴\n"
                               "[00:22.00]让这首歌带你进入专属梦境\n",
                               track.name ?: @"正在播放"];
        NSString *sampleTrans = @"[00:04.00]Soft melodies arrive from midnight radio\n"
                                 "[00:09.00]Breeze in headphones fades away fatigue\n"
                                 "[00:15.00]Only rhythm and starlight accompany tonight\n"
                                 "[00:22.00]Let this track carry you into your dream\n";
        SPLyricDocument *doc = [SPLyricDocument parseLRC:sampleLRC translationLRC:sampleTrans];
        completion(doc, nil);
    }];
}

@end
