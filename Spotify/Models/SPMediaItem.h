//
//  SPMediaItem.h
//  Spotify
//
//  所有可展示的"媒体项"（歌曲/专辑/歌单/艺人）的统一抽象。
//  UI 组件（卡片、列表行）只依赖这个协议，不关心具体模型类型。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPMediaType) {
    SPMediaTypeTrack = 0,
    SPMediaTypeAlbum,
    SPMediaTypePlaylist,
    SPMediaTypeArtist,
};

@protocol SPMediaItem <NSObject>

- (SPMediaType)mediaType;
- (NSString *)identifier;
- (NSString *)title;
/// 卡片副标题，如 "歌单 · Spotify"、"专辑 · 林知夏"
- (NSString *)subtitle;
- (nullable NSString *)coverURL;
/// 主题色（阶段一来自数据，阶段三改为封面取色）
- (nullable UIColor *)themeColor;

@end

NS_ASSUME_NONNULL_END
