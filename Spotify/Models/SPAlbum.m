//
//  SPAlbum.m
//  Spotify
//

#import "SPAlbum.h"
#import "SPArtist.h"
#import "SPTrack.h"
#import <YYModel/YYModel.h>

@implementation SPAlbum

+ (NSDictionary<NSString *, id> *)modelContainerPropertyGenericClass {
    return @{ @"artists": SPArtist.class, @"tracks": SPTrack.class };
}

- (NSString *)artistNames {
    return [[self.artists valueForKey:@"name"] componentsJoinedByString:@", "] ?: @"";
}

- (SPMediaType)mediaType { return SPMediaTypeAlbum; }
- (NSString *)title { return self.name ?: @""; }
- (NSString *)subtitle {
    NSString *artists = [self artistNames];
    return artists.length ? [NSString stringWithFormat:@"%@ · %@", self.albumType ?: @"专辑", artists] : (self.albumType ?: @"专辑");
}
- (UIColor *)themeColor { return [UIColor sp_colorWithHexString:self.colorHex]; }

@end
