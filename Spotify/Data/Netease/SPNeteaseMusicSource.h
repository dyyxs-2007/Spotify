//
//  SPNeteaseMusicSource.h
//  Spotify
//
//  网易云音乐真实 API 数据源实现（基于 NeteaseCloudMusicApi）。
//

#import <Foundation/Foundation.h>
#import "SPMusicDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPNeteaseMusicSource : NSObject <SPMusicDataSource>

- (instancetype)initWithBaseURLString:(NSString *)baseURLString;

@end

NS_ASSUME_NONNULL_END
