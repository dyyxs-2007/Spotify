//
//  SPLyricModel.h
//  Spotify
//
//  歌词行与完整 LRC（含双语翻译）解析与实时时间轴索引模型。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPLyricLine : NSObject
@property (nonatomic, assign) NSTimeInterval time;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *translation;
@end

@interface SPLyricDocument : NSObject

@property (nonatomic, copy) NSArray<SPLyricLine *> *lines;
@property (nonatomic, assign) BOOL isSynced;
@property (nonatomic, assign) BOOL isInstrumental;
@property (nonatomic, assign, readonly) BOOL hasTranslation;

+ (instancetype)parseLRC:(nullable NSString *)lrcText
          translationLRC:(nullable NSString *)tlyricText;

- (NSInteger)activeLineIndexForTime:(NSTimeInterval)time;

@end

NS_ASSUME_NONNULL_END
