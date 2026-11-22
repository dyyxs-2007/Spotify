//
//  SPFeedModels.m
//  Spotify
//

#import "SPFeedModels.h"

@implementation SPHomeSection
@end

@implementation SPSearchCategory
@end

@implementation SPSearchResult

- (instancetype)init {
    if (self = [super init]) {
        _keyword = @"";
        _tracks = @[]; _artists = @[]; _albums = @[]; _playlists = @[];
    }
    return self;
}

- (BOOL)isEmpty {
    return self.tracks.count + self.artists.count + self.albums.count + self.playlists.count == 0;
}

@end
