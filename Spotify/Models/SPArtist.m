//
//  SPArtist.m
//  Spotify
//

#import "SPArtist.h"

@implementation SPArtist

- (SPMediaType)mediaType { return SPMediaTypeArtist; }
- (NSString *)title { return self.name ?: @""; }
- (NSString *)subtitle { return @"艺人"; }
- (UIColor *)themeColor { return nil; }

@end
