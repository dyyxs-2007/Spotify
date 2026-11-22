# Spotify 仿写（Objective-C + UIKit）

基于 Objective-C 和 UIKit 纯代码构建的 Spotify 风格 iOS 音乐客户端，采用模块化分层架构（数据源与播放器均与 UI 解耦）。

## 运行方式

1. 确保已安装 Xcode、CocoaPods 与 XcodeGen（如修改了目录结构）。
2. 在项目根目录执行：
   ```bash
   xcodegen generate && pod install
   ```
3. 使用 Xcode 打开 **`Spotify.xcworkspace`**（不要打开 `.xcodeproj`），选择任意 iOS 15+ 模拟器（例如 `iPhone 16 Pro`），`Cmd + R` 运行。

## 技术栈与依赖

- **Masonry**：纯代码 Auto Layout 约束 DSL
- **SDWebImage**：封面异步加载、内存/磁盘缓存与降采样
- **YYModel**：无侵入式 JSON 转模型映射

## 目录概览

- `Spotify/App/`：应用入口、`SPRootViewController`（Tab + 悬浮迷你播放条）、`SPNavigationController`
- `Spotify/Core/`：主题 Token（`SPTheme`）、扩展、通用组件（渐变、列表行、卡片、Toast）
- `Spotify/Models/`：与数据源无关的领域模型（`SPTrack` / `SPAlbum` / `SPPlaylist` / `SPArtist`）
- `Spotify/Data/`：`SPMusicDataSource` 协议、`SPMusicRepository` 门面与本地 `SPMockMusicSource`
- `Spotify/Player/`：`SPPlayerService` 播放器门面与多播观察者机制
- `Spotify/Modules/`：`Home`、`Search`、`Library`、`Detail`、`MiniPlayer`、`NowPlaying`
