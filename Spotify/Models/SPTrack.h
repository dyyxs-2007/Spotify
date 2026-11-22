//
//  SPTrack.h
//  Spotify
//

#import <Foundation/Foundation.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@class SPArtist, SPAlbum;

@interface SPTrack : NSObject <SPMediaItem>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSArray<SPArtist *> *artists;
/// 精简版专辑信息（id / 名称 / 封面）
@property (nonatomic, strong, nullable) SPAlbum *album;
/// 时长（秒）
@property (nonatomic, assign) NSTimeInterval duration;
/// 单曲独立封面 URL（为空时自动回退到所属专辑封面）
@property (nonatomic, copy, nullable) NSString *trackCoverURL;
/// 播放地址。真实音乐源通常为空，需要播放前通过数据源解析（URL 有时效）
@property (nonatomic, copy, nullable) NSString *audioURL;

- (NSString *)artistNames;

@end

NS_ASSUME_NONNULL_END
