//
//  UIImageView+SPCover.m
//  Spotify
//

#import "UIImageView+SPCover.h"
#import "UIImage+SPDominantColor.h"
#import "SPPlaylist.h"
#import <objc/runtime.h>

static const void *SPCoverCurrentURLKey = &SPCoverCurrentURLKey;

@implementation UIImageView (SPCover)

- (nullable NSString *)sp_currentURLString {
    return objc_getAssociatedObject(self, SPCoverCurrentURLKey);
}

- (void)sp_setCurrentURLString:(nullable NSString *)urlString {
    objc_setAssociatedObject(self, SPCoverCurrentURLKey, urlString, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)sp_applyCoverChrome {
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.layer.borderColor = [SPTheme.coverBorderColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.layer.borderColor = [SPTheme.coverBorderColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    }
}

- (void)sp_setImageWithURLString:(NSString *)urlString placeholderColor:(UIColor *)color {
    [self sp_setImageWithURLString:urlString placeholderColor:color completion:nil];
}

- (void)sp_setImageWithURLString:(NSString *)urlString
                placeholderColor:(UIColor *)color
                      completion:(void (^)(UIImage * _Nullable image))completion {
    [self sp_applyCoverChrome];

    if (urlString.length > 0 && [[self sp_currentURLString] isEqualToString:urlString] && self.image != nil) {
        if (completion) completion(self.image);
        return;
    }

    [self sp_setCurrentURLString:urlString];
    self.backgroundColor = color ? [color sp_darkenedBy:0.35] : SPTheme.highlightColor;
    self.sd_imageTransition = nil;

    NSURL *url = urlString.length ? [NSURL URLWithString:urlString] : nil;
    if (!url) {
        [self sd_cancelCurrentImageLoad];
        self.image = nil;
        if (completion) completion(nil);
        return;
    }

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat side = width > 0 ? MIN(width * UIScreen.mainScreen.scale, 600) : 600;
    NSDictionary *context = @{ SDWebImageContextImageThumbnailPixelSize: @(CGSizeMake(side, side)) };

    __weak typeof(self) weakSelf = self;
    [self sd_setImageWithURL:url
            placeholderImage:nil
                     options:SDWebImageRetryFailed | SDWebImageAvoidAutoSetImage
                     context:context
                    progress:nil
                   completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (image) {
            if (cacheType == SDImageCacheTypeNone && !UIAccessibilityIsReduceMotionEnabled()) {
                [UIView transitionWithView:strongSelf
                                  duration:0.18
                                   options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                                animations:^{
                    strongSelf.image = image;
                } completion:nil];
            } else {
                // 命中内存/磁盘缓存时 0ms 直接赋值，彻底避免闪烁
                strongSelf.image = image;
            }
        }
        if (completion) completion(image);
    }];
}

- (void)sp_setCoverWithItem:(id<SPMediaItem>)item {
    [self sp_setCoverWithItem:item dominantColorCompletion:nil];
}

- (void)sp_setCoverWithItem:(id<SPMediaItem>)item
    dominantColorCompletion:(void (^)(UIColor *))completion {
    [self sp_applyCoverChrome];
    if ([item isKindOfClass:SPPlaylist.class] && ((SPPlaylist *)item).isLikedSongs) {
        [self sd_cancelCurrentImageLoad];
        [self sp_setCurrentURLString:SPLikedSongsPlaylistId];
        UIImage *likedImage = [UIImageView sp_likedSongsCoverImage];
        self.image = likedImage;
        if (completion) {
            [UIImage sp_extractDominantColorForImage:likedImage cacheKey:SPLikedSongsPlaylistId completion:completion];
        }
        return;
    }

    if ([item isKindOfClass:SPPlaylist.class] && item.coverURL.length == 0) {
        [self sd_cancelCurrentImageLoad];
        [self sp_setCurrentURLString:[@"user_pl_placeholder_" stringByAppendingString:item.identifier ?: @""]];
        UIImage *fallback = [UIImageView sp_defaultPlaylistCoverImageForColor:item.themeColor];
        self.image = fallback;
        if (completion) {
            completion(item.themeColor ? [item.themeColor sp_clampedForDarkBackground] : [UIColor sp_colorWithHex:0x1E3A5F]);
        }
        return;
    }

    NSString *cacheKey = item.coverURL.length ? item.coverURL : item.identifier;
    [self sp_setImageWithURLString:item.coverURL
                  placeholderColor:item.themeColor
                        completion:^(UIImage *image) {
        if (!completion) return;
        if (image) {
            [UIImage sp_extractDominantColorForImage:image cacheKey:cacheKey completion:completion];
        } else if (item.themeColor) {
            completion([item.themeColor sp_clampedForDarkBackground]);
        }
    }];
    self.layer.cornerCurve = (item.mediaType == SPMediaTypeArtist) ? kCACornerCurveCircular : kCACornerCurveContinuous;
}

+ (UIImage *)sp_likedSongsCoverImage {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGSize size = CGSizeMake(300, 300);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            NSArray *colors = @[(__bridge id)[UIColor sp_colorWithHex:0x450AF5].CGColor,
                                (__bridge id)[UIColor sp_colorWithHex:0x8E8EE5].CGColor,
                                (__bridge id)[UIColor sp_colorWithHex:0xC4EFD9].CGColor];
            CGFloat locations[] = {0, 0.6, 1};
            CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locations);
            CGContextDrawLinearGradient(ctx.CGContext, gradient, CGPointZero, CGPointMake(size.width, size.height), 0);
            CGGradientRelease(gradient);
            CGColorSpaceRelease(space);

            UIImage *heart = [[SPTheme symbol:@"heart.fill" size:96 weight:UIImageSymbolWeightBold]
                              imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
            CGRect rect = CGRectMake((size.width - heart.size.width) / 2, (size.height - heart.size.height) / 2,
                                     heart.size.width, heart.size.height);
            [heart drawInRect:rect];
        }];
    });
    return image;
}

+ (UIImage *)sp_defaultPlaylistCoverImageForColor:(nullable UIColor *)themeColor {
    UIColor *base = themeColor ?: [UIColor sp_colorWithHex:0x1E3A5F];
    UIColor *darker = [base sp_darkenedBy:0.45];
    CGSize size = CGSizeMake(300, 300);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(__bridge id)base.CGColor, (__bridge id)darker.CGColor];
        CGFloat locations[] = {0, 1};
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locations);
        CGContextDrawLinearGradient(ctx.CGContext, gradient, CGPointZero, CGPointMake(size.width, size.height), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);

        UIImage *icon = [[SPTheme symbol:@"music.note.list" size:86 weight:UIImageSymbolWeightMedium]
                         imageWithTintColor:[UIColor colorWithWhite:1 alpha:0.88] renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGRect rect = CGRectMake((size.width - icon.size.width) / 2, (size.height - icon.size.height) / 2,
                                 icon.size.width, icon.size.height);
        [icon drawInRect:rect];
    }];
}

@end
