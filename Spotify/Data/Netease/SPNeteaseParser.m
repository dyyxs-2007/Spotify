//
//  SPNeteaseParser.m
//  Spotify
//

#import "SPNeteaseParser.h"

@implementation SPNeteaseParser

+ (nullable NSString *)stringValue:(id)val {
    if (!val || val == NSNull.null) return nil;
    if ([val isKindOfClass:NSString.class]) {
        NSString *s = (NSString *)val;
        return s.length > 0 ? s : nil;
    }
    if ([val isKindOfClass:NSNumber.class]) {
        return [(NSNumber *)val stringValue];
    }
    return nil;
}

+ (nullable NSDictionary *)dictValue:(id)val {
    return [val isKindOfClass:NSDictionary.class] ? (NSDictionary *)val : nil;
}

+ (nullable NSArray *)arrayValue:(id)val {
    return [val isKindOfClass:NSArray.class] ? (NSArray *)val : nil;
}

+ (long long)longLongValue:(id)val {
    if (!val || val == NSNull.null) return 0;
    return [val respondsToSelector:@selector(longLongValue)] ? [val longLongValue] : 0;
}

+ (nullable NSString *)normalizedCoverURL:(nullable NSString *)rawURL size:(NSInteger)px {
    NSString *url = [self stringValue:rawURL];
    if (url.length == 0) return nil;
    if ([url hasPrefix:@"http://"]) {
        url = [@"https://" stringByAppendingString:[url substringFromIndex:7]];
    }
    if (px > 0 && [url containsString:@"music.126.net"] && ![url containsString:@"param="]) {
        NSString *sep = [url containsString:@"?"] ? @"&" : @"?";
        url = [url stringByAppendingFormat:@"%@param=%ldy%ld", sep, (long)px, (long)px];
    }
    return url;
}

+ (NSInteger)yearFromTimestampMs:(long long)ms {
    if (ms <= 0) return 0;
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ms / 1000.0];
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    return [cal component:NSCalendarUnitYear fromDate:date];
}

+ (NSString *)mappedAlbumType:(nullable NSString *)rawType {
    NSString *lower = [self stringValue:rawType].lowercaseString;
    if ([lower containsString:@"ep"]) return @"EP";
    if ([lower containsString:@"single"] || [lower containsString:@"单曲"]) return @"单曲";
    return @"专辑";
}

+ (NSString *)paletteHexForSeed:(NSString *)seed {
    static NSArray<NSString *> *palette;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        palette = @[
            @"#E13300", @"#1E3264", @"#8D67AB", @"#148A08",
            @"#BA5D07", @"#E8115B", @"#503750", @"#0D73EC",
            @"#477D95", @"#AF2896", @"#27856A", @"#777777"
        ];
    });
    NSUInteger idx = seed.length > 0 ? (seed.hash % palette.count) : 0;
    return palette[idx];
}

#pragma mark - Models

+ (nullable SPArtist *)artistFromJSON:(nullable NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    NSString *ident = [self stringValue:dict[@"id"]];
    NSString *name = [self stringValue:dict[@"name"]];
    if (ident.length == 0 || name.length == 0) return nil;

    SPArtist *artist = [SPArtist new];
    artist.identifier = ident;
    artist.name = name;
    artist.coverURL = [self normalizedCoverURL:([self stringValue:dict[@"picUrl"]] ?: [self stringValue:dict[@"img1v1Url"]]) size:400];
    return artist;
}

+ (nullable SPAlbum *)albumFromJSON:(nullable NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    NSString *ident = [self stringValue:dict[@"id"]];
    NSString *name = [self stringValue:dict[@"name"]];
    if (name.length == 0) return nil;

    SPAlbum *album = [SPAlbum new];
    album.identifier = ident ?: @"0";
    album.name = name;
    NSString *pic = [self stringValue:dict[@"picUrl"]] ?: [self stringValue:dict[@"blurPicUrl"]];
    album.coverURL = [self normalizedCoverURL:pic size:500];
    album.colorHex = [self paletteHexForSeed:album.identifier];
    album.albumType = [self mappedAlbumType:dict[@"type"]];
    album.releaseYear = [self yearFromTimestampMs:[self longLongValue:dict[@"publishTime"]]];

    NSArray *rawArtists = [self arrayValue:dict[@"artists"]];
    NSMutableArray<SPArtist *> *artists = [NSMutableArray array];
    for (id item in rawArtists) {
        SPArtist *ar = [self artistFromJSON:[self dictValue:item]];
        if (ar) [artists addObject:ar];
    }
    if (artists.count == 0) {
        SPArtist *single = [self artistFromJSON:[self dictValue:dict[@"artist"]]];
        if (single) [artists addObject:single];
    }
    album.artists = artists;
    return album;
}

+ (nullable SPTrack *)trackFromJSON:(nullable NSDictionary *)dict fallbackAlbum:(nullable SPAlbum *)fallbackAlbum {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    NSString *ident = [self stringValue:dict[@"id"]];
    NSString *name = [self stringValue:dict[@"name"]];
    if (ident.length == 0 || name.length == 0) return nil;

    SPTrack *track = [SPTrack new];
    track.identifier = ident;
    track.name = name;

    long long dtMs = [self longLongValue:dict[@"dt"]];
    if (dtMs <= 0) dtMs = [self longLongValue:dict[@"duration"]];
    track.duration = dtMs > 0 ? (dtMs / 1000.0) : 0.0;

    NSArray *rawArtists = [self arrayValue:dict[@"ar"]] ?: [self arrayValue:dict[@"artists"]];
    NSMutableArray<SPArtist *> *artists = [NSMutableArray array];
    for (id item in rawArtists) {
        SPArtist *ar = [self artistFromJSON:[self dictValue:item]];
        if (ar) [artists addObject:ar];
    }
    track.artists = artists;

    NSDictionary *alDict = [self dictValue:dict[@"al"]] ?: [self dictValue:dict[@"album"]];
    SPAlbum *parsedAlbum = [self albumFromJSON:alDict];
    if (parsedAlbum) {
        if (parsedAlbum.coverURL.length == 0) parsedAlbum.coverURL = fallbackAlbum.coverURL;
        if (parsedAlbum.artists.count == 0) parsedAlbum.artists = artists.count > 0 ? artists : fallbackAlbum.artists;
        track.album = parsedAlbum;
    } else {
        track.album = fallbackAlbum;
    }

    NSString *pic = parsedAlbum.coverURL ?: [self normalizedCoverURL:[self stringValue:dict[@"picUrl"]] size:500];
    if (pic.length == 0) pic = fallbackAlbum.coverURL;
    track.trackCoverURL = pic;
    track.audioURL = nil; // 播放前实时通过 /song/url/v1 解析
    return track;
}

+ (nullable SPPlaylist *)playlistFromJSON:(nullable NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    NSString *ident = [self stringValue:dict[@"id"]];
    NSString *name = [self stringValue:dict[@"name"]];
    if (ident.length == 0 || name.length == 0) return nil;

    SPPlaylist *pl = [SPPlaylist new];
    pl.identifier = ident;
    pl.name = name;
    pl.desc = [self stringValue:dict[@"description"]] ?: [self stringValue:dict[@"copywriter"]];
    NSString *rawCover = [self stringValue:dict[@"coverImgUrl"]] ?: [self stringValue:dict[@"picUrl"]];
    pl.coverURL = [self normalizedCoverURL:rawCover size:500];
    pl.colorHex = [self paletteHexForSeed:ident];

    NSDictionary *creator = [self dictValue:dict[@"creator"]];
    pl.creatorName = [self stringValue:creator[@"nickname"]] ?: @"网易云音乐";
    pl.creatorUserId = [self stringValue:creator[@"userId"]] ?: [self stringValue:dict[@"userId"]];

    long long count = [self longLongValue:dict[@"subscribedCount"]];
    if (count <= 0) count = [self longLongValue:dict[@"bookCount"]];
    if (count <= 0) count = [self longLongValue:dict[@"playCount"]];
    pl.followerCount = (NSInteger)MIN(count, (long long)NSIntegerMax);

    NSArray *rawTracks = [self arrayValue:dict[@"tracks"]];
    if (rawTracks.count > 0) {
        pl.tracks = [self tracksFromArray:rawTracks fallbackAlbum:nil];
    }
    return pl;
}

+ (nullable SPPlaylist *)podcastRadioFromJSON:(nullable NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    NSString *rawId = [self stringValue:dict[@"id"]];
    NSString *name = [self stringValue:dict[@"name"]];
    if (rawId.length == 0 || name.length == 0) return nil;

    SPPlaylist *pl = [SPPlaylist new];
    pl.identifier = [rawId hasPrefix:@"dj:"] ? rawId : [@"dj:" stringByAppendingString:rawId];
    pl.name = name;
    pl.desc = [self stringValue:dict[@"rcmdtext"]]
           ?: [self stringValue:dict[@"copywriter"]]
           ?: [self stringValue:dict[@"desc"]]
           ?: [self stringValue:dict[@"category"]];
    pl.coverURL = [self normalizedCoverURL:[self stringValue:dict[@"picUrl"]] size:500];
    pl.colorHex = [self paletteHexForSeed:pl.identifier];

    NSDictionary *dj = [self dictValue:dict[@"dj"]];
    pl.creatorName = [self stringValue:dj[@"nickname"]] ?: [self stringValue:dict[@"category"]] ?: @"播客电台";

    long long count = [self longLongValue:dict[@"subCount"]];
    if (count <= 0) count = [self longLongValue:dict[@"playCount"]];
    pl.followerCount = (NSInteger)MIN(count, (long long)NSIntegerMax);
    return pl;
}

+ (nullable SPTrack *)podcastEpisodeTrackFromJSON:(nullable NSDictionary *)dict fallbackRadio:(nullable SPPlaylist *)radio {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *mainSong = [self dictValue:dict[@"mainSong"]];
    NSString *songId = [self stringValue:mainSong[@"id"]] ?: [self stringValue:dict[@"id"]];
    NSString *name = [self stringValue:dict[@"name"]] ?: [self stringValue:mainSong[@"name"]];
    if (songId.length == 0 || name.length == 0) return nil;

    SPTrack *track = [SPTrack new];
    track.identifier = songId;
    track.name = name;

    long long dtMs = [self longLongValue:dict[@"duration"]];
    if (dtMs <= 0) dtMs = [self longLongValue:mainSong[@"duration"]];
    track.duration = dtMs > 0 ? (dtMs / 1000.0) : 0.0;

    NSDictionary *dj = [self dictValue:dict[@"dj"]];
    NSString *hostName = [self stringValue:dj[@"nickname"]] ?: radio.creatorName ?: @"播客主播";
    SPArtist *hostArtist = [SPArtist new];
    hostArtist.identifier = [self stringValue:dj[@"userId"]] ?: radio.identifier ?: songId;
    hostArtist.name = hostName;
    hostArtist.coverURL = [self normalizedCoverURL:[self stringValue:dj[@"avatarUrl"]] size:300];
    track.artists = @[hostArtist];

    NSString *epCover = [self normalizedCoverURL:([self stringValue:dict[@"coverUrl"]] ?: [self stringValue:dict[@"blurCoverUrl"]] ?: radio.coverURL) size:500];
    track.trackCoverURL = epCover;

    SPAlbum *syntheticAlbum = [SPAlbum new];
    NSDictionary *radioDict = [self dictValue:dict[@"radio"]];
    syntheticAlbum.identifier = [self stringValue:radioDict[@"id"]] ?: radio.identifier ?: songId;
    syntheticAlbum.name = [self stringValue:radioDict[@"name"]] ?: radio.name ?: @"播客电台";
    syntheticAlbum.coverURL = epCover;
    syntheticAlbum.colorHex = radio.colorHex;
    syntheticAlbum.artists = @[hostArtist];
    track.album = syntheticAlbum;
    return track;
}

+ (NSArray<SPPlaylist *> *)playlistsFromArray:(nullable NSArray *)array {
    NSMutableArray<SPPlaylist *> *list = [NSMutableArray array];
    for (id item in [self arrayValue:array]) {
        SPPlaylist *pl = [self playlistFromJSON:[self dictValue:item]];
        if (pl) [list addObject:pl];
    }
    return list;
}

+ (NSArray<SPPlaylist *> *)podcastRadiosFromArray:(nullable NSArray *)array {
    NSMutableArray<SPPlaylist *> *list = [NSMutableArray array];
    for (id item in [self arrayValue:array]) {
        SPPlaylist *pl = [self podcastRadioFromJSON:[self dictValue:item]];
        if (pl) [list addObject:pl];
    }
    return list;
}

+ (NSArray<SPTrack *> *)podcastEpisodesFromArray:(nullable NSArray *)array fallbackRadio:(nullable SPPlaylist *)radio {
    NSMutableArray<SPTrack *> *list = [NSMutableArray array];
    for (id item in [self arrayValue:array]) {
        SPTrack *track = [self podcastEpisodeTrackFromJSON:[self dictValue:item] fallbackRadio:radio];
        if (track) [list addObject:track];
    }
    return list;
}

+ (NSArray<SPAlbum *> *)albumsFromArray:(nullable NSArray *)array {
    NSMutableArray<SPAlbum *> *list = [NSMutableArray array];
    for (id item in [self arrayValue:array]) {
        SPAlbum *al = [self albumFromJSON:[self dictValue:item]];
        if (al) [list addObject:al];
    }
    return list;
}

+ (NSArray<SPArtist *> *)artistsFromArray:(nullable NSArray *)array {
    NSMutableArray<SPArtist *> *list = [NSMutableArray array];
    for (id item in [self arrayValue:array]) {
        SPArtist *ar = [self artistFromJSON:[self dictValue:item]];
        if (ar) [list addObject:ar];
    }
    return list;
}

+ (NSArray<SPTrack *> *)tracksFromArray:(nullable NSArray *)array fallbackAlbum:(nullable SPAlbum *)fallbackAlbum {
    NSMutableArray<SPTrack *> *list = [NSMutableArray array];
    for (id item in [self arrayValue:array]) {
        SPTrack *track = [self trackFromJSON:[self dictValue:item] fallbackAlbum:fallbackAlbum];
        if (track) [list addObject:track];
    }
    return list;
}

+ (NSArray<SPSearchCategory *> *)categoriesFromHotTags:(nullable NSArray *)tags
                                             coverURLs:(nullable NSArray<NSString *> *)covers {
    static NSArray<NSString *> *colors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colors = @[
            @"#E13300", @"#1E3264", @"#8D67AB", @"#148A08",
            @"#BA5D07", @"#E8115B", @"#503750", @"#0D73EC",
            @"#477D95", @"#AF2896", @"#27856A", @"#7358FF"
        ];
    });
    NSMutableArray<SPSearchCategory *> *cats = [NSMutableArray array];
    NSArray *raw = [self arrayValue:tags];
    for (NSUInteger i = 0; i < raw.count && cats.count < 12; i++) {
        NSDictionary *dict = [self dictValue:raw[i]];
        NSString *name = [self stringValue:dict[@"name"]];
        if (name.length == 0) continue;
        SPSearchCategory *cat = [SPSearchCategory new];
        cat.identifier = [self stringValue:dict[@"id"]] ?: [NSString stringWithFormat:@"cat_%lu", (unsigned long)i];
        cat.name = name;
        cat.colorHex = colors[cats.count % colors.count];
        if (covers.count > 0) {
            cat.coverURL = covers[cats.count % covers.count];
        }
        [cats addObject:cat];
    }
    return cats;
}

@end
