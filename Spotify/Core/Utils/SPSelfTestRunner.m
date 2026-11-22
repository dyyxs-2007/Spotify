//
//  SPSelfTestRunner.m
//  Spotify
//

#import "SPSelfTestRunner.h"
#import "SPRootViewController.h"
#import "SPMiniPlayerView.h"
#import "SPHomeViewController.h"
#import "SPSearchViewController.h"
#import "SPLibraryViewController.h"
#import "SPDetailViewController.h"
#import "SPNowPlayingViewController.h"
#import "SPCoverPreviewViewController.h"
#import "SPFullScreenLyricsViewController.h"
#import "SPLyricModel.h"
#import "SPNavigationController.h"
#import "SPOnboardingViewController.h"
#import "SPAuthWelcomeViewController.h"
#import "SPAuthViewController.h"
#import "SPNeteaseQRLoginViewController.h"
#import "SPNeteaseAuthProvider.h"
#import "SPActivityViewController.h"
#import "SPHistoryViewController.h"
#import "SPSettingsViewController.h"
#import "SPHaptics.h"
#import "SPLRUCache.h"
#import "SPPlayQueue.h"
#import "SPAudioCacheManager.h"
#import "SPMusicRepository.h"
#import "SPLibraryStore.h"
#import "SPNeteaseMusicSource.h"
#import "SPMockMusicSource.h"
#import "SPHistoryStore.h"
#import "SPAuthService.h"
#import "SPPlayerService.h"
#import "SPPlaylist.h"
#import "SPToast.h"
#import <MediaPlayer/MediaPlayer.h>

@implementation SPSelfTestRunner

+ (BOOL)shouldCaptureSnapshots {
    return [NSProcessInfo.processInfo.arguments containsObject:@"-SPCaptureSnapshots"];
}

+ (void)captureWindow:(UIWindow *)window named:(NSString *)name {
    if (![self shouldCaptureSnapshots] || !window) return;
    [window layoutIfNeeded];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    NSData *data = UIImagePNGRepresentation(image);
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [data writeToFile:[docs stringByAppendingPathComponent:name] atomically:YES];
}

+ (void)runWithRootViewController:(SPRootViewController *)rootVC
                       completion:(void (^)(BOOL, NSString *))completion {
    NSMutableArray<NSString *> *logs = [NSMutableArray array];
    __block NSInteger passCount = 0;
    __block NSInteger failCount = 0;

    void (^assertCheck)(BOOL, NSString *) = ^(BOOL cond, NSString *name) {
        if (cond) {
            passCount += 1;
            [logs addObject:[NSString stringWithFormat:@"[PASS] %@", name]];
        } else {
            failCount += 1;
            [logs addObject:[NSString stringWithFormat:@"[FAIL] %@", name]];
        }
    };

    // 1. SPLRUCache 算法测试
    {
        NSMutableArray *evicted = [NSMutableArray array];
        SPLRUCache<NSString *, NSString *> *lru = [[SPLRUCache alloc] initWithMaxCount:3];
        lru.evictionHandler = ^(NSString *key, NSString *obj) {
            [evicted addObject:key];
        };
        [lru setObject:@"1" forKey:@"a"];
        [lru setObject:@"2" forKey:@"b"];
        [lru setObject:@"3" forKey:@"c"];
        NSString *hitA = [lru objectForKey:@"a"];
        NSString *missZ = [lru objectForKey:@"z"];
        [lru setObject:@"4" forKey:@"d"];

        assertCheck([hitA isEqualToString:@"1"] && missZ == nil, @"SPLRUCache 读写与命中/未命中统计");
        assertCheck([evicted isEqualToArray:@[@"b"]], @"SPLRUCache 容量淘汰顺序 (淘汰 b)");
        assertCheck([[lru allKeysInMRUOrder] isEqualToArray:@[@"d", @"a", @"c"]], @"SPLRUCache MRU 顺序维护");
        assertCheck(lru.hitCount == 1 && lru.missCount == 1, @"SPLRUCache hitCount/missCount 精确计数");

        SPLRUCache<NSString *, NSNumber *> *costCache = [[SPLRUCache alloc] initWithMaxCount:10 maxCost:100];
        [costCache setObject:@1 forKey:@"k1" cost:60];
        [costCache setObject:@2 forKey:@"k2" cost:60];
        assertCheck(costCache.count == 1 && [costCache peekObjectForKey:@"k1"] == nil && costCache.totalCost == 60,
                    @"SPLRUCache maxCost 字节上限淘汰");
    }

    // 2. SPPlayQueue 测试
    {
        NSMutableArray<SPTrack *> *sample = [NSMutableArray array];
        for (int i = 1; i <= 5; i++) {
            SPTrack *t = [SPTrack new];
            t.identifier = [NSString stringWithFormat:@"q%d", i];
            t.name = [NSString stringWithFormat:@"Song %d", i];
            t.duration = 180;
            [sample addObject:t];
        }
        SPPlayQueue *queue = [SPPlayQueue new];
        [queue replaceWithTracks:sample startIndex:2];
        assertCheck([queue.currentTrack.identifier isEqualToString:@"q3"] &&
                    [queue.previousTrack.identifier isEqualToString:@"q2"] &&
                    [queue.nextTrack.identifier isEqualToString:@"q4"],
                    @"SPPlayQueue 初始索引与前后预读曲目定位");

        queue.shuffleEnabled = YES;
        assertCheck(queue.currentIndex == 0 && [queue.currentTrack.identifier isEqualToString:@"q3"] && queue.playOrderTracks.count == 5,
                    @"SPPlayQueue 开启随机保持当前歌曲在首位");

        queue.shuffleEnabled = NO;
        assertCheck(queue.currentIndex == 2 && [queue.currentTrack.identifier isEqualToString:@"q3"],
                    @"SPPlayQueue 关闭随机还原原始下标");

        SPTrack *inserted = [SPTrack new];
        inserted.identifier = @"q99";
        inserted.name = @"Inserted";
        [queue insertNextTrack:inserted];
        assertCheck([queue.upNextTracks.firstObject.identifier isEqualToString:@"q99"],
                    @"SPPlayQueue 下一首插队逻辑");

        SPLyricDocument *sampleLRC = [SPLyricDocument parseLRC:@"[00:12.00][01:24.50]Chorus line\n[00:18.500]Second line\n"
                                                translationLRC:@"[00:12.00]副歌句\n[00:18.50]第二句\n"];
        assertCheck(sampleLRC.isSynced && sampleLRC.lines.count == 3 && sampleLRC.hasTranslation
                    && [sampleLRC.lines[1].translation isEqualToString:@"第二句"]
                    && [sampleLRC activeLineIndexForTime:19.0] == 1,
                    @"SPLyricDocument LRC 多时间轴解析、双语合并与实时索引正确");
    }

    // 3. 认证与 Keychain 闭环测试
    [self runAuthTestWithAssert:assertCheck completion:^{
        // 4. 阶段四真实网易云 API 全链路 + 三级 LRU 缓存 + 预加载秒切 + 热切换验证
        SPMusicRepository *repo = [SPMusicRepository shared];
        BOOL isNetease = [repo.source isKindOfClass:SPNeteaseMusicSource.class];
        assertCheck(isNetease, @"默认数据源已切换为真实网易云音乐 API");
        if (!isNetease) {
            repo.source = [SPNeteaseMusicSource new];
        }

        [repo fetchHomeSectionsWithCompletion:^(NSArray<SPHomeSection *> *sections, NSError *homeErr) {
            assertCheck(!homeErr && sections.count >= 4, @"真实网易云首页多分区拉取成功");

            SPPlaylist *firstPlaylist = nil;
            SPAlbum *firstAlbum = nil;
            SPArtist *firstArtist = nil;
            for (SPHomeSection *sec in sections) {
                for (id<SPMediaItem> item in sec.items) {
                    if (!firstPlaylist && [item isKindOfClass:SPPlaylist.class]) firstPlaylist = (SPPlaylist *)item;
                    if (!firstAlbum && [item isKindOfClass:SPAlbum.class]) firstAlbum = (SPAlbum *)item;
                    if (!firstArtist && [item isKindOfClass:SPArtist.class]) firstArtist = (SPArtist *)item;
                }
            }
            assertCheck(firstPlaylist && firstAlbum && firstArtist && [firstPlaylist.coverURL hasPrefix:@"https://"],
                        @"网易云首页解析出真实歌单/专辑/艺人及 HTTPS 高清封面");

            if (!firstPlaylist) {
                [self finishReport:logs pass:passCount fail:failCount completion:completion];
                return;
            }

            dispatch_group_t metaGroup = dispatch_group_create();
            __block NSArray<SPSearchCategory *> *hotCats = @[];
            __block SPAlbum *loadedAlbum = nil;
            __block NSArray<SPTrack *> *artistTracks = @[];
            __block NSArray<SPHomeSection *> *moreSections = @[];
            __block BOOL moreHasMore = NO;
            __block NSInteger qrCheckCode = 0;
            __block NSString *qrUnikey = nil;
            __block NSString *qrURLStr = nil;

            dispatch_group_enter(metaGroup);
            [repo fetchSearchCategoriesWithCompletion:^(NSArray<SPSearchCategory *> *cats, NSError *catErr) {
                if (!catErr && cats) hotCats = cats;
                dispatch_group_leave(metaGroup);
            }];

            dispatch_group_enter(metaGroup);
            [repo fetchHomeMoreSectionsForPage:1 completion:^(NSArray<SPHomeSection *> *more, BOOL hasMore, NSError *moreErr) {
                if (!moreErr && more) {
                    moreSections = more;
                    moreHasMore = hasMore;
                }
                dispatch_group_leave(metaGroup);
            }];

            SPNeteaseAuthProvider *qrAuth = [SPNeteaseAuthProvider new];
            dispatch_group_enter(metaGroup);
            [qrAuth createQRCodeWithCompletion:^(NSString *unikey, NSString *qrURL, NSError *qrErr) {
                qrUnikey = unikey;
                qrURLStr = qrURL;
                if (!qrErr && unikey.length > 0) {
                    [qrAuth checkQRStatusForKey:unikey completion:^(NSInteger statusCode, NSString *msg, NSString *cookie, NSError *chkErr) {
                        qrCheckCode = statusCode;
                        dispatch_group_leave(metaGroup);
                    }];
                } else {
                    dispatch_group_leave(metaGroup);
                }
            }];

            if (firstAlbum) {
                dispatch_group_enter(metaGroup);
                [repo fetchAlbumWithId:firstAlbum.identifier completion:^(SPAlbum *al, NSError *alErr) {
                    if (!alErr) loadedAlbum = al;
                    dispatch_group_leave(metaGroup);
                }];
            }

            if (firstArtist) {
                dispatch_group_enter(metaGroup);
                [repo fetchArtistTopTracksWithId:firstArtist.identifier completion:^(SPArtist *ar, NSArray<SPTrack *> *tracks, NSError *arErr) {
                    if (!arErr && tracks) artistTracks = tracks;
                    dispatch_group_leave(metaGroup);
                }];
            }

            __block SPPlaylist *playlist = nil;
            dispatch_group_enter(metaGroup);
            [repo fetchPlaylistWithId:firstPlaylist.identifier completion:^(SPPlaylist *pl, NSError *plErr) {
                playlist = pl;
                dispatch_group_leave(metaGroup);
            }];

            __block NSArray<SPHomeSection *> *musicSections = @[];
            dispatch_group_enter(metaGroup);
            [repo fetchHomeSectionsForCategory:SPHomeCategoryMusic completion:^(NSArray<SPHomeSection *> *secs, NSError *mErr) {
                if (!mErr && secs) musicSections = secs;
                dispatch_group_leave(metaGroup);
            }];

            __block NSArray<SPHomeSection *> *podcastSections = @[];
            __block SPPlaylist *podcastDetail = nil;
            __block NSURL *podcastAudioURL = nil;
            dispatch_group_enter(metaGroup);
            [repo fetchHomeSectionsForCategory:SPHomeCategoryPodcast completion:^(NSArray<SPHomeSection *> *secs, NSError *pErr) {
                if (!pErr && secs) podcastSections = secs;
                SPPlaylist *firstRadio = nil;
                for (SPHomeSection *sec in podcastSections) {
                    for (id<SPMediaItem> item in sec.items) {
                        if ([item isKindOfClass:SPPlaylist.class] && ((SPPlaylist *)item).isPodcast) {
                            firstRadio = (SPPlaylist *)item;
                            break;
                        }
                    }
                    if (firstRadio) break;
                }
                if (firstRadio) {
                    [repo fetchPlaylistWithId:firstRadio.identifier completion:^(SPPlaylist *pl, NSError *dErr) {
                        podcastDetail = pl;
                        SPTrack *ep = pl.tracks.firstObject;
                        if (ep) {
                            [repo fetchPlayURLForTrack:ep completion:^(NSURL *url, NSError *uErr) {
                                podcastAudioURL = url;
                                dispatch_group_leave(metaGroup);
                            }];
                        } else {
                            dispatch_group_leave(metaGroup);
                        }
                    }];
                } else {
                    dispatch_group_leave(metaGroup);
                }
            }];

            dispatch_group_notify(metaGroup, dispatch_get_main_queue(), ^{
                assertCheck(hotCats.count >= 6, @"网易云热门搜索分类 (/playlist/hot) 拉取成功");
                assertCheck(moreSections.count >= 2 && moreHasMore, @"网易云首页下滑分页扩展分区 (page=1) 拉取成功");
                assertCheck(musicSections.count >= 3 && [musicSections.firstObject.items.firstObject isKindOfClass:SPPlaylist.class]
                            && ![musicSections.firstObject.items.firstObject.identifier isEqualToString:firstPlaylist.identifier],
                            @"首页「音乐」标签返回独立音乐/新碟歌单分区");
                assertCheck(podcastSections.count >= 3 && podcastDetail.isPodcast && podcastDetail.tracks.count > 0 && podcastAudioURL.absoluteString.length > 0,
                            @"首页「播客」标签拉取真实网易云 DJ 播客节目并解析可播音频 URL");
                assertCheck(qrUnikey.length > 0 && qrURLStr.length > 0 && qrCheckCode == 801,
                            @"网易云扫码登录二维码生成与状态轮询 (code=801) 闭环通过");
                assertCheck(loadedAlbum != nil && loadedAlbum.tracks.count > 0, @"网易云专辑详情 (/album) 拉取曲目成功");
                assertCheck(artistTracks.count > 0, @"网易云艺人热门歌曲 (/artists) 拉取成功");
                assertCheck(playlist.tracks.count >= 5, @"网易云歌单详情 (/playlist/track/all) 拉取完整曲目");

                SPPlaylist *syncCached = [repo cachedPlaylistForId:firstPlaylist.identifier];
                assertCheck(syncCached != nil && repo.cacheHitCount >= 1,
                            @"L3 SPMusicRepository 同步 LRU 缓存命中网易云歌单");

                // 个人音乐库（点赞/自建歌单/关注艺人）持久化闭环校验（自动清理恢复）
                if (playlist.tracks.count > 0) {
                    SPLibraryStore *lib = [SPLibraryStore shared];
                    SPTrack *sampleTrack = playlist.tracks.firstObject;
                    BOOL origLiked = [lib isTrackLiked:sampleTrack.identifier];
                    BOOL toggledLike = [lib toggleLikeTrack:sampleTrack];
                    assertCheck(toggledLike == !origLiked && ([lib isTrackLiked:sampleTrack.identifier] == !origLiked),
                                @"SPLibraryStore 点赞歌曲状态持久化切换正常");
                    [lib toggleLikeTrack:sampleTrack];

                    SPPlaylist *tmpPl = [lib createPlaylistWithName:@"__自检临时歌单__" desc:nil];
                    BOOL addedTmp = [lib addTrack:sampleTrack toPlaylistId:tmpPl.identifier];
                    SPPlaylist *fetchedTmp = [lib localPlaylistWithId:tmpPl.identifier];
                    BOOL deletedTmp = [lib deletePlaylistWithId:tmpPl.identifier];
                    assertCheck(addedTmp && fetchedTmp.tracks.count == 1 && deletedTmp && [lib localPlaylistWithId:tmpPl.identifier] == nil,
                                @"SPLibraryStore 新建歌单/加歌/删歌单全链路正常");

                    if (firstArtist) {
                        BOOL origFollow = [lib isArtistFollowed:firstArtist.identifier];
                        BOOL nowFollow = [lib toggleFollowArtist:firstArtist];
                        assertCheck(nowFollow == !origFollow, @"SPLibraryStore 关注艺人切换与持久化正常");
                        [lib toggleFollowArtist:firstArtist];
                    }

                    // 多账号音乐库与点赞/歌单数据隔离校验
                    SPUser *origUser = [SPAuthService shared].currentUser;
                    SPUser *userA = [SPUser new];
                    userA.userId = @"u_iso_test_a";
                    userA.account = @"iso_a@spotify.local";
                    userA.nickname = @"隔离账号A";
                    [[SPAuthService shared] adoptAuthenticatedUser:userA];
                    NSString *pathA = lib.currentStorageFilePath;
                    [lib toggleLikeTrack:sampleTrack];
                    SPPlaylist *plA = [lib createPlaylistWithName:@"账号A私密歌单" desc:nil];

                    SPUser *userB = [SPUser new];
                    userB.userId = @"u_iso_test_b";
                    userB.account = @"iso_b@spotify.local";
                    userB.nickname = @"隔离账号B";
                    [[SPAuthService shared] adoptAuthenticatedUser:userB];
                    NSString *pathB = lib.currentStorageFilePath;
                    BOOL bIsolatedFromA = ![pathA isEqualToString:pathB]
                        && ![lib isTrackLiked:sampleTrack.identifier]
                        && ([lib localPlaylistWithId:plA.identifier] == nil);

                    [[SPAuthService shared] adoptAuthenticatedUser:userA];
                    BOOL aRestoredIntact = [lib isTrackLiked:sampleTrack.identifier]
                        && ([lib localPlaylistWithId:plA.identifier] != nil);
                    assertCheck(bIsolatedFromA && aRestoredIntact,
                                @"不同登录账号之间音乐库（点赞歌曲 / 自建歌单 / 关注艺人）独立隔离不互通");

                    [[NSFileManager defaultManager] removeItemAtPath:pathA error:nil];
                    [[NSFileManager defaultManager] removeItemAtPath:pathB error:nil];
                    if (origUser) {
                        [[SPAuthService shared] adoptAuthenticatedUser:origUser];
                    } else {
                        [[SPAuthService shared] logout];
                    }
                }

                if (playlist.tracks.count < 2) {
                    [self finishReport:logs pass:passCount fail:failCount completion:completion];
                    return;
                }

                // 挑出 2 首有合法播放地址的真实网易云歌曲用于播放器 + 缓存闭环测试
                NSUInteger probeLimit = MIN((NSUInteger)8, playlist.tracks.count);
                dispatch_group_t urlGroup = dispatch_group_create();
                NSMutableArray<SPTrack *> *playableTracks = [NSMutableArray array];
                NSMutableDictionary<NSString *, NSURL *> *resolvedURLs = [NSMutableDictionary dictionary];

                for (NSUInteger i = 0; i < probeLimit; i++) {
                    SPTrack *cand = playlist.tracks[i];
                    dispatch_group_enter(urlGroup);
                    [repo fetchPlayURLForTrack:cand completion:^(NSURL *url, NSError *urlErr) {
                        @synchronized (playableTracks) {
                            if (url.absoluteString.length > 0 && !urlErr) {
                                resolvedURLs[cand.identifier] = url;
                                [playableTracks addObject:cand];
                            }
                        }
                        dispatch_group_leave(urlGroup);
                    }];
                }

                dispatch_group_notify(urlGroup, dispatch_get_main_queue(), ^{
                    assertCheck(playableTracks.count >= 2,
                                [NSString stringWithFormat:@"网易云 /song/url/v1 解析到可播放歌曲 (%lu/%lu)",
                                 (unsigned long)playableTracks.count, (unsigned long)probeLimit]);

                    if (playableTracks.count < 2) {
                        [self finishReport:logs pass:passCount fail:failCount completion:completion];
                        return;
                    }

                    // 保持歌单原始相对顺序
                    NSMutableArray<SPTrack *> *orderedPlayable = [NSMutableArray array];
                    for (SPTrack *t in playlist.tracks) {
                        if (resolvedURLs[t.identifier]) [orderedPlayable addObject:t];
                    }
                    SPTrack *track0 = orderedPlayable[0];
                    SPTrack *track1 = orderedPlayable[1];

                    SPPlayerService *player = [SPPlayerService shared];
                    if (player.isShuffleEnabled) [player toggleShuffle];
                    [player playTracks:orderedPlayable startIndex:0 contextTitle:playlist.name];

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        assertCheck([[SPAudioCacheManager shared] hasCachedTrack:track1],
                                    @"播放真实网易云第 1 首时已后台预加载第 2 首到 L1/L2 缓存");
                        assertCheck([[SPHistoryStore shared].recentTracks.firstObject isEqual:track0],
                                    @"SPHistoryStore 实时记录真实网易云曲目");

                        NSDictionary *nowInfo = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
                        assertCheck([nowInfo[MPMediaItemPropertyTitle] isEqualToString:track0.name] &&
                                    [nowInfo[MPNowPlayingInfoPropertyMediaType] integerValue] == MPNowPlayingInfoMediaTypeAudio,
                                    @"锁屏/灵动岛 MPNowPlayingInfoCenter 真实网易云元数据已注入");

                        [player next];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            assertCheck([player.currentTrack isEqual:track1] && player.lastPlaybackUsedCache,
                                        @"切下一首网易云歌曲成功且命中预加载缓存");

                            SPTrack *lyricProbe = [SPTrack new];
                            lyricProbe.identifier = @"2155422573";
                            lyricProbe.name = @"LyricProbe";
                            NSUInteger hitsBeforeLyric = repo.cacheHitCount;
                            [repo fetchLyricsForTrack:lyricProbe completion:^(SPLyricDocument *doc1, NSError *lErr) {
                                BOOL hasSynced = (!lErr && doc1.isSynced && doc1.lines.count > 5);
                                [repo fetchLyricsForTrack:lyricProbe completion:^(SPLyricDocument *doc2, NSError *lErr2) {
                                    assertCheck(hasSynced && doc2 != nil && repo.cacheHitCount > hitsBeforeLyric,
                                                [NSString stringWithFormat:@"网易云 /lyric 解析同步歌词 (%lu 句) 与 L3 LRU 缓存命中成功",
                                                 (unsigned long)doc1.lines.count]);

                                    CFTimeInterval t0 = CFAbsoluteTimeGetCurrent();
                                    [[SPAudioCacheManager shared] resolvePlayableAssetForTrack:track0
                                                                                    completion:^(AVURLAsset *asset, BOOL isCacheHit, NSError *err) {
                                        double elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
                                        assertCheck(asset != nil && isCacheHit && elapsedMs < 20.0,
                                                    [NSString stringWithFormat:@"切回上一首立即命中缓存 (isHit=%d, 耗时=%.2fms)", isCacheHit, elapsedMs]);

                                        [player seekToTime:10.0];
                                        [player skipToPreviousTrack];
                                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                            assertCheck([player.currentTrack isEqual:track0] && player.lastPlaybackUsedCache,
                                                        @"左/右滑交互提交 skipToPreviousTrack 直接回退上一首并命中缓存秒切");

                                            [self runUIFlowTestWithRootVC:rootVC
                                                                 playlist:playlist
                                                              assertCheck:assertCheck
                                                               completion:^{
                                                // 验证数据源热切换（Netease -> Mock -> Netease）
                                                id<SPMusicDataSource> origSrc = repo.source;
                                                repo.source = [SPMockMusicSource new];
                                                assertCheck([repo.sourceName isEqualToString:@"Mock"], @"设置切换 Mock 数据源正常");
                                                repo.source = origSrc;
                                                assertCheck([repo.source isKindOfClass:SPNeteaseMusicSource.class], @"热切回网易云 API 数据源正常");
                                                [self finishReport:logs pass:passCount fail:failCount completion:completion];
                                            }];
                                        });
                                    }];
                                }];
                            }];
                        });
                    });
                });
            });
        }];
    }];
}

+ (void)runAuthTestWithAssert:(void (^)(BOOL, NSString *))assertCheck
                   completion:(void (^)(void))completion {
    SPAuthService *auth = [SPAuthService shared];
    SPUser *originalUser = auth.currentUser;
    NSString *testAccount = [NSString stringWithFormat:@"test_%u@spotify.local", arc4random_uniform(900000) + 100000];

    [auth sendVerificationCodeToAccount:testAccount
                                purpose:SPAuthCodePurposeRegister
                             completion:^(BOOL success, NSString *debugCode, NSError *error) {
        assertCheck(success && debugCode.length == 6 && !error, @"SPAuthService 生成 6 位注册验证码");
        if (!success || debugCode.length != 6) {
            if (completion) completion();
            return;
        }
        [auth registerWithAccount:testAccount
                         password:@"SpotifyTest9"
                 verificationCode:debugCode
                         nickname:@"测试听友"
                       completion:^(SPUser *user, NSError *regErr) {
            assertCheck(user != nil && !regErr && auth.isLoggedIn, @"SPAuthService 注册并自动登录持久化会话");
            [auth logout];
            assertCheck(!auth.isLoggedIn, @"SPAuthService 登出清理会话");

            [auth loginWithAccount:testAccount password:@"WrongPass1" completion:^(SPUser *badUser, NSError *badErr) {
                assertCheck(badUser == nil && badErr != nil, @"SPAuthService 错误密码拦截");

                [auth loginWithAccount:testAccount password:@"SpotifyTest9" completion:^(SPUser *okUser, NSError *okErr) {
                    assertCheck(okUser != nil && !okErr && [okUser.nickname isEqualToString:@"测试听友"],
                                @"SPAuthService SHA-256 加盐密码校验登录成功");

                    [auth sendVerificationCodeToAccount:testAccount
                                                purpose:SPAuthCodePurposeLogin
                                             completion:^(BOOL codeOK, NSString *loginCode, NSError *codeErr) {
                        assertCheck(codeOK && loginCode.length == 6 && !codeErr, @"SPAuthService 生成登录验证码");
                        [auth logout];
                        [auth loginWithAccount:testAccount verificationCode:loginCode completion:^(SPUser *codeUser, NSError *loginErr) {
                            assertCheck(codeUser != nil && !loginErr, @"SPAuthService 验证码登录闭环通过");
                            if (!originalUser) [auth logout];
                            if (completion) completion();
                        }];
                    }];
                }];
            }];
        }];
    }];
}

+ (void)runUIFlowTestWithRootVC:(SPRootViewController *)rootVC
                       playlist:(SPPlaylist *)playlist
                    assertCheck:(void (^)(BOOL, NSString *))assertCheck
                     completion:(void (^)(void))completion {
    UITabBarController *tab = rootVC.tabController;
    UINavigationController *homeNav = tab.viewControllers[0];

    // 1. 叠加式左侧抽屉展开与收起（验证主视图静止无位移/无抖动）
    tab.selectedIndex = 0;
    [rootVC openSideDrawer];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.40 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        assertCheck(rootVC.isDrawerOpen && CGAffineTransformIsIdentity(rootVC.contentContainer.transform),
                    @"左侧叠加抽屉展开正常且主页面静止无拉伸");
        [self captureWindow:rootVC.view.window named:@"snap_drawer.png"];
        [rootVC closeSideDrawerAnimated:NO completion:nil];

        // 2. 新手引导页 & 原版两级登录注册流
        SPOnboardingViewController *onboarding = [SPOnboardingViewController new];
        [onboarding.view layoutIfNeeded];
        assertCheck(onboarding.slideCount == 4, @"横滑大图引导页初始化与 4 页配置正常");

        [rootVC presentAuthFlow];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.42 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SPNavigationController *authNav = (SPNavigationController *)rootVC.presentedViewController;
            BOOL isWelcomeRoot = [authNav isKindOfClass:SPNavigationController.class]
                && [authNav.topViewController isKindOfClass:SPAuthWelcomeViewController.class];
            assertCheck(isWelcomeRoot, @"登录注册欢迎页以统一导航容器弹出正常");
            UIWindow *authWindow = authNav.view.window ?: rootVC.view.window;
            [self captureWindow:authWindow named:@"snap_welcome.png"];

            SPAuthViewController *loginForm = [[SPAuthViewController alloc] initWithMode:SPAuthModeCodeLogin
                                                                                 context:SPAuthPresentationContextModal];
            if ([authNav isKindOfClass:UINavigationController.class]) {
                [authNav pushViewController:loginForm animated:NO];
                [authNav.view layoutIfNeeded];
            }
            assertCheck([authNav.topViewController isKindOfClass:SPAuthViewController.class] && authNav.viewControllers.count == 2,
                        @"欢迎页推入原版左对齐登录表单页正常");
            NSDictionary *bundleIcons = NSBundle.mainBundle.infoDictionary[@"CFBundleIcons"];
            assertCheck(bundleIcons != nil || [UIImage imageNamed:@"AppIcon60x60"] != nil,
                        @"AppIcon 资源集已编译打包至应用 Bundle");
            [SPToast showMessage:@"测试验证码：682914（5分钟内有效，也可点击下方提示一键填入）"
                        duration:6.5
                        position:SPToastPositionTop];
            [self captureWindow:(authNav.view.window ?: rootVC.view.window) named:@"snap_login.png"];

            SPNeteaseQRLoginViewController *qrVC = [[SPNeteaseQRLoginViewController alloc] initWithContext:SPAuthPresentationContextModal];
            if ([authNav isKindOfClass:UINavigationController.class]) {
                [authNav pushViewController:qrVC animated:NO];
                [authNav.view layoutIfNeeded];
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self captureWindow:(authNav.view.window ?: rootVC.view.window) named:@"snap_qr_login.png"];
                [rootVC dismissViewControllerAnimated:NO completion:^{
                    // 2.5 验证首页 UI 实测下滑自动追加更多分区
                    UIViewController *homeRoot = homeNav.viewControllers.firstObject;
                    UICollectionView *homeCV = nil;
                    for (UIView *sub in homeRoot.view.subviews) {
                        if ([sub isKindOfClass:UICollectionView.class]) {
                            homeCV = (UICollectionView *)sub;
                            break;
                        }
                    }
                    NSInteger initialSecCount = homeCV.numberOfSections;
                    if (homeCV && initialSecCount > 0) {
                        [homeCV layoutIfNeeded];
                        CGFloat targetY = MAX(0, homeCV.contentSize.height - CGRectGetHeight(homeCV.bounds) + 20.0);
                        [homeCV setContentOffset:CGPointMake(0, targetY) animated:NO];
                    }

                    // 3. 动态深浅模式切换 & 设置开关状态（含 UITextEffectsWindow 防黑白屏与 MiniPlayer 槽位布局回归验证）
                    UIUserInterfaceStyle originalStyle = SPTheme.interfaceStyle;
                    [SPTheme applyInterfaceStyle:UIUserInterfaceStyleDark animated:YES];
                    [self captureWindow:rootVC.view.window named:@"snap_netease_home.png"];
                    [SPTheme applyInterfaceStyle:UIUserInterfaceStyleLight animated:YES];
                    assertCheck(!SPTheme.isDarkMode, @"动态主题支持切换至浅色模式");

                    BOOL auxiliaryWindowsTransparent = YES;
                    for (UIWindow *win in rootVC.view.window.windowScene.windows) {
                        if (win != rootVC.view.window) {
                            if (win.backgroundColor != nil && ![win.backgroundColor isEqual:UIColor.clearColor]) {
                                auxiliaryWindowsTransparent = NO;
                                break;
                            }
                        }
                    }
                    assertCheck(auxiliaryWindowsTransparent, @"深浅色切换时系统辅助窗口 (UITextEffectsWindow) 保持全透明不遮挡主屏");
                    SPMiniPlayerView *miniPlayerView = nil;
                    for (UIView *sub in rootVC.contentContainer.subviews) {
                        if ([sub isKindOfClass:SPMiniPlayerView.class]) {
                            miniPlayerView = (SPMiniPlayerView *)sub;
                            break;
                        }
                    }
                    [miniPlayerView layoutIfNeeded];
                    assertCheck(miniPlayerView != nil && !CGRectIsEmpty(miniPlayerView.coverView.frame) && CGRectGetWidth(miniPlayerView.coverView.frame) >= 36.0,
                                @"登录后进入主页时底部 MiniPlayer 内部槽位与封面帧同步就位不乱飘");
                    [self captureWindow:rootVC.view.window named:@"snap_home_light.png"];

                    BOOL origPreload = [SPPlayerService shared].isPreloadEnabled;
                    BOOL origHaptic = SPHaptics.isEnabled;
                    [SPPlayerService shared].preloadEnabled = !origPreload;
                    SPHaptics.enabled = !origHaptic;
                    assertCheck([SPPlayerService shared].isPreloadEnabled == !origPreload && SPHaptics.isEnabled == !origHaptic,
                                @"设置开关项（预加载 / 触感反馈）状态读写正常");
                    [SPPlayerService shared].preloadEnabled = origPreload;
                    SPHaptics.enabled = origHaptic;

                    // 4. 新动态 / 历史 / 舒展设置页 / 详情页流转
                    SPSettingsViewController *settingsVC = [SPSettingsViewController new];
                    [homeNav pushViewController:settingsVC animated:NO];
                    [settingsVC.view layoutIfNeeded];
                    [self captureWindow:rootVC.view.window named:@"snap_settings_light.png"];

                    [SPTheme applyInterfaceStyle:UIUserInterfaceStyleDark animated:NO];
                    [settingsVC.view layoutIfNeeded];
                    [self captureWindow:rootVC.view.window named:@"snap_settings_dark.png"];

                    SPActivityViewController *activityVC = [SPActivityViewController new];
                    SPHistoryViewController *historyVC = [SPHistoryViewController new];
                    SPDetailViewController *detailVC = [[SPDetailViewController alloc] initWithMediaItem:playlist];
                    [homeNav pushViewController:activityVC animated:NO];
                    [homeNav pushViewController:historyVC animated:NO];
                    [homeNav pushViewController:detailVC animated:NO];
                    [detailVC.view layoutIfNeeded];
                    assertCheck(homeNav.viewControllers.count == 5, @"新动态/收听历史/设置/详情页推入正常");
                    [SPTheme applyInterfaceStyle:originalStyle animated:NO];

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (homeCV) {
                            assertCheck(homeCV.numberOfSections > initialSecCount,
                                        [NSString stringWithFormat:@"首页下滑自动拉取并平滑插入新分区 (%ld -> %ld)",
                                         (long)initialSecCount, (long)homeCV.numberOfSections]);
                        }
                        [self captureWindow:rootVC.view.window named:@"snap_netease_detail.png"];
                        SPArtist *sampleArtist = playlist.tracks.firstObject.artists.firstObject;
                        if (sampleArtist.identifier.length > 0) {
                            SPDetailViewController *artistVC = [[SPDetailViewController alloc] initWithMediaItem:sampleArtist];
                            [homeNav pushViewController:artistVC animated:NO];
                            [artistVC.view layoutIfNeeded];
                        }
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            if (sampleArtist.identifier.length > 0) {
                                [self captureWindow:rootVC.view.window named:@"snap_artist_detail.png"];
                            }
                            [homeNav popToRootViewControllerAnimated:NO];

                        // 5. 真实网易云搜索页与搜索结果
                        tab.selectedIndex = 1;
                        [[SPMusicRepository shared] searchWithKeyword:@"周杰伦" completion:^(SPSearchResult *res, NSError *err) {
                            assertCheck(!err && res.tracks.count > 0 && res.playlists.count > 0,
                                        @"真实网易云搜索 (周杰伦) 返回单曲与歌单成功");
                        }];

                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [self captureWindow:rootVC.view.window named:@"snap_netease_search.png"];
                            tab.selectedIndex = 2;
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                UINavigationController *libNav = tab.viewControllers[2];
                                UIViewController *libRoot = libNav.viewControllers.firstObject;
                                UICollectionView *libCV = nil;
                                for (UIView *sub in libRoot.view.subviews) {
                                    if ([sub isKindOfClass:UICollectionView.class]) {
                                        libCV = (UICollectionView *)sub;
                                        break;
                                    }
                                }
                                assertCheck(libCV != nil && libCV.numberOfSections == 2
                                            && [libCV numberOfItemsInSection:0] >= 2
                                            && [libCV numberOfItemsInSection:1] > 0,
                                            @"音乐库分区展示「我的音乐」与「网易云精选推荐」成功");
                                [self captureWindow:rootVC.view.window named:@"snap_library_split.png"];

                                // 验证首页「播客」标签页面截图
                                tab.selectedIndex = 0;
                                UIButton *allChip = nil;
                                UIButton *podcastChip = nil;
                                for (UIView *sub in homeRoot.view.subviews) {
                                    for (UIView *inner in sub.subviews) {
                                        for (UIView *leaf in inner.subviews) {
                                            if ([leaf isKindOfClass:UIButton.class]) {
                                                UIButton *b = (UIButton *)leaf;
                                                if ([b.configuration.title isEqualToString:@"全部"]) allChip = b;
                                                if ([b.configuration.title isEqualToString:@"播客"]) podcastChip = b;
                                            }
                                        }
                                    }
                                }
                                [podcastChip sendActionsForControlEvents:UIControlEventTouchUpInside];

                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                        [self captureWindow:rootVC.view.window named:@"snap_home_podcast.png"];
                                        [allChip sendActionsForControlEvents:UIControlEventTouchUpInside];

                                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                            [self captureWindow:rootVC.view.window named:@"snap_miniplayer_home.png"];
                                            [rootVC presentNowPlaying];
                                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                                UIViewController *presentedNP = rootVC.presentedViewController;
                                                assertCheck([presentedNP isKindOfClass:SPNowPlayingViewController.class],
                                                            @"全屏播放页 Hero 转场弹出成功");
                                                [self captureWindow:(presentedNP.view.window ?: rootVC.view.window) named:@"snap_nowplaying_main.png"];

                                                // 下滑/滚动至播放页内嵌歌词卡片
                                                UIScrollView *mainVertScroll = nil;
                                                for (UIView *sub in presentedNP.view.subviews) {
                                                    if ([sub isKindOfClass:UIScrollView.class]) {
                                                        mainVertScroll = (UIScrollView *)sub;
                                                        break;
                                                    }
                                                }
                                                if (mainVertScroll) {
                                                    CGFloat maxY = MAX(0, mainVertScroll.contentSize.height - CGRectGetHeight(mainVertScroll.bounds));
                                                    [mainVertScroll setContentOffset:CGPointMake(0, maxY) animated:NO];
                                                    [presentedNP.view layoutIfNeeded];
                                                }
                                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                                    [self captureWindow:(presentedNP.view.window ?: rootVC.view.window) named:@"snap_nowplaying_lyrics.png"];
                                                    if (mainVertScroll) {
                                                        [mainVertScroll setContentOffset:CGPointZero animated:NO];
                                                    }

                                                    SPTrack *nowTrack = [SPPlayerService shared].currentTrack;
                                                    SPFullScreenLyricsViewController *fullLyrics = [[SPFullScreenLyricsViewController alloc] initWithTrack:nowTrack
                                                                                                                                      document:nil
                                                                                                                                    themeColor:SPTheme.brandGreenColor
                                                                                                                               showTranslation:YES];
                                                    fullLyrics.modalPresentationStyle = UIModalPresentationFullScreen;
                                                    [presentedNP presentViewController:fullLyrics animated:NO completion:nil];
                                                    [fullLyrics.view layoutIfNeeded];
                                                    assertCheck(presentedNP.presentedViewController == fullLyrics,
                                                                @"全屏实时歌词页面弹出正常");
                                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                                        [self captureWindow:(fullLyrics.view.window ?: rootVC.view.window) named:@"snap_lyrics_fullscreen.png"];
                                                        [presentedNP dismissViewControllerAnimated:NO completion:^{
                                                            UIImage *cachedImg = nowTrack.coverURL.length
                                                                ? [SDImageCache.sharedImageCache imageFromCacheForKey:nowTrack.coverURL] : nil;
                                                            SPCoverPreviewViewController *coverPreview = [[SPCoverPreviewViewController alloc] initWithTrack:nowTrack
                                                                                                                                             placeholderImage:cachedImg
                                                                                                                                                   themeColor:SPTheme.brandGreenColor];
                                                            coverPreview.modalPresentationStyle = UIModalPresentationOverFullScreen;
                                                            [presentedNP presentViewController:coverPreview animated:NO completion:nil];
                                                            [coverPreview.view layoutIfNeeded];
                                                            assertCheck(presentedNP.presentedViewController == coverPreview,
                                                                        @"QQ 音乐风格高清封面大图浏览页弹出正常");
                                                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                                                [self captureWindow:(coverPreview.view.window ?: rootVC.view.window) named:@"snap_cover_preview.png"];
                                                                [presentedNP dismissViewControllerAnimated:NO completion:^{
                                                                    [[SPPlayerService shared] seekToTime:25.0];
                                                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                                                        assertCheck(fabs([SPPlayerService shared].currentTime - 25.0) < 2.0, @"全屏播放页 Seek 进度稳定无跳变");
                                                                        [rootVC dismissViewControllerAnimated:NO completion:^{
                                                                            tab.selectedIndex = 0;
                                                                            if (completion) completion();
                                                                        }];
                                                                    });
                                                                }];
                                                            });
                                                        }];
                                                    });
                                                });
                                            });
                                        });
                                    });
                            });
                        });
                        });
                    });
                }];
            });
        });
    });
}

+ (void)finishReport:(NSArray<NSString *> *)logs
                pass:(NSInteger)passCount
                fail:(NSInteger)failCount
          completion:(void (^)(BOOL, NSString *))completion {
    [[SPPlayerService shared] pause];
    SPAudioCacheManager *audioCache = [SPAudioCacheManager shared];
    SPMusicRepository *repo = [SPMusicRepository shared];
    NSString *stats = [NSString stringWithFormat:@"\n[Cache Stats] L1(URL:%lu Asset:%lu) L2(Disk:%lu首/%.2fMB Hit:%lu/%lu) L3(Meta:%lu Hit:%lu)",
                       (unsigned long)audioCache.resolvedURLCount,
                       (unsigned long)audioCache.memoryAssetCount,
                       (unsigned long)audioCache.diskCachedTrackCount,
                       audioCache.diskCacheBytes / (1024.0 * 1024.0),
                       (unsigned long)audioCache.totalHitCount,
                       (unsigned long)audioCache.totalRequestCount,
                       (unsigned long)repo.cachedEntryCount,
                       (unsigned long)repo.cacheHitCount];

    BOOL allPassed = (failCount == 0);
    NSString *summary = [NSString stringWithFormat:@"[SPSelfTest] %@ (%ld passed, %ld failed)\n%@%@",
                         allPassed ? @"ALL TESTS PASSED" : @"SOME TESTS FAILED",
                         (long)passCount, (long)failCount,
                         [logs componentsJoinedByString:@"\n"],
                         stats];
    NSLog(@"\n%@", summary);

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *reportPath = [docs stringByAppendingPathComponent:@"selftest_report.txt"];
    [summary writeToFile:reportPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [SPToast showMessage:allPassed
        ? [NSString stringWithFormat:@"自检全过 (%ld/%ld) · 缓存命中 %lu 次", (long)passCount, (long)(passCount + failCount), (unsigned long)audioCache.totalHitCount]
        : [NSString stringWithFormat:@"自检发现 %ld 项失败", (long)failCount]];

    if (completion) completion(allPassed, summary);
}

@end
