Pod::Spec.new do |s|
  s.name             = 'ChatSharedDataManager'
  s.version          = '1.0.4'
  s.summary          = 'Shared data manager for chat app and extensions'
  s.description      = <<-DESC
ChatSharedDataManager provides unified access to app data across main app,
notification extensions, and other app extensions. Handles JWT tokens,
contacts, and API calls with proper multi-process support.
                       DESC

  s.homepage         = 'https://github.com/qusaieilouti99/chat-shared-swift-module'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Qusai Eilouti' => 'qusaieilouti@gmail.com' }
  s.source           = { :git => 'https://github.com/qusaieilouti99/chat-shared-swift-module.git', :tag => s.version.to_s }

  s.ios.deployment_target = '16.0'
  s.swift_version = '5.0'

  s.source_files = 'Sources/**/*'

  # Dependencies
  s.dependency 'MMKV'
  s.dependency 'RealmSwift', '~> 10.49.2'

  # Framework requirements
  s.frameworks = 'Foundation'

  # Pod configuration
  s.requires_arc = true
  s.static_framework = true
end