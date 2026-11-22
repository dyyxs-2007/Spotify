//
//  SPPlaylist.m
//  Spotify
//

#import "SPPlaylist.h"
#import "SPTrack.h"
#import <YYModel/YYModel.h>

NSString * const SPLikedSongsPlaylistId = @"liked";

@implementation SPPlaylist

+ (NSDictionary<NSString *, id> *)modelContainerPropertyGenericClass {
    return @{ @"tracks": SPTrack.class };
}

- (BOOL)isLikedSongs { return [self.identifier isEqualToString:SPLikedSongsPlaylistId]; }
- (BOOL)isPodcast { return [self.identifier hasPrefix:@"dj:"]; }

- (SPMediaType)mediaType { return SPMediaTypePlaylist; }
- (NSString *)title { return self.name ?: @""; }
- (NSString *)subtitle {
    if (self.isLikedSongs) return [NSString stringWithFormat:@"歌单 · %lu 首歌曲", (unsigned long)self.tracks.count];
    if (self.isPodcast) return self.creatorName.length ? [NSString stringWithFormat:@"播客 · %@", self.creatorName] : @"播客电台";
    if ([self.identifier hasPrefix:@"user_pl_"]) return [NSString stringWithFormat:@"自建歌单 · %lu 首", (unsigned long)self.tracks.count];
    return self.creatorName.length ? [NSString stringWithFormat:@"歌单 · %@", self.creatorName] : @"歌单";
}
- (UIColor *)themeColor { return [UIColor sp_colorWithHexString:self.colorHex]; }

@end
