//
//  SPUser.m
//  Spotify
//

#import "SPUser.h"

@implementation SPUser

- (NSString *)avatarInitial {
    NSString *source = self.nickname.length > 0 ? self.nickname : self.account;
    if (source.length == 0) return @"S";
    NSString *first = [source substringToIndex:1];
    return first.uppercaseString;
}

@end
