//
//  SPPlayQueue.m
//  Spotify
//

#import "SPPlayQueue.h"

@interface SPPlayQueue ()
@property (nonatomic, copy) NSArray<SPTrack *> *originalTracks;
@property (nonatomic, copy) NSArray<SPTrack *> *playOrderTracks;
@property (nonatomic, assign) NSInteger currentIndex;
@end

@implementation SPPlayQueue

- (instancetype)init {
    if (self = [super init]) {
        _originalTracks = @[];
        _playOrderTracks = @[];
        _currentIndex = -1;
    }
    return self;
}

- (SPTrack *)currentTrack {
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.playOrderTracks.count) return nil;
    return self.playOrderTracks[self.currentIndex];
}

- (SPTrack *)previousTrack {
    if (self.playOrderTracks.count < 2 || self.currentIndex < 0) return nil;
    NSInteger count = (NSInteger)self.playOrderTracks.count;
    NSInteger prevIdx = (self.currentIndex - 1 + count) % count;
    return self.playOrderTracks[prevIdx];
}

- (SPTrack *)nextTrack {
    if (self.playOrderTracks.count < 2 || self.currentIndex < 0) return nil;
    NSInteger count = (NSInteger)self.playOrderTracks.count;
    NSInteger nextIdx = (self.currentIndex + 1) % count;
    return self.playOrderTracks[nextIdx];
}

- (NSArray<SPTrack *> *)upNextTracks {
    if (self.currentIndex < 0 || self.currentIndex + 1 >= (NSInteger)self.playOrderTracks.count) return @[];
    NSRange range = NSMakeRange(self.currentIndex + 1, self.playOrderTracks.count - self.currentIndex - 1);
    return [self.playOrderTracks subarrayWithRange:range];
}

- (void)replaceWithTracks:(NSArray<SPTrack *> *)tracks startIndex:(NSUInteger)startIndex {
    if (tracks.count == 0 || startIndex >= tracks.count) {
        self.originalTracks = @[];
        self.playOrderTracks = @[];
        self.currentIndex = -1;
        return;
    }
    self.originalTracks = [tracks copy];
    if (self.shuffleEnabled) {
        SPTrack *anchor = tracks[startIndex];
        self.playOrderTracks = [self shuffledTracksFrom:tracks anchor:anchor anchorIndex:startIndex];
        self.currentIndex = 0;
    } else {
        self.playOrderTracks = self.originalTracks;
        self.currentIndex = (NSInteger)startIndex;
    }
}

- (void)setShuffleEnabled:(BOOL)shuffleEnabled {
    if (_shuffleEnabled == shuffleEnabled) return;
    _shuffleEnabled = shuffleEnabled;

    if (self.originalTracks.count == 0) return;
    SPTrack *current = self.currentTrack;

    if (shuffleEnabled) {
        NSUInteger anchorIdx = current ? [self.originalTracks indexOfObject:current] : NSNotFound;
        self.playOrderTracks = [self shuffledTracksFrom:self.originalTracks anchor:current anchorIndex:anchorIdx];
        self.currentIndex = 0;
    } else {
        self.playOrderTracks = self.originalTracks;
        if (current) {
            NSUInteger idx = [self.originalTracks indexOfObject:current];
            if (idx != NSNotFound) {
                self.currentIndex = (NSInteger)idx;
            } else {
                // 当前曲目可能是通过"下一首播放"临时插队的，插入首位以保持连贯
                NSMutableArray *merged = [self.originalTracks mutableCopy];
                [merged insertObject:current atIndex:0];
                self.playOrderTracks = [merged copy];
                self.currentIndex = 0;
            }
        } else {
            self.currentIndex = 0;
        }
    }
}

- (void)insertNextTrack:(SPTrack *)track {
    if (!track) return;
    if (self.playOrderTracks.count == 0) {
        self.originalTracks = @[track];
        self.playOrderTracks = @[track];
        self.currentIndex = 0;
        return;
    }
    NSMutableArray *mutable = [self.playOrderTracks mutableCopy];
    NSInteger insertIndex = MIN(MAX(self.currentIndex + 1, 0), (NSInteger)mutable.count);
    [mutable insertObject:track atIndex:insertIndex];
    self.playOrderTracks = [mutable copy];
}

- (SPTrack *)advanceToNextByAutoPlay:(BOOL)isAutoPlay {
    if (self.playOrderTracks.count == 0) return nil;
    if (isAutoPlay && self.repeatMode == SPRepeatModeOne) {
        return self.currentTrack;
    }
    if (self.currentIndex + 1 < (NSInteger)self.playOrderTracks.count) {
        self.currentIndex += 1;
        return self.currentTrack;
    }
    if (!isAutoPlay || self.repeatMode == SPRepeatModeAll) {
        self.currentIndex = 0;
        return self.currentTrack;
    }
    return nil;
}

- (SPTrack *)retreatToPrevious {
    if (self.playOrderTracks.count == 0) return nil;
    NSInteger count = (NSInteger)self.playOrderTracks.count;
    self.currentIndex = (self.currentIndex - 1 + count) % count;
    return self.currentTrack;
}

- (SPTrack *)jumpToUpNextIndex:(NSUInteger)upNextIndex {
    NSInteger target = self.currentIndex + 1 + (NSInteger)upNextIndex;
    if (target < 0 || target >= (NSInteger)self.playOrderTracks.count) return nil;
    self.currentIndex = target;
    return self.currentTrack;
}

#pragma mark - Helpers

- (NSArray<SPTrack *> *)shuffledTracksFrom:(NSArray<SPTrack *> *)source
                                    anchor:(nullable SPTrack *)anchor
                               anchorIndex:(NSUInteger)anchorIndex {
    NSMutableArray<SPTrack *> *pool = [source mutableCopy];
    if (anchor && anchorIndex < pool.count) {
        [pool removeObjectAtIndex:anchorIndex];
    }
    // Fisher-Yates 洗牌
    for (NSUInteger i = pool.count; i > 1; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)i);
        [pool exchangeObjectAtIndex:i - 1 withObjectAtIndex:j];
    }
    if (anchor) {
        [pool insertObject:anchor atIndex:0];
    }
    return [pool copy];
}

@end
