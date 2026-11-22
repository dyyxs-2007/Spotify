//
//  SPNeteaseMusicSource.m
//  Spotify
//

#import "SPNeteaseMusicSource.h"
#import "SPHTTPClient.h"
#import "SPNeteaseSession.h"
#import "SPNeteaseParser.h"

@interface SPNeteaseMusicSource ()
@property (nonatomic, strong) SPHTTPClient *client;
@end

@implementation SPNeteaseMusicSource

- (instancetype)init {
    return [self initWithBaseURLString:[SPNeteaseSession baseURLString]];
}

- (instancetype)initWithBaseURLString:(NSString *)baseURLString {
    if (self = [super init]) {
        NSURL *url = [NSURL URLWithString:baseURLString] ?: [NSURL URLWithString:SPNeteaseDefaultBaseURL];
        _client = [[SPHTTPClient alloc] initWithBaseURL:url];
    }
    return self;
}

- (NSString *)sourceName {
    return [NSString stringWithFormat:@"网易云音乐 API (%@)", self.client.baseURL.host ?: @"msapi.awup.cn"];
}

- (NSError *)musicErrorFrom:(nullable NSError *)error fallbackCode:(SPMusicErrorCode)code fallbackMessage:(NSString *)message {
    if (!error) {
        return [NSError errorWithDomain:SPMusicErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return [NSError errorWithDomain:SPMusicErrorDomain
                               code:(error.code == 451 ? SPMusicErrorNoCopyright : code)
                           userInfo:@{NSLocalizedDescriptionKey: error.localizedDescription ?: message}];
}

#pragma mark - Home Sections

- (void)fetchHomeSectionsWithCompletion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    [self fetchHomeSectionsForCategory:SPHomeCategoryAll completion:completion];
}

- (void)fetchHomeSectionsForCategory:(SPHomeCategory)category
                          completion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    if (category == SPHomeCategoryMusic) {
        [self fetchMusicHomeSectionsWithCompletion:completion];
        return;
    }
    if (category == SPHomeCategoryPodcast) {
        [self fetchPodcastHomeSectionsWithCompletion:completion];
        return;
    }
    [self fetchAllHomeSectionsWithCompletion:completion];
}

- (void)fetchAllHomeSectionsWithCompletion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        dispatch_group_t group = dispatch_group_create();
        __block NSArray<SPPlaylist *> *toplists = @[];
        __block NSArray<SPPlaylist *> *personalized = @[];
        __block NSArray<SPPlaylist *> *hotPlaylists = @[];
        __block NSArray<SPPlaylist *> *podcasts = @[];
        __block NSArray<SPAlbum *> *newestAlbums = @[];
        __block NSArray<SPArtist *> *topArtists = @[];
        __block NSError *lastError = nil;

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/toplist" parameters:nil cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) toplists = [SPNeteaseParser playlistsFromArray:json[@"list"]];
            else lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/personalized" parameters:@{@"limit": @14} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) personalized = [SPNeteaseParser playlistsFromArray:json[@"result"]];
            else lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/dj/hot" parameters:@{@"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) podcasts = [SPNeteaseParser podcastRadiosFromArray:json[@"djRadios"]];
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/top/playlist" parameters:@{@"order": @"hot", @"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) hotPlaylists = [SPNeteaseParser playlistsFromArray:json[@"playlists"]];
            else lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/album/newest" parameters:nil cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) newestAlbums = [SPNeteaseParser albumsFromArray:json[@"albums"]];
            else lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/top/artists" parameters:@{@"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) topArtists = [SPNeteaseParser artistsFromArray:json[@"artists"]];
            else lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<SPHomeSection *> *sections = [NSMutableArray array];

            NSMutableArray<id<SPMediaItem>> *shortcuts = [NSMutableArray array];
            NSUInteger topLimit = MIN((NSUInteger)4, toplists.count);
            for (NSUInteger i = 0; i < topLimit; i++) [shortcuts addObject:toplists[i]];
            NSUInteger persHead = MIN((NSUInteger)4, personalized.count);
            for (NSUInteger i = 0; i < persHead && shortcuts.count < 8; i++) [shortcuts addObject:personalized[i]];
            if (shortcuts.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"";
                sec.style = SPHomeSectionStyleShortcut;
                sec.items = shortcuts;
                [sections addObject:sec];
            }

            if (personalized.count > persHead) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"为你推荐";
                sec.style = SPHomeSectionStyleCard;
                sec.items = [personalized subarrayWithRange:NSMakeRange(persHead, MIN((NSUInteger)10, personalized.count - persHead))];
                [sections addObject:sec];
            }

            if (podcasts.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"精选播客电台";
                sec.style = SPHomeSectionStyleCard;
                sec.items = podcasts;
                [sections addObject:sec];
            }

            if (hotPlaylists.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"热门精选歌单";
                sec.style = SPHomeSectionStyleCard;
                sec.items = hotPlaylists;
                [sections addObject:sec];
            }

            if (newestAlbums.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"最新发行专辑";
                sec.style = SPHomeSectionStyleCard;
                sec.items = [newestAlbums subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)10, newestAlbums.count))];
                [sections addObject:sec];
            }

            if (topArtists.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"热门艺人";
                sec.style = SPHomeSectionStyleArtist;
                sec.items = topArtists;
                [sections addObject:sec];
            }

            if (sections.count == 0) {
                completion(nil, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNetwork fallbackMessage:@"加载网易云首页失败"]);
            } else {
                completion(sections, nil);
            }
        });
    }];
}

- (void)fetchMusicHomeSectionsWithCompletion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        dispatch_group_t group = dispatch_group_create();
        __block NSArray<SPPlaylist *> *hqPlaylists = @[];
        __block NSArray<SPAlbum *> *newAlbums = @[];
        __block NSArray<SPPlaylist *> *cnPlaylists = @[];
        __block NSArray<SPArtist *> *musicArtists = @[];
        __block NSArray<SPPlaylist *> *westernPlaylists = @[];
        __block NSArray<SPPlaylist *> *rockPlaylists = @[];
        __block NSError *lastError = nil;

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/top/playlist/highquality" parameters:@{@"limit": @6} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) hqPlaylists = [SPNeteaseParser playlistsFromArray:json[@"playlists"]];
            else lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/album/new" parameters:@{@"area": @"ALL", @"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) newAlbums = [SPNeteaseParser albumsFromArray:json[@"albums"]];
            else if (!lastError) lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/top/playlist" parameters:@{@"cat": @"华语", @"order": @"hot", @"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) cnPlaylists = [SPNeteaseParser playlistsFromArray:json[@"playlists"]];
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/top/artists" parameters:@{@"limit": @10, @"offset": @6} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) musicArtists = [SPNeteaseParser artistsFromArray:json[@"artists"]];
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/top/playlist" parameters:@{@"cat": @"欧美", @"order": @"hot", @"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) westernPlaylists = [SPNeteaseParser playlistsFromArray:json[@"playlists"]];
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/top/playlist" parameters:@{@"cat": @"摇滚", @"order": @"hot", @"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) rockPlaylists = [SPNeteaseParser playlistsFromArray:json[@"playlists"]];
            dispatch_group_leave(group);
        }];

        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<SPHomeSection *> *sections = [NSMutableArray array];
            if (hqPlaylists.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"";
                sec.style = SPHomeSectionStyleShortcut;
                sec.items = hqPlaylists;
                [sections addObject:sec];
            }
            if (newAlbums.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"新碟首发";
                sec.style = SPHomeSectionStyleCard;
                sec.items = newAlbums;
                [sections addObject:sec];
            }
            if (cnPlaylists.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"华语精选歌单";
                sec.style = SPHomeSectionStyleCard;
                sec.items = cnPlaylists;
                [sections addObject:sec];
            }
            if (musicArtists.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"实力音乐人";
                sec.style = SPHomeSectionStyleArtist;
                sec.items = musicArtists;
                [sections addObject:sec];
            }
            if (westernPlaylists.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"欧美流行热榜";
                sec.style = SPHomeSectionStyleCard;
                sec.items = westernPlaylists;
                [sections addObject:sec];
            }
            if (rockPlaylists.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"摇滚与现场";
                sec.style = SPHomeSectionStyleCard;
                sec.items = rockPlaylists;
                [sections addObject:sec];
            }
            if (sections.count == 0) {
                completion(nil, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNetwork fallbackMessage:@"加载音乐专区失败"]);
            } else {
                completion(sections, nil);
            }
        });
    }];
}

- (void)fetchPodcastHomeSectionsWithCompletion:(void (^)(NSArray<SPHomeSection *> *, NSError *))completion {
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        dispatch_group_t group = dispatch_group_create();
        __block NSArray<SPPlaylist *> *hotHead = @[];
        __block NSArray<SPPlaylist *> *toplistRadios = @[];
        __block NSArray<SPPlaylist *> *personalizedRadios = @[];
        __block NSArray<SPPlaylist *> *editorRadios = @[];
        __block NSArray<SPPlaylist *> *moreHotRadios = @[];
        __block NSError *lastError = nil;

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/dj/hot" parameters:@{@"limit": @6} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) hotHead = [SPNeteaseParser podcastRadiosFromArray:json[@"djRadios"]];
            else lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/dj/toplist" parameters:@{@"type": @"hot", @"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) toplistRadios = [SPNeteaseParser podcastRadiosFromArray:json[@"toplist"]];
            else if (!lastError) lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/dj/personalize/recommend" parameters:@{@"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) personalizedRadios = [SPNeteaseParser podcastRadiosFromArray:json[@"data"]];
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/dj/recommend" parameters:nil cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) editorRadios = [SPNeteaseParser podcastRadiosFromArray:json[@"djRadios"]];
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/dj/hot" parameters:@{@"limit": @10, @"offset": @6} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) moreHotRadios = [SPNeteaseParser podcastRadiosFromArray:json[@"djRadios"]];
            dispatch_group_leave(group);
        }];

        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<SPHomeSection *> *sections = [NSMutableArray array];
            if (hotHead.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"";
                sec.style = SPHomeSectionStyleShortcut;
                sec.items = hotHead;
                [sections addObject:sec];
            }
            if (toplistRadios.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"热门播客榜";
                sec.style = SPHomeSectionStyleCard;
                sec.items = toplistRadios;
                [sections addObject:sec];
            }
            if (personalizedRadios.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"个性播客推荐";
                sec.style = SPHomeSectionStyleCard;
                sec.items = personalizedRadios;
                [sections addObject:sec];
            }
            if (editorRadios.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"编辑严选电台";
                sec.style = SPHomeSectionStyleCard;
                sec.items = editorRadios;
                [sections addObject:sec];
            }
            if (moreHotRadios.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = @"人气声音电台";
                sec.style = SPHomeSectionStyleCard;
                sec.items = moreHotRadios;
                [sections addObject:sec];
            }
            if (sections.count == 0) {
                completion(nil, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNetwork fallbackMessage:@"加载播客电台失败"]);
            } else {
                completion(sections, nil);
            }
        });
    }];
}

- (void)fetchHomeMoreSectionsForPage:(NSInteger)page
                          completion:(void (^)(NSArray<SPHomeSection *> *, BOOL, NSError *))completion {
    [self fetchHomeMoreSectionsForCategory:SPHomeCategoryAll page:page completion:completion];
}

- (void)fetchHomeMoreSectionsForCategory:(SPHomeCategory)category
                                    page:(NSInteger)page
                              completion:(void (^)(NSArray<SPHomeSection *> *, BOOL, NSError *))completion {
    if (category == SPHomeCategoryPodcast) {
        [self fetchPodcastMoreSectionsForPage:page completion:completion];
        return;
    }
    if (category == SPHomeCategoryMusic) {
        [self fetchMusicMoreSectionsForPage:page completion:completion];
        return;
    }
    if (page < 1 || page > 6) {
        completion(@[], NO, nil);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        dispatch_group_t group = dispatch_group_create();
        NSMutableArray<SPHomeSection *> *slots = [NSMutableArray arrayWithObjects:NSNull.null, NSNull.null, NSNull.null, nil];
        __block NSError *lastError = nil;

        void (^loadPlaylistCat)(NSInteger, NSString *, NSString *) = ^(NSInteger idx, NSString *title, NSString *cat) {
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/top/playlist"
                      parameters:@{@"cat": cat, @"order": @"hot", @"limit": @10}
                          cookie:cookie
                     bypassCache:NO
                      completion:^(NSDictionary *json, NSError *err) {
                NSArray<SPPlaylist *> *pls = [SPNeteaseParser playlistsFromArray:json[@"playlists"]];
                if (pls.count > 0) {
                    SPHomeSection *sec = [SPHomeSection new];
                    sec.title = title;
                    sec.style = SPHomeSectionStyleCard;
                    sec.items = pls;
                    @synchronized (slots) { slots[idx] = sec; }
                } else if (err) {
                    lastError = err;
                }
                dispatch_group_leave(group);
            }];
        };

        if (page == 1) {
            loadPlaylistCat(0, @"华语金曲精选", @"华语");
            loadPlaylistCat(1, @"流行风向标", @"流行");
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/toplist" parameters:nil cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                NSArray<SPPlaylist *> *tops = [SPNeteaseParser playlistsFromArray:json[@"list"]];
                if (tops.count > 4) {
                    NSRange range = NSMakeRange(4, MIN((NSUInteger)10, tops.count - 4));
                    SPHomeSection *sec = [SPHomeSection new];
                    sec.title = @"官方热门榜单";
                    sec.style = SPHomeSectionStyleCard;
                    sec.items = [tops subarrayWithRange:range];
                    @synchronized (slots) { slots[2] = sec; }
                } else if (err) {
                    lastError = err;
                }
                dispatch_group_leave(group);
            }];
        } else if (page == 2) {
            loadPlaylistCat(0, @"摇滚与现场能量", @"摇滚");
            loadPlaylistCat(1, @"民谣与温柔时刻", @"民谣");
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/top/artists" parameters:@{@"limit": @10, @"offset": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                NSArray<SPArtist *> *artists = [SPNeteaseParser artistsFromArray:json[@"artists"]];
                if (artists.count > 0) {
                    SPHomeSection *sec = [SPHomeSection new];
                    sec.title = @"更多实力艺人";
                    sec.style = SPHomeSectionStyleArtist;
                    sec.items = artists;
                    @synchronized (slots) { slots[2] = sec; }
                } else if (err) {
                    lastError = err;
                }
                dispatch_group_leave(group);
            }];
        } else if (page == 3) {
            loadPlaylistCat(0, @"电子节拍空间", @"电子");
            loadPlaylistCat(1, @"轻音乐与专注", @"轻音乐");
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/album/new" parameters:@{@"limit": @10, @"offset": @0} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                NSArray<SPAlbum *> *albums = [SPNeteaseParser albumsFromArray:json[@"albums"]];
                if (albums.count > 0) {
                    SPHomeSection *sec = [SPHomeSection new];
                    sec.title = @"新碟上架速递";
                    sec.style = SPHomeSectionStyleCard;
                    sec.items = albums;
                    @synchronized (slots) { slots[2] = sec; }
                } else if (err) {
                    lastError = err;
                }
                dispatch_group_leave(group);
            }];
        } else if (page == 4) {
            loadPlaylistCat(0, @"欧美流行精选", @"欧美");
            loadPlaylistCat(1, @"影视原声与配乐", @"影视原声");
            loadPlaylistCat(2, @"独立与另类声浪", @"另类/独立");
        } else if (page == 5) {
            loadPlaylistCat(0, @"ACG 与二次元", @"ACG");
            loadPlaylistCat(1, @"说唱与街头节拍", @"说唱");
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/top/artists" parameters:@{@"limit": @10, @"offset": @20} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                NSArray<SPArtist *> *artists = [SPNeteaseParser artistsFromArray:json[@"artists"]];
                if (artists.count > 0) {
                    SPHomeSection *sec = [SPHomeSection new];
                    sec.title = @"人气歌手榜";
                    sec.style = SPHomeSectionStyleArtist;
                    sec.items = artists;
                    @synchronized (slots) { slots[2] = sec; }
                } else if (err) {
                    lastError = err;
                }
                dispatch_group_leave(group);
            }];
        } else {
            loadPlaylistCat(0, @"治愈系歌单", @"治愈");
            loadPlaylistCat(1, @"夜晚与微醺", @"夜晚");
            loadPlaylistCat(2, @"运动与燃脂", @"运动");
        }

        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<SPHomeSection *> *result = [NSMutableArray array];
            for (id obj in slots) {
                if ([obj isKindOfClass:SPHomeSection.class]) {
                    [result addObject:(SPHomeSection *)obj];
                }
            }
            BOOL hasMore = (page < 6);
            if (result.count == 0 && lastError) {
                completion(nil, hasMore, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNetwork fallbackMessage:@"加载更多精选内容失败"]);
            } else {
                completion(result, hasMore, nil);
            }
        });
    }];
}

- (void)fetchMusicMoreSectionsForPage:(NSInteger)page
                           completion:(void (^)(NSArray<SPHomeSection *> *, BOOL, NSError *))completion {
    if (page < 1 || page > 4) {
        completion(@[], NO, nil);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        dispatch_group_t group = dispatch_group_create();
        NSMutableArray *slots = [NSMutableArray arrayWithObjects:NSNull.null, NSNull.null, nil];
        __block NSError *lastError = nil;

        void (^loadCat)(NSInteger, NSString *, NSString *) = ^(NSInteger idx, NSString *title, NSString *cat) {
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/top/playlist" parameters:@{@"cat": cat, @"order": @"hot", @"limit": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                NSArray<SPPlaylist *> *pls = [SPNeteaseParser playlistsFromArray:json[@"playlists"]];
                if (pls.count > 0) {
                    SPHomeSection *sec = [SPHomeSection new];
                    sec.title = title;
                    sec.style = SPHomeSectionStyleCard;
                    sec.items = pls;
                    @synchronized (slots) { slots[idx] = sec; }
                } else if (err) {
                    lastError = err;
                }
                dispatch_group_leave(group);
            }];
        };

        if (page == 1) {
            loadCat(0, @"民谣与木吉他", @"民谣");
            loadCat(1, @"电子节拍空间", @"电子");
        } else if (page == 2) {
            loadCat(0, @"说唱与节奏律动", @"说唱");
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/album/new" parameters:@{@"area": @"ALL", @"limit": @10, @"offset": @10} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                NSArray<SPAlbum *> *albums = [SPNeteaseParser albumsFromArray:json[@"albums"]];
                if (albums.count > 0) {
                    SPHomeSection *sec = [SPHomeSection new];
                    sec.title = @"全球新碟速递";
                    sec.style = SPHomeSectionStyleCard;
                    sec.items = albums;
                    @synchronized (slots) { slots[1] = sec; }
                }
                dispatch_group_leave(group);
            }];
        } else if (page == 3) {
            loadCat(0, @"古典与器乐演奏", @"古典");
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/top/artists" parameters:@{@"limit": @10, @"offset": @16} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                NSArray<SPArtist *> *artists = [SPNeteaseParser artistsFromArray:json[@"artists"]];
                if (artists.count > 0) {
                    SPHomeSection *sec = [SPHomeSection new];
                    sec.title = @"人气音乐人";
                    sec.style = SPHomeSectionStyleArtist;
                    sec.items = artists;
                    @synchronized (slots) { slots[1] = sec; }
                }
                dispatch_group_leave(group);
            }];
        } else {
            loadCat(0, @"轻音乐与放松", @"轻音乐");
            loadCat(1, @"古风国韵精选", @"古风");
        }

        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<SPHomeSection *> *result = [NSMutableArray array];
            for (id obj in slots) {
                if ([obj isKindOfClass:SPHomeSection.class]) [result addObject:(SPHomeSection *)obj];
            }
            BOOL hasMore = (page < 4);
            if (result.count == 0 && lastError) {
                completion(nil, hasMore, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNetwork fallbackMessage:@"加载更多音乐失败"]);
            } else {
                completion(result, hasMore, nil);
            }
        });
    }];
}

- (void)fetchPodcastMoreSectionsForPage:(NSInteger)page
                             completion:(void (^)(NSArray<SPHomeSection *> *, BOOL, NSError *))completion {
    if (page < 1 || page > 2) {
        completion(@[], NO, nil);
        return;
    }
    NSInteger offset = (page == 1) ? 16 : 26;
    NSString *title = (page == 1) ? @"深度播客探索" : @"更多精选电台";
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        [weakSelf.client GET:@"/dj/hot"
                  parameters:@{@"limit": @10, @"offset": @(offset)}
                      cookie:cookie
                 bypassCache:NO
                  completion:^(NSDictionary *json, NSError *err) {
            NSArray<SPPlaylist *> *radios = [SPNeteaseParser podcastRadiosFromArray:json[@"djRadios"]];
            BOOL hasMore = (page < 2 && radios.count > 0);
            if (radios.count > 0) {
                SPHomeSection *sec = [SPHomeSection new];
                sec.title = title;
                sec.style = SPHomeSectionStyleCard;
                sec.items = radios;
                completion(@[sec], hasMore, nil);
            } else if (err) {
                completion(nil, hasMore, [weakSelf musicErrorFrom:err fallbackCode:SPMusicErrorNetwork fallbackMessage:@"加载更多播客失败"]);
            } else {
                completion(@[], NO, nil);
            }
        }];
    }];
}

#pragma mark - Search Categories

- (void)fetchSearchCategoriesWithCompletion:(void (^)(NSArray<SPSearchCategory *> *, NSError *))completion {
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        dispatch_group_t group = dispatch_group_create();
        __block NSArray *rawTags = @[];
        __block NSMutableArray<NSString *> *covers = [NSMutableArray array];
        __block NSError *lastError = nil;

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/playlist/hot" parameters:nil cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) rawTags = [SPNeteaseParser arrayValue:json[@"tags"]] ?: @[];
            else lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/toplist" parameters:nil cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            NSArray<SPPlaylist *> *lists = [SPNeteaseParser playlistsFromArray:json[@"list"]];
            for (SPPlaylist *pl in lists) {
                if (pl.coverURL.length > 0) [covers addObject:pl.coverURL];
            }
            dispatch_group_leave(group);
        }];

        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray<SPSearchCategory *> *cats = [SPNeteaseParser categoriesFromHotTags:rawTags coverURLs:covers];
            if (cats.count == 0) {
                completion(nil, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNetwork fallbackMessage:@"加载分类失败"]);
            } else {
                completion(cats, nil);
            }
        });
    }];
}

#pragma mark - Search (1018 Comprehensive + Cloudsearch Fallback)

- (void)searchWithKeyword:(NSString *)keyword completion:(void (^)(SPSearchResult *, NSError *))completion {
    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        completion([SPSearchResult new], nil);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        [weakSelf.client GET:@"/search"
                  parameters:@{@"keywords": trimmed, @"type": @1018}
                      cookie:cookie
                 bypassCache:NO
                  completion:^(NSDictionary *json, NSError *error) {
            NSDictionary *res = [SPNeteaseParser dictValue:json[@"result"]];
            SPSearchResult *parsed = [SPSearchResult new];
            parsed.keyword = trimmed;

            NSDictionary *songBox = [SPNeteaseParser dictValue:res[@"song"]];
            NSDictionary *artistBox = [SPNeteaseParser dictValue:res[@"artist"]];
            NSDictionary *albumBox = [SPNeteaseParser dictValue:res[@"album"]];
            NSDictionary *plBox = [SPNeteaseParser dictValue:res[@"playList"]];

            parsed.tracks = [SPNeteaseParser tracksFromArray:songBox[@"songs"] fallbackAlbum:nil];
            parsed.artists = [SPNeteaseParser artistsFromArray:artistBox[@"artists"]];
            parsed.albums = [SPNeteaseParser albumsFromArray:albumBox[@"albums"]];
            parsed.playlists = [SPNeteaseParser playlistsFromArray:plBox[@"playLists"]];

            if (!error && !parsed.isEmpty) {
                completion(parsed, nil);
                return;
            }
            [weakSelf fallbackCloudSearchWithKeyword:trimmed cookie:cookie completion:completion];
        }];
    }];
}

- (void)fallbackCloudSearchWithKeyword:(NSString *)keyword
                                cookie:(nullable NSString *)cookie
                            completion:(void (^)(SPSearchResult *, NSError *))completion {
    dispatch_group_t group = dispatch_group_create();
    SPSearchResult *result = [SPSearchResult new];
    result.keyword = keyword;
    __block NSError *lastError = nil;

    dispatch_group_enter(group);
    [self.client GET:@"/cloudsearch" parameters:@{@"keywords": keyword, @"type": @1, @"limit": @20} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
        NSDictionary *r = [SPNeteaseParser dictValue:json[@"result"]];
        if (r) result.tracks = [SPNeteaseParser tracksFromArray:r[@"songs"] fallbackAlbum:nil];
        else lastError = err;
        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [self.client GET:@"/cloudsearch" parameters:@{@"keywords": keyword, @"type": @100, @"limit": @6} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
        NSDictionary *r = [SPNeteaseParser dictValue:json[@"result"]];
        if (r) result.artists = [SPNeteaseParser artistsFromArray:r[@"artists"]];
        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [self.client GET:@"/cloudsearch" parameters:@{@"keywords": keyword, @"type": @10, @"limit": @6} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
        NSDictionary *r = [SPNeteaseParser dictValue:json[@"result"]];
        if (r) result.albums = [SPNeteaseParser albumsFromArray:r[@"albums"]];
        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [self.client GET:@"/cloudsearch" parameters:@{@"keywords": keyword, @"type": @1000, @"limit": @8} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
        NSDictionary *r = [SPNeteaseParser dictValue:json[@"result"]];
        if (r) result.playlists = [SPNeteaseParser playlistsFromArray:r[@"playlists"]];
        dispatch_group_leave(group);
    }];

    __weak typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (result.isEmpty && lastError) {
            completion(nil, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNetwork fallbackMessage:@"搜索失败"]);
        } else {
            completion(result, nil);
        }
    });
}

#pragma mark - Playlist / Album / Artist Detail

- (void)fetchPlaylistWithId:(NSString *)playlistId completion:(void (^)(SPPlaylist *, NSError *))completion {
    if (playlistId.length == 0) {
        completion(nil, [self musicErrorFrom:nil fallbackCode:SPMusicErrorNotFound fallbackMessage:@"歌单 ID 无效"]);
        return;
    }
    if ([playlistId hasPrefix:@"dj:"]) {
        [self fetchPodcastRadioWithId:[playlistId substringFromIndex:3] completion:completion];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        dispatch_group_t group = dispatch_group_create();
        __block SPPlaylist *detailPl = nil;
        __block NSArray<SPTrack *> *fullTracks = @[];
        __block NSError *lastError = nil;

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/playlist/detail" parameters:@{@"id": playlistId} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            detailPl = [SPNeteaseParser playlistFromJSON:[SPNeteaseParser dictValue:json[@"playlist"]]];
            if (!detailPl && err) lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/playlist/track/all" parameters:@{@"id": playlistId, @"limit": @50, @"offset": @0} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) {
                fullTracks = [SPNeteaseParser tracksFromArray:json[@"songs"] fallbackAlbum:nil];
            } else if (err && !lastError) {
                lastError = err;
            }
            dispatch_group_leave(group);
        }];

        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (!detailPl && fullTracks.count > 0) {
                detailPl = [SPPlaylist new];
                detailPl.identifier = playlistId;
                detailPl.name = @"歌单";
            }
            if (!detailPl) {
                completion(nil, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNotFound fallbackMessage:@"歌单加载失败"]);
                return;
            }
            if (fullTracks.count > 0) {
                detailPl.tracks = fullTracks;
            }
            completion(detailPl, nil);
        });
    }];
}

- (void)fetchPodcastRadioWithId:(NSString *)radioId completion:(void (^)(SPPlaylist *, NSError *))completion {
    if (radioId.length == 0) {
        completion(nil, [self musicErrorFrom:nil fallbackCode:SPMusicErrorNotFound fallbackMessage:@"播客 ID 无效"]);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        dispatch_group_t group = dispatch_group_create();
        __block SPPlaylist *radio = nil;
        __block NSArray *rawPrograms = @[];
        __block NSError *lastError = nil;

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/dj/detail" parameters:@{@"rid": radioId} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            radio = [SPNeteaseParser podcastRadioFromJSON:[SPNeteaseParser dictValue:json[@"data"]]];
            if (!radio && err) lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/dj/program" parameters:@{@"rid": radioId, @"limit": @30, @"offset": @0} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            NSArray *arr = [SPNeteaseParser arrayValue:json[@"programs"]];
            if (arr) rawPrograms = arr;
            else if (err && !lastError) lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (!radio && rawPrograms.count > 0) {
                NSDictionary *firstProg = [SPNeteaseParser dictValue:rawPrograms.firstObject];
                radio = [SPNeteaseParser podcastRadioFromJSON:[SPNeteaseParser dictValue:firstProg[@"radio"]]];
                if (!radio) {
                    radio = [SPPlaylist new];
                    radio.identifier = [@"dj:" stringByAppendingString:radioId];
                    radio.name = @"精选播客";
                }
            }
            if (!radio) {
                completion(nil, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNotFound fallbackMessage:@"播客加载失败"]);
                return;
            }
            radio.tracks = [SPNeteaseParser podcastEpisodesFromArray:rawPrograms fallbackRadio:radio];
            completion(radio, nil);
        });
    }];
}

- (void)fetchAlbumWithId:(NSString *)albumId completion:(void (^)(SPAlbum *, NSError *))completion {
    if (albumId.length == 0) {
        completion(nil, [self musicErrorFrom:nil fallbackCode:SPMusicErrorNotFound fallbackMessage:@"专辑 ID 无效"]);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        [weakSelf.client GET:@"/album" parameters:@{@"id": albumId} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            SPAlbum *album = [SPNeteaseParser albumFromJSON:[SPNeteaseParser dictValue:json[@"album"]]];
            if (!album) {
                completion(nil, [weakSelf musicErrorFrom:err fallbackCode:SPMusicErrorNotFound fallbackMessage:@"专辑加载失败"]);
                return;
            }
            album.tracks = [SPNeteaseParser tracksFromArray:json[@"songs"] fallbackAlbum:album];
            completion(album, nil);
        }];
    }];
}

- (void)fetchArtistTopTracksWithId:(NSString *)artistId
                        completion:(void (^)(SPArtist *, NSArray<SPTrack *> *, NSError *))completion {
    if (artistId.length == 0) {
        completion(nil, nil, [self musicErrorFrom:nil fallbackCode:SPMusicErrorNotFound fallbackMessage:@"艺人 ID 无效"]);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        [weakSelf.client GET:@"/artists" parameters:@{@"id": artistId} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            SPArtist *artist = [SPNeteaseParser artistFromJSON:[SPNeteaseParser dictValue:json[@"artist"]]];
            NSArray<SPTrack *> *tracks = [SPNeteaseParser tracksFromArray:json[@"hotSongs"] fallbackAlbum:nil];
            if (!artist && tracks.count == 0) {
                completion(nil, nil, [weakSelf musicErrorFrom:err fallbackCode:SPMusicErrorNotFound fallbackMessage:@"歌手详情加载失败"]);
                return;
            }
            completion(artist, tracks, nil);
        }];
    }];
}

#pragma mark - Library

- (void)fetchLibraryItemsWithCompletion:(void (^)(NSArray<id<SPMediaItem>> *, NSError *))completion {
    __weak typeof(self) weakSelf = self;
    SPNeteaseSession *session = [SPNeteaseSession shared];
    [session ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        dispatch_group_t group = dispatch_group_create();
        __block NSArray<SPPlaylist *> *playlists = @[];
        __block NSArray<SPPlaylist *> *extraPlaylists = @[];
        __block NSArray<SPAlbum *> *albums = @[];
        __block NSArray<SPArtist *> *artists = @[];
        __block NSError *lastError = nil;

        NSString *uid = session.userId;
        if (uid.length > 0 && session.userCookie.length > 0) {
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/user/playlist"
                      parameters:@{@"uid": uid, @"limit": @20}
                          cookie:session.userCookie
                     bypassCache:YES
                      completion:^(NSDictionary *json, NSError *err) {
                if (json) playlists = [SPNeteaseParser playlistsFromArray:json[@"playlist"]];
                else lastError = err;
                dispatch_group_leave(group);
            }];
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/top/playlist/highquality" parameters:@{@"limit": @6} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                if (json) extraPlaylists = [SPNeteaseParser playlistsFromArray:json[@"playlists"]];
                dispatch_group_leave(group);
            }];
        } else {
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/top/playlist/highquality" parameters:@{@"limit": @6} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                if (json) playlists = [SPNeteaseParser playlistsFromArray:json[@"playlists"]];
                else lastError = err;
                dispatch_group_leave(group);
            }];
            dispatch_group_enter(group);
            [weakSelf.client GET:@"/toplist" parameters:nil cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
                NSArray<SPPlaylist *> *tops = [SPNeteaseParser playlistsFromArray:json[@"list"]];
                if (tops.count > 0) {
                    extraPlaylists = [tops subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)4, tops.count))];
                }
                dispatch_group_leave(group);
            }];
        }

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/album/newest" parameters:nil cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            NSArray<SPAlbum *> *arr = [SPNeteaseParser albumsFromArray:json[@"albums"]];
            if (arr.count > 0) albums = [arr subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)6, arr.count))];
            else if (err && !lastError) lastError = err;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [weakSelf.client GET:@"/top/artists" parameters:@{@"limit": @6} cookie:cookie bypassCache:NO completion:^(NSDictionary *json, NSError *err) {
            if (json) artists = [SPNeteaseParser artistsFromArray:json[@"artists"]];
            dispatch_group_leave(group);
        }];

        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<id<SPMediaItem>> *merged = [NSMutableArray array];
            [merged addObjectsFromArray:playlists];
            [merged addObjectsFromArray:extraPlaylists];
            [merged addObjectsFromArray:albums];
            [merged addObjectsFromArray:artists];
            if (merged.count == 0) {
                completion(nil, [weakSelf musicErrorFrom:lastError fallbackCode:SPMusicErrorNetwork fallbackMessage:@"加载音乐库失败"]);
            } else {
                completion(merged, nil);
            }
        });
    }];
}

#pragma mark - Playable URL

- (void)fetchPlayURLForTrack:(SPTrack *)track completion:(void (^)(NSURL *, NSError *))completion {
    if (track.identifier.length == 0) {
        completion(nil, [self musicErrorFrom:nil fallbackCode:SPMusicErrorNoCopyright fallbackMessage:@"歌曲 ID 无效"]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        [weakSelf.client GET:@"/song/url/v1"
                  parameters:@{@"id": track.identifier, @"level": @"standard"}
                      cookie:cookie
                 bypassCache:YES
                  completion:^(NSDictionary *json, NSError *error) {
            NSURL *resolved = [weakSelf extractURLFromSongURLPayload:json];
            if (resolved) {
                completion(resolved, nil);
                return;
            }
            // 兜底请求旧版 /song/url
            [weakSelf.client GET:@"/song/url"
                      parameters:@{@"id": track.identifier, @"br": @320000}
                          cookie:cookie
                     bypassCache:YES
                      completion:^(NSDictionary *fallbackJson, NSError *fallbackErr) {
                NSURL *fallbackURL = [weakSelf extractURLFromSongURLPayload:fallbackJson];
                if (fallbackURL) {
                    completion(fallbackURL, nil);
                } else {
                    completion(nil, [weakSelf musicErrorFrom:(fallbackErr ?: error)
                                                fallbackCode:SPMusicErrorNoCopyright
                                             fallbackMessage:@"该歌曲暂无播放版权"]);
                }
            }];
        }];
    }];
}

- (nullable NSURL *)extractURLFromSongURLPayload:(nullable NSDictionary *)json {
    NSArray *data = [SPNeteaseParser arrayValue:json[@"data"]];
    NSDictionary *first = [SPNeteaseParser dictValue:data.firstObject];
    NSString *urlStr = [SPNeteaseParser stringValue:first[@"url"]];
    return urlStr.length > 0 ? [NSURL URLWithString:urlStr] : nil;
}

#pragma mark - Lyrics

- (void)fetchLyricsForTrack:(SPTrack *)track completion:(void (^)(SPLyricDocument *, NSError *))completion {
    if (track.identifier.length == 0) {
        completion([SPLyricDocument parseLRC:nil translationLRC:nil], nil);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[SPNeteaseSession shared] ensureCookieWithClient:self.client completion:^(NSString *cookie) {
        [weakSelf.client GET:@"/lyric"
                  parameters:@{@"id": track.identifier}
                      cookie:cookie
                 bypassCache:NO
                  completion:^(NSDictionary *json, NSError *error) {
            if (error || !json) {
                completion(nil, [weakSelf musicErrorFrom:error fallbackCode:SPMusicErrorNetwork fallbackMessage:@"加载歌词失败"]);
                return;
            }
            NSDictionary *lrcDict = [SPNeteaseParser dictValue:json[@"lrc"]];
            NSDictionary *tlyricDict = [SPNeteaseParser dictValue:json[@"tlyric"]];
            NSString *lrcText = [SPNeteaseParser stringValue:lrcDict[@"lyric"]];
            NSString *tlyricText = [SPNeteaseParser stringValue:tlyricDict[@"lyric"]];
            SPLyricDocument *doc = [SPLyricDocument parseLRC:lrcText translationLRC:tlyricText];
            if ([json[@"nolyric"] boolValue] && doc.lines.count == 0) {
                doc.isInstrumental = YES;
            }
            completion(doc, nil);
        }];
    }];
}

@end
