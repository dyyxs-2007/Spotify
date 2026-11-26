//
//  SPUser.m
//  Spotify
//

#import "SPUser.h"

@implementation SPUser

- (NSString *)avatarInitial {
    NSString *source = self.nickname.length > 0 ? self.nickname : self.account;
    if (source.length == 0) return @"S";
    NSRange firstRange = [source rangeOfComposedCharacterSequenceAtIndex:0];
    NSString *first = [source substringWithRange:firstRange];
    return first.uppercaseString;
}

@end
