//
//  SPMusicRepository.h
//  Spotify
//
//  数据层门面：持有当前数据源，对上层提供统一入口，并内置 L3 元数据与搜索结果 LRU 缓存。
//

#import <Foundation/Foundation.h>
#import "SPMusicDataSource.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SPMusicSourceDidChangeNotification;

@interface SPMusicRepository : NSObject <SPMusicDataSource>

+ (instancetype)shared;

/// 当前数据源，启动时注入；替换即切换音乐源并清理对应数据缓存
@property (nonatomic, strong) id<SPMusicDataSource> source;

/// L3 缓存命中统计
@property (nonatomic, assign, readonly) NSUInteger cacheHitCount;
@property (nonatomic, assign, readonly) NSUInteger cachedEntryCount;

/// 同步读取 L3 LRU 缓存（命中时在详情页首帧即可直接渲染，避免表头高度跳动）
- (nullable SPPlaylist *)cachedPlaylistForId:(NSString *)playlistId;
- (nullable SPAlbum *)cachedAlbumForId:(NSString *)albumId;

/// 强制绕过首页缓存刷新（下拉刷新用）
- (void)refreshHomeSectionsWithCompletion:(void (^)(NSArray<SPHomeSection *> *_Nullable sections, NSError *_Nullable error))completion;
- (void)refreshHomeSectionsForCategory:(SPHomeCategory)category
                            completion:(void (^)(NSArray<SPHomeSection *> *_Nullable sections, NSError *_Nullable error))completion;

- (void)clearMetadataCaches;

@end

NS_ASSUME_NONNULL_END
