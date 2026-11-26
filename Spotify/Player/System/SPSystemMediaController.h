//
//  SPSystemMediaController.h
//  Spotify
//
//  系统媒体集成：AVAudioSession 后台播放与中断/拔出耳机处理、
//  MPNowPlayingInfoCenter 锁屏信息与封面、MPRemoteCommandCenter 锁屏/控制中心指令。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SPPlayerService;

@interface SPSystemMediaController : NSObject

- (instancetype)initWithPlayerService:(SPPlayerService *)playerService;

- (void)activateAudioSession;
- (void)updateNowPlayingInfo;
- (void)clearNowPlayingInfo;

@end

NS_ASSUME_NONNULL_END
