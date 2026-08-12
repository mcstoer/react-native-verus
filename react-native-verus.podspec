require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = package['name']
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = package['homepage']
  s.license      = package['license']
  s.authors      = package['author']

  s.platform     = :ios, "13.0"
  s.source = {
    :git => "https://github.com/VerusCoin/react-native-verus.git",
    :tag => "v#{s.version}"
  }

  s.prepare_command = <<-CMD
    echo "[react-native-verus] prepare_command starting..."
    set -e

    echo "PWD=$(pwd)"
    export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
    export HUSKY=0
    export CI=1
    # Corepack refuses to run a shimmed package manager when a parent
    # package.json pins a different one, which is the normal case inside an
    # app's node_modules. Downgrade that from an error to a warning:
    export COREPACK_ENABLE_STRICT=0

    # scripts/prepack.ts owns the decision of whether anything needs building,
    # and runs the build if so. CocoaPods runs this for our :git and :podspec
    # consumers; for a :path pod it runs nothing, and the npm prepack hook calls
    # the same script. The two checks below are the only ones repeated here,
    # because both mean "there is nothing to do" and reaching the script at all
    # costs a dependency install:
    if [ "$RNV_BUILD_IOS" = "0" ]; then
      echo "[react-native-verus] RNV_BUILD_IOS=0, skipping the iOS source build."
      exit 0
    fi

    # The build needs a full Xcode install; the Command Line Tools carry no
    # iphoneos SDK. Skip rather than fail, so a pod install that does not need
    # these still finishes:
    if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
      echo "[react-native-verus] No iphoneos SDK found, skipping the iOS source build."
      echo "[react-native-verus] Install Xcode and run 'npm run update-sources' to create them."
      exit 0
    fi

    # Our devDependencies are absent whenever we are installed as a dependency,
    # and packing strips lockfiles, so this can use neither `yarn
    # --frozen-lockfile` nor `npm ci`. `--legacy-peer-deps` stops npm from
    # failing over our react-native peer, which the app owns:
    if [ ! -x "./node_modules/.bin/sucrase" ]; then
      echo "Installing deps (ignoring lifecycle scripts to avoid Husky)..."
      npm install --ignore-scripts --legacy-peer-deps --no-package-lock --no-audit --no-fund
    fi

    echo "Transpiling TS -> JS (with imports->CJS) ..."
    rm -rf ./scripts-built
    ./node_modules/.bin/sucrase ./scripts \
      --transforms typescript,imports \
      --out-dir ./scripts-built

    if [ ! -f "./scripts-built/prepack.js" ]; then
      echo "ERROR: Expected ./scripts-built/prepack.js after transpile."
      exit 1
    fi

    echo "Running prepack.js ..."
    node ./scripts-built/prepack.js

    echo "[react-native-verus] prepare_command finished."
  CMD

  s.source_files =
    "ios/react-native-verus-Bridging-Header.h",
    "ios/VerusLightClient.m",
    "ios/VerusLightClient.swift",
    "ios/zcashlc.h",
    "ios/ZCashLightClientKit/**/*.swift"
  s.resource_bundles = {
    "zcash-mainnet" => "ios/ZCashLightClientKit/Resources/checkpoints/mainnet/*.json",
    "zcash-testnet" => "ios/ZCashLightClientKit/Resources/checkpoints/testnet/*.json"
  }

  s.vendored_frameworks = "ios/libzcashlc.xcframework"
  s.libraries = "z", "sqlite3", "c++"
  s.preserve_paths = "ios/libzcashlc.xcframework"

  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS'   => '$(inherited) $(PODS_CONFIGURATION_BUILD_DIR) $(PODS_XCFRAMEWORKS_BUILD_DIR)/libzcashlc',
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) $(PODS_CONFIGURATION_BUILD_DIR) $(PODS_XCFRAMEWORKS_BUILD_DIR)'
  }

  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS'    => '$(inherited) $(PODS_TARGET_SRCROOT)/ios $(PODS_XCFRAMEWORKS_BUILD_DIR)/libzcashlc/**',
    'LIBRARY_SEARCH_PATHS'   => '$(inherited) $(PODS_CONFIGURATION_BUILD_DIR) $(PODS_XCFRAMEWORKS_BUILD_DIR)/libzcashlc',
    'DEAD_CODE_STRIPPING'    => 'NO',
  }

  s.dependency "React-Core"
  s.dependency "MnemonicSwift", "~> 2.0"
  s.dependency "gRPC-Swift", "~> 1.8"
  s.dependency "SQLite.swift", "~> 0.12"
  s.dependency "React-Core"
end
