//
//  SPLibraryStore.m
//  Spotify
//
//  Spotify
//

#import "SPLibraryStore.h"
#import "SPAuthService.h"
#import "SPHTTPClient.h"
#import "SPNeteaseSession.h"
#import <YYModel/YYModel.h>

NSNotificationName const SPLibraryDidUpdateNotification = @"com.dyyxs.spotify.libraryUpdated";

static NSString * const SPLibraryLegacyFileName = @"sp_user_library_v1.json";
static NSString * const SPLibraryScopedPrefix = @"sp_user_library_v2_";
static NSString * const SPDefaultUserPlaylistId = @"user_pl_default";

@interface SPLibraryStore () <SPAuthObserver>
@property (nonatomic, copy) NSString *activeScopeKey;
@property (nonatomic, strong) NSMutableArray<SPTrack *> *likedStorage;
@property (nonatomic, strong) NSMutableArray<SPPlaylist *> *playlistsStorage;
@property (nonatomic, strong) NSMutableArray<SPArtist *> *followedArtistsStorage;
@end

@implementation SPLibraryStore

+ (instancetype)shared {
    static SPLibraryStore *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SPLibraryStore new]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _likedStorage = [NSMutableArray array];
        _playlistsStorage = [NSMutableArray array];
        _followedArtistsStorage = [NSMutableArray array];
        _activeScopeKey = [self resolvedScopeKeyForCurrentUser];
        [self loadFromDisk];
        [[SPAuthService shared] addObserver:self];
    }
    return self;
}

- (NSString *)resolvedScopeKeyForCurrentUser {
    SPUser *user = [SPAuthService shared].currentUser;
    NSString *raw = user.userId.length > 0 ? user.userId : user.account.lowercaseString;
    if (raw.length == 0) {
        return @"guest";
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    NSMutableString *sanitized = [NSMutableString stringWithCapacity:raw.length];
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex:i];
        if ([allowed characterIsMember:c]) {
            [sanitized appendFormat:@"%C", c];
        } else {
            [sanitized appendString:@"_"];
        }
    }
    return sanitized.length > 0 ? [sanitized copy] : @"guest";
}

- (NSString *)currentScopeKey {
    @synchronized (self) {
        return self.activeScopeKey ?: @"guest";
    }
}

- (NSString *)storageFilePathForScopeKey:(NSString *)scopeKey {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *fileName = [NSString stringWithFormat:@"%@%@.json", SPLibraryScopedPrefix, scopeKey.length > 0 ? scopeKey : @"guest"];
    return [docs stringByAppendingPathComponent:fileName];
}

- (NSString *)storageFilePath {
    return [self storageFilePathForScopeKey:self.activeScopeKey];
}

- (NSString *)currentStorageFilePath {
    @synchronized (self) {
        return [self storageFilePath];
    }
}

- (void)reloadForCurrentUser {
    @synchronized (self) {
        NSString *nextScope = [self resolvedScopeKeyForCurrentUser];
        self.activeScopeKey = nextScope;
        [self loadFromDisk];
    }
    [self postDidUpdate];
}

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    [self reloadForCurrentUser];
}

- (NSString *)paletteHexForIndex:(NSUInteger)idx {
    static NSArray<NSString *> *palette;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        palette = @[@"#1E3A5F", @"#27856A", @"#503750", @"#0D73EC", @"#8D67AB", @"#BA5D07"];
    });
    return palette[idx % palette.count];
}

- (void)loadFromDisk {
    [self.likedStorage removeAllObjects];
    [self.playlistsStorage removeAllObjects];
    [self.followedArtistsStorage removeAllObjects];

    NSString *path = [self storageFilePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length > 0) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) {
            NSDictionary *dict = (NSDictionary *)json;
            NSArray *liked = [NSArray yy_modelArrayWithClass:SPTrack.class json:dict[@"likedTracks"]];
            NSArray *playlists = [NSArray yy_modelArrayWithClass:SPPlaylist.class json:dict[@"userPlaylists"]];
            NSArray *artists = [NSArray yy_modelArrayWithClass:SPArtist.class json:dict[@"followedArtists"]];
            if (liked) [self.likedStorage addObjectsFromArray:liked];
            if (playlists) [self.playlistsStorage addObjectsFromArray:playlists];
            if (artists) [self.followedArtistsStorage addObjectsFromArray:artists];
            return;
        }
    }

    // 每个新账号首次初始化时拥有独立、干净的初始自建歌单与空的点赞列表
    SPPlaylist *starter = [SPPlaylist new];
    starter.identifier = SPDefaultUserPlaylistId;
    starter.name = @"我的收藏歌单";
    starter.desc = @"点击任意歌曲右侧「···」即可收藏到这里";
    starter.creatorName = [SPAuthService shared].currentUser.nickname ?: @"你";
    starter.colorHex = @"#1E3A5F";
    starter.tracks = @[];
    [self.playlistsStorage addObject:starter];
    [self saveToDisk];
}

- (void)saveToDisk {
    id likedJson = [self.likedStorage yy_modelToJSONObject] ?: @[];
    id playlistsJson = [self.playlistsStorage yy_modelToJSONObject] ?: @[];
    id artistsJson = [self.followedArtistsStorage yy_modelToJSONObject] ?: @[];

    NSDictionary *payload = @{
        @"likedTracks": [likedJson isKindOfClass:NSArray.class] ? likedJson : @[],
        @"userPlaylists": [playlistsJson isKindOfClass:NSArray.class] ? playlistsJson : @[],
        @"followedArtists": [artistsJson isKindOfClass:NSArray.class] ? artistsJson : @[],
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (data) {
        [data writeToFile:[self storageFilePath] atomically:YES];
    }
}

- (void)postDidUpdate {
    dispatch_block_t block = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPLibraryDidUpdateNotification object:self];
    };
    if (NSThread.isMainThread) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

#pragma mark - Liked Songs

- (NSArray<SPTrack *> *)likedTracks {
    @synchronized (self) {
        return [self.likedStorage copy];
    }
}

- (SPPlaylist *)likedSongsPlaylist {
    @synchronized (self) {
        SPPlaylist *pl = [SPPlaylist new];
        pl.identifier = SPLikedSongsPlaylistId;
        pl.name = @"已点赞的歌曲";
        pl.desc = @"你点赞收藏的每一首心动曲目";
        pl.creatorName = [SPAuthService shared].currentUser.nickname ?: @"你";
        pl.colorHex = @"#450AF5";
        pl.tracks = [self.likedStorage copy];
        return pl;
    }
}

- (BOOL)isTrackLiked:(NSString *)trackId {
    if (trackId.length == 0) return NO;
    @synchronized (self) {
        for (SPTrack *t in self.likedStorage) {
            if ([t.identifier isEqualToString:trackId]) return YES;
        }
        return NO;
    }
}

- (BOOL)toggleLikeTrack:(SPTrack *)track {
    if (!track || track.identifier.length == 0) return NO;
    BOOL likedNow = NO;
    @synchronized (self) {
        NSUInteger idx = [self.likedStorage indexOfObjectPassingTest:^BOOL(SPTrack *obj, NSUInteger i, BOOL *stop) {
            return [obj.identifier isEqualToString:track.identifier];
        }];
        if (idx != NSNotFound) {
            [self.likedStorage removeObjectAtIndex:idx];
            likedNow = NO;
        } else {
            [self.likedStorage insertObject:track atIndex:0];
            likedNow = YES;
        }
        [self saveToDisk];
    }
    [self postDidUpdate];
    return likedNow;
}

#pragma mark - User Playlists

- (NSArray<SPPlaylist *> *)userPlaylists {
    @synchronized (self) {
        return [self.playlistsStorage copy];
    }
}

- (BOOL)isUserCreatedPlaylistId:(NSString *)playlistId {
    return [playlistId hasPrefix:@"user_pl_"];
}

- (SPPlaylist *)createPlaylistWithName:(NSString *)name desc:(nullable NSString *)desc {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) trimmed = @"新建歌单";

    SPPlaylist *pl = [SPPlaylist new];
    long long ts = (long long)(NSDate.date.timeIntervalSince1970 * 1000.0);
    pl.identifier = [NSString stringWithFormat:@"user_pl_%lld_%u", ts, arc4random_uniform(1000)];
    pl.name = trimmed;
    pl.desc = desc.length > 0 ? desc : @"由你创建的个人歌单";
    pl.creatorName = [SPAuthService shared].currentUser.nickname ?: @"你";
    pl.tracks = @[];

    @synchronized (self) {
        pl.colorHex = [self paletteHexForIndex:self.playlistsStorage.count];
        [self.playlistsStorage insertObject:pl atIndex:0];
        [self saveToDisk];
    }
    [self postDidUpdate];
    return pl;
}

- (BOOL)deletePlaylistWithId:(NSString *)playlistId {
    if (playlistId.length == 0) return NO;
    BOOL deleted = NO;
    @synchronized (self) {
        NSUInteger idx = [self.playlistsStorage indexOfObjectPassingTest:^BOOL(SPPlaylist *obj, NSUInteger i, BOOL *stop) {
            return [obj.identifier isEqualToString:playlistId];
        }];
        if (idx != NSNotFound) {
            [self.playlistsStorage removeObjectAtIndex:idx];
            [self saveToDisk];
            deleted = YES;
        }
    }
    if (deleted) [self postDidUpdate];
    return deleted;
}

- (BOOL)addTrack:(SPTrack *)track toPlaylistId:(NSString *)playlistId {
    if (!track || track.identifier.length == 0 || playlistId.length == 0) return NO;
    if ([playlistId isEqualToString:SPLikedSongsPlaylistId]) {
        if ([self isTrackLiked:track.identifier]) return NO;
        return [self toggleLikeTrack:track];
    }

    BOOL added = NO;
    @synchronized (self) {
        for (SPPlaylist *pl in self.playlistsStorage) {
            if (![pl.identifier isEqualToString:playlistId]) continue;
            for (SPTrack *existing in pl.tracks) {
                if ([existing.identifier isEqualToString:track.identifier]) {
                    return NO;
                }
            }
            NSMutableArray<SPTrack *> *updated = [NSMutableArray arrayWithObject:track];
            if (pl.tracks.count > 0) [updated addObjectsFromArray:pl.tracks];
            pl.tracks = updated;
            if (pl.coverURL.length == 0 && track.coverURL.length > 0) {
                pl.coverURL = track.coverURL;
            }
            [self saveToDisk];
            added = YES;
            break;
        }
    }
    if (added) [self postDidUpdate];
    return added;
}

- (BOOL)removeTrackId:(NSString *)trackId fromPlaylistId:(NSString *)playlistId {
    if (trackId.length == 0 || playlistId.length == 0) return NO;
    BOOL removed = NO;
    @synchronized (self) {
        if ([playlistId isEqualToString:SPLikedSongsPlaylistId]) {
            NSUInteger idx = [self.likedStorage indexOfObjectPassingTest:^BOOL(SPTrack *obj, NSUInteger i, BOOL *stop) {
                return [obj.identifier isEqualToString:trackId];
            }];
            if (idx != NSNotFound) {
                [self.likedStorage removeObjectAtIndex:idx];
                [self saveToDisk];
                removed = YES;
            }
        } else {
            for (SPPlaylist *pl in self.playlistsStorage) {
                if (![pl.identifier isEqualToString:playlistId]) continue;
                NSMutableArray<SPTrack *> *mutable = [NSMutableArray arrayWithArray:pl.tracks ?: @[]];
                NSUInteger idx = [mutable indexOfObjectPassingTest:^BOOL(SPTrack *obj, NSUInteger i, BOOL *stop) {
                    return [obj.identifier isEqualToString:trackId];
                }];
                if (idx != NSNotFound) {
                    [mutable removeObjectAtIndex:idx];
                    pl.tracks = mutable;
                    [self saveToDisk];
                    removed = YES;
                }
                break;
            }
        }
    }
    if (removed) [self postDidUpdate];
    return removed;
}

- (nullable SPPlaylist *)localPlaylistWithId:(nullable NSString *)playlistId {
    if (playlistId.length == 0) return nil;
    if ([playlistId isEqualToString:SPLikedSongsPlaylistId]) {
        return [self likedSongsPlaylist];
    }
    @synchronized (self) {
        for (SPPlaylist *pl in self.playlistsStorage) {
            if ([pl.identifier isEqualToString:playlistId]) {
                return pl;
            }
        }
    }
    return nil;
}

#pragma mark - Followed Artists

- (NSArray<SPArtist *> *)followedArtists {
    @synchronized (self) {
        return [self.followedArtistsStorage copy];
    }
}

- (BOOL)isArtistFollowed:(nullable NSString *)artistId {
    if (artistId.length == 0) return NO;
    @synchronized (self) {
        for (SPArtist *ar in self.followedArtistsStorage) {
            if ([ar.identifier isEqualToString:artistId]) return YES;
        }
        return NO;
    }
}

- (BOOL)toggleFollowArtist:(SPArtist *)artist {
    if (!artist || artist.identifier.length == 0) return NO;
    BOOL followedNow = NO;
    @synchronized (self) {
        NSUInteger idx = [self.followedArtistsStorage indexOfObjectPassingTest:^BOOL(SPArtist *obj, NSUInteger i, BOOL *stop) {
            return [obj.identifier isEqualToString:artist.identifier];
        }];
        if (idx != NSNotFound) {
            [self.followedArtistsStorage removeObjectAtIndex:idx];
            followedNow = NO;
        } else {
            [self.followedArtistsStorage insertObject:artist atIndex:0];
            followedNow = YES;
        }
        [self saveToDisk];
    }
    [self syncFollowWithNeteaseIfSignedIn:artist.identifier follow:followedNow];
    [self postDidUpdate];
    return followedNow;
}

- (void)syncFollowWithNeteaseIfSignedIn:(NSString *)artistId follow:(BOOL)follow {
    SPNeteaseSession *session = [SPNeteaseSession shared];
    if (session.userCookie.length == 0 || artistId.length == 0) return;
    NSURL *base = [NSURL URLWithString:[SPNeteaseSession baseURLString]];
    if (!base) return;
    SPHTTPClient *client = [[SPHTTPClient alloc] initWithBaseURL:base];
    [client GET:@"/artist/sub"
     parameters:@{@"id": artistId, @"t": follow ? @1 : @0}
         cookie:session.userCookie
    bypassCache:YES
     completion:^(NSDictionary *json, NSError *err) {}];
}

@end
