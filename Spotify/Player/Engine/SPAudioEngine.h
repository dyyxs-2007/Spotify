//
//  SPAudioEngine.h
//  Spotify
//
//  音频播放内核协议：隔离具体底层播放器（AVPlayer / 第三方解码器等）。
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "SPPlayerService.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SPAudioEngine;

@protocol SPAudioEngineDelegate <NSObject>
- (void)audioEngine:(id<SPAudioEngine>)engine didChangeState:(SPPlaybackState)state;
- (void)audioEngine:(id<SPAudioEngine>)engine
didUpdateCurrentTime:(NSTimeInterval)currentTime
           duration:(NSTimeInterval)duration
       bufferedTime:(NSTimeInterval)bufferedTime;
- (void)audioEngineDidFinishPlaying:(id<SPAudioEngine>)engine;
- (void)audioEngine:(id<SPAudioEngine>)engine didFailWithError:(NSError *)error;
@end

@protocol SPAudioEngine <NSObject>

@property (nonatomic, weak, nullable) id<SPAudioEngineDelegate> delegate;
@property (nonatomic, assign, readonly) SPPlaybackState state;
@property (nonatomic, assign, readonly) NSTimeInterval currentTime;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly) NSTimeInterval bufferedTime;

- (void)loadURL:(NSURL *)url autoPlay:(BOOL)autoPlay;
- (void)loadAsset:(AVURLAsset *)asset autoPlay:(BOOL)autoPlay;
- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)time completion:(nullable void (^)(BOOL finished))completion;

@end

NS_ASSUME_NONNULL_END
