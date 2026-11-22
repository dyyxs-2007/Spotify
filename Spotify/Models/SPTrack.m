//
//  SPTrack.m
//  Spotify
//

#import "SPTrack.h"
#import "SPArtist.h"
#import "SPAlbum.h"
#import <YYModel/YYModel.h>

@implementation SPTrack

+ (NSDictionary<NSString *, id> *)modelContainerPropertyGenericClass {
    return @{ @"artists": SPArtist.class };
}

+ (NSDictionary<NSString *, id> *)modelCustomPropertyMapper {
    return @{ @"trackCoverURL": @"coverURL" };
}

- (NSString *)artistNames {
    return [[self.artists valueForKey:@"name"] componentsJoinedByString:@", "] ?: @"";
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:SPTrack.class]) return NO;
    return [self.identifier isEqualToString:((SPTrack *)object).identifier];
}

- (NSUInteger)hash { return self.identifier.hash; }

#pragma mark - SPMediaItem
- (SPMediaType)mediaType { return SPMediaTypeTrack; }
- (NSString *)title { return self.name ?: @""; }
- (NSString *)subtitle { return [self artistNames]; }
- (NSString *)coverURL { return self.trackCoverURL.length ? self.trackCoverURL : self.album.coverURL; }
- (UIColor *)themeColor { return self.album.themeColor; }

@end
