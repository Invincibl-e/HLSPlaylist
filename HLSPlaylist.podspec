Pod::Spec.new do |s|
  s.name = 'HLSPlaylist'
  s.version = '1.0.0'
  s.summary = 'A lossless, pure-Swift parser and writer for HLS playlists.'
  s.homepage = 'https://github.com/CreatureSurvive/HLSPlaylist'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = 'CreatureSurvive'
  s.source = { :git => 'https://github.com/CreatureSurvive/HLSPlaylist.git', :tag => s.version.to_s }
  s.source_files = 'Sources/HLSPlaylist/**/*.swift'
  s.swift_version = '6.0'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.tvos.deployment_target = '15.0'
  s.watchos.deployment_target = '8.0'
  s.visionos.deployment_target = '1.0'
  s.framework = 'Foundation'
end
