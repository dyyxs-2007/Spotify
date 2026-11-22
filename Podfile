platform :ios, '15.0'
inhibit_all_warnings!

target 'Spotify' do
  # 纯代码 Auto Layout DSL
  pod 'Masonry', '~> 1.1'
  # 网络图片加载 / 缓存 / 渐显
  pod 'SDWebImage', '~> 5.19'
  # JSON -> Model，无侵入、性能好
  pod 'YYModel', '~> 1.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # 老库的 deployment target 过低会让新 Xcode 报错（libarclite 等），统一抬到 15.0
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
