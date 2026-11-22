//
//  SPMockMusicSource.h
//  Spotify
//
//  本地 mock 数据源：读取 bundle 中的 mock_data.json，并模拟网络延迟。
//

#import <Foundation/Foundation.h>
#import "SPMusicDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPMockMusicSource : NSObject <SPMusicDataSource>

/// 模拟网络延迟（秒），默认 0.4
@property (nonatomic, assign) NSTimeInterval simulatedLatency;

@end

NS_ASSUME_NONNULL_END
