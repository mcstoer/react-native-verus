require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# Encryption-only Expo module over the Verus Swift SDK. The SDK sources, the
# Rust header and the XCFramework are gitignored build outputs. CocoaPods never
# runs prepare_command for the :path pods that autolinking creates, but it does
# evaluate this file, so the fetch runs from here: it installs the CI-built set
# pinned in ios-artifacts.lock after checking its sha256. To build them from
# source instead, run `RNV_BUILD_IOS=1 npm run update-sources` on a Mac.
ios_artifacts = ["ios/libzcashlc.xcframework", "ios/ZCashLightClientKit", "ios/zcashlc.h"]
missing_ios_artifacts = lambda do
  ios_artifacts.reject { |path| File.exist?(File.join(__dir__, path)) }
end
unless missing_ios_artifacts.call.empty?
  fetch = File.join(__dir__, "scripts", "fetch-ios-artifacts.sh")
  Pod::UI.puts "[react-native-verus] Fetching prebuilt iOS artifacts..."
  system("bash", fetch) || Pod::UI.warn("[react-native-verus] #{fetch} failed")
end
missing = missing_ios_artifacts.call
unless missing.empty? || ENV["RNV_ALLOW_MISSING_IOS_ARTIFACTS"] == "1"
  raise "[react-native-verus] Missing #{missing.join(', ')}. Fill ios-artifacts.lock " \
    "from the 'iOS artifacts' workflow, or build them on a Mac with " \
    "`RNV_BUILD_IOS=1 npm run update-sources`. Set RNV_ALLOW_MISSING_IOS_ARTIFACTS=1 " \
    "to skip this check (the app will not compile)."
end

Pod::Spec.new do |s|
  s.name         = package['name']
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = package['homepage']
  s.license      = package['license']
  s.authors      = package['author']

  s.platform     = :ios, "16.4"
  # Ignored for :path pods, which is how autolinking installs this one.
  s.source       = { :git => "https://github.com/mcstoer/react-native-verus.git" }
  s.static_framework = true

  s.source_files =
    "ios/VerusCryptoModule.swift",
    "ios/zcashlc.h",
    "ios/ZCashLightClientKit/**/*.swift"

  s.vendored_frameworks = "ios/libzcashlc.xcframework"
  s.libraries = "z", "sqlite3", "c++"
  s.preserve_paths = "ios/libzcashlc.xcframework"

  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS'   => '$(inherited) $(PODS_CONFIGURATION_BUILD_DIR) $(PODS_XCFRAMEWORKS_BUILD_DIR)/libzcashlc',
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) $(PODS_CONFIGURATION_BUILD_DIR) $(PODS_XCFRAMEWORKS_BUILD_DIR)'
  }

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'         => 'YES',
    'HEADER_SEARCH_PATHS'    => '$(inherited) $(PODS_TARGET_SRCROOT)/ios $(PODS_XCFRAMEWORKS_BUILD_DIR)/libzcashlc/**',
    'LIBRARY_SEARCH_PATHS'   => '$(inherited) $(PODS_CONFIGURATION_BUILD_DIR) $(PODS_XCFRAMEWORKS_BUILD_DIR)/libzcashlc',
    'DEAD_CODE_STRIPPING'    => 'NO',
  }

  s.dependency "ExpoModulesCore"
  # Needed by the copied Swift SDK sources, not by VerusCryptoModule itself.
  s.dependency "gRPC-Swift", "~> 1.8"
  s.dependency "SQLite.swift", "~> 0.12"
end
