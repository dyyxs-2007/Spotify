//
//  SPFeedModels.h
//  Spotify
//
//  页面级的聚合模型：首页分区、搜索分类、搜索结果。
//

#import <Foundation/Foundation.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@class SPTrack, SPAlbum, SPPlaylist, SPArtist;

typedef NS_ENUM(NSInteger, SPHomeCategory) {
    SPHomeCategoryAll = 0,
    SPHomeCategoryMusic = 1,
    SPHomeCategoryPodcast = 2,
};

typedef NS_ENUM(NSInteger, SPHomeSectionStyle) {
    SPHomeSectionStyleShortcut = 0, ///< 顶部两列快捷入口
    SPHomeSectionStyleCard,         ///< 横向滚动方形卡片
    SPHomeSectionStyleArtist,       ///< 横向滚动圆形艺人
};

@interface SPHomeSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) SPHomeSectionStyle style;
@property (nonatomic, copy) NSArray<id<SPMediaItem>> *items;
@end

@interface SPSearchCategory : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *colorHex;
@property (nonatomic, copy, nullable) NSString *coverURL;
@end

@interface SPSearchResult : NSObject
@property (nonatomic, copy) NSString *keyword;
@property (nonatomic, copy) NSArray<SPTrack *> *tracks;
@property (nonatomic, copy) NSArray<SPArtist *> *artists;
@property (nonatomic, copy) NSArray<SPAlbum *> *albums;
@property (nonatomic, copy) NSArray<SPPlaylist *> *playlists;
@property (nonatomic, readonly, getter=isEmpty) BOOL empty;
@end

NS_ASSUME_NONNULL_END
