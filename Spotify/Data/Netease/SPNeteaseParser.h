//
//  SPNeteaseParser.h
//  Spotify
//
//  网易云音乐 API JSON 响应与领域模型映射工具（含 NSNull 防护与封面尺寸规范化）。
//

#import <Foundation/Foundation.h>
#import "SPFeedModels.h"
#import "SPTrack.h"
#import "SPAlbum.h"
#import "SPPlaylist.h"
#import "SPArtist.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPNeteaseParser : NSObject

+ (nullable NSString *)stringValue:(nullable id)val;
+ (nullable NSDictionary *)dictValue:(nullable id)val;
+ (nullable NSArray *)arrayValue:(nullable id)val;

/// 升级 http -> https，并对 126 图床自动附加 ?param=NxN 缩略图参数
+ (nullable NSString *)normalizedCoverURL:(nullable NSString *)rawURL size:(NSInteger)px;

+ (nullable SPArtist *)artistFromJSON:(nullable NSDictionary *)dict;
+ (nullable SPAlbum *)albumFromJSON:(nullable NSDictionary *)dict;
+ (nullable SPTrack *)trackFromJSON:(nullable NSDictionary *)dict fallbackAlbum:(nullable SPAlbum *)fallbackAlbum;
+ (nullable SPPlaylist *)playlistFromJSON:(nullable NSDictionary *)dict;
+ (nullable SPPlaylist *)podcastRadioFromJSON:(nullable NSDictionary *)dict;
+ (nullable SPTrack *)podcastEpisodeTrackFromJSON:(nullable NSDictionary *)dict fallbackRadio:(nullable SPPlaylist *)radio;

+ (NSArray<SPPlaylist *> *)playlistsFromArray:(nullable NSArray *)array;
+ (NSArray<SPPlaylist *> *)podcastRadiosFromArray:(nullable NSArray *)array;
+ (NSArray<SPAlbum *> *)albumsFromArray:(nullable NSArray *)array;
+ (NSArray<SPArtist *> *)artistsFromArray:(nullable NSArray *)array;
+ (NSArray<SPTrack *> *)tracksFromArray:(nullable NSArray *)array fallbackAlbum:(nullable SPAlbum *)fallbackAlbum;
+ (NSArray<SPTrack *> *)podcastEpisodesFromArray:(nullable NSArray *)array fallbackRadio:(nullable SPPlaylist *)radio;

+ (NSArray<SPSearchCategory *> *)categoriesFromHotTags:(nullable NSArray *)tags
                                             coverURLs:(nullable NSArray<NSString *> *)covers;

@end

NS_ASSUME_NONNULL_END
