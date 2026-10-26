Pod::Spec.new do |s|
  s.name = 'HLSPlaylist'
  s.version = '1.0.0'
  s.summary = 'A lossless Swift HLS parser and writer with RFC 3986 URI handling.'
  s.homepage = 'https://github.com/CreatureSurvive/HLSPlaylist'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = 'CreatureSurvive'
  s.source = { :git => 'https://github.com/CreatureSurvive/HLSPlaylist.git', :tag => s.version.to_s }
  s.source_files = 'Sources/HLSPlaylist/**/*.swift',
                  'Sources/CURIParser/src/*.c', 'Sources/CURIParser/include/**/*.h'
  s.public_header_files = 'Sources/CURIParser/include/**/*.h'
  s.header_mappings_dir = 'Sources/CURIParser/include'
  s.preserve_paths = 'Sources/CURIParser/LICENSE', 'Sources/CURIParser/README.md',
                     'Sources/CURIParser/src/*.h'
  s.pod_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) URI_NO_UNICODE URI_STATIC_BUILD',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/Sources/CURIParser/include"'
  }
  s.swift_version = '6.0'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.tvos.deployment_target = '15.0'
  s.watchos.deployment_target = '8.0'
  s.visionos.deployment_target = '1.0'
  s.framework = 'Foundation'
end
