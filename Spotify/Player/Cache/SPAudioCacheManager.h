//
//  SPAudioCacheManager.h
//  Spotify
//
//  多级音频 LRU 缓存与上下首预加载管理器：
//  - L1 内存热缓存：SPLRUCache（已解析 URL + 预热好的 AVURLAsset）
//  - L2 本地磁盘 LRU 缓存：音频文件（<trackId>.mp3），按 LRU 顺序与 200MB 上限淘汰
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "SPTrack.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPAudioCacheManager : NSObject

+ (instancetype)shared;

@property (nonatomic, assign, readonly) NSUInteger diskCacheBytes;
@property (nonatomic, assign, readonly) NSUInteger diskCachedTrackCount;
@property (nonatomic, assign, readonly) NSUInteger memoryAssetCount;
@property (nonatomic, assign, readonly) NSUInteger resolvedURLCount;
@property (nonatomic, assign, readonly) NSUInteger totalHitCount;
@property (nonatomic, assign, readonly) NSUInteger totalRequestCount;

/// 获取可立即播放的 AVURLAsset（优先 L2 磁盘文件，其次 L1 内存预热 Asset，最后实时请求并后台落盘）
- (void)resolvePlayableAssetForTrack:(SPTrack *)track
                          completion:(void (^)(AVURLAsset *_Nullable asset, BOOL isCacheHit, NSError *_Nullable error))completion;

/// 后台预加载相邻曲目（下一首 / 上一首）：预热 L1 AVURLAsset + 下载到 L2 磁盘 LRU
- (void)preloadTracks:(NSArray<SPTrack *> *)tracks;

/// 判断某首歌曲是否已在 L1 内存或 L2 磁盘就绪
- (BOOL)hasCachedTrack:(SPTrack *)track;

/// 仅清空 L1 内存缓存（切换数据源时保留已落盘音频）
- (void)clearMemoryCaches;

/// 清空 L1 与 L2 音频缓存
- (void)clearAllCaches;

@end

NS_ASSUME_NONNULL_END
