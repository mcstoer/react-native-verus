# react-native-verus (VerusSky fork)

A VerusSky-only fork of [`VerusCoin/react-native-verus`](https://github.com/VerusCoin/react-native-verus)
v0.6.10 (`971a75c`). The legacy `VerusLightClient` bridge module is replaced by an
[Expo module](https://docs.expo.dev/modules/overview/), `VerusCrypto`, that exposes only the three
Verus Sapling encryption functions from `verus_zfunc`. Verus's native SDKs and binaries stay
underneath; no crypto is implemented here.

Because it is an Expo module it runs natively on the React Native New Architecture (bridgeless),
with no dependency on the legacy-module interop layer.

The light-wallet API (sync, balances, sending, events) is gone. Use upstream if you need it.

## API

```ts
import {
  zGetEncryptionAddress,
  encryptVerusData,
  decryptVerusData
} from 'react-native-verus'

const keys = await zGetEncryptionAddress({ seedHex, fromIdHex, toIdHex })
// { address: 'zs1...', extfvk: 'zxviews1...', ivk: '<hex>', spendingKey?: 'secret-extended-key-main1...' }

const payload = await encryptVerusData(keys.address, dataHex, /* returnSsk */ true)
// { ephemeralPublicKey: '<hex>', encryptedData: '<hex>', symmetricKey?: '<hex>' }

const plaintextHex = await decryptVerusData(keys.ivk, payload.ephemeralPublicKey, payload.encryptedData, null)
```

| Function | Inputs | Notes |
| --- | --- | --- |
| `zGetEncryptionAddress` | `seedHex` (32 or 64 bytes) or `extskHex` (169 bytes); optional `fromIdHex`/`toIdHex` (20 bytes), `hdIndex` (default `-1` = none), `encryptionIndex` (default `0`), `returnSecret` | Seeds are raw bytes on both platforms, never mnemonics. `hdIndex` other than `-1` together with an extsk is an error. |
| `encryptVerusData` | `zs1...` address, data hex, `returnSsk` | |
| `decryptVerusData` | `ivkHex` + `epkHex`, or `sskHex`; ciphertext hex | An ssk takes precedence over the ivk. |

Errors reject with these codes: `ERR_VERUS_ENCRYPTION_ADDRESS`, `ERR_VERUS_ENCRYPT`,
`ERR_VERUS_DECRYPT`, `ERR_VERUS_HEX`, `ERR_VERUS_ADDRESS`, `ERR_VERUS_KEY_LENGTH`.

Callers should validate inputs before calling in, in particular reject any index of 2^31 or more:
`verus_zfunc` panics on it, and a Rust panic across the iOS C FFI aborts the app. The Swift module
also checks this.

## Key material

- **Never log** the arguments or results of these functions, in JS or native code. They carry
  seeds, spending keys, viewing keys and symmetric keys.
- Native code never puts inputs in error messages, and zeroes decoded key bytes once the SDK call
  returns. Strings that crossed the bridge cannot be zeroed.

## Android

The module depends on `com.github.VerusCoin:verus-android-sdk:2.1.2`, which is **not published** to
JitPack or Maven Central. The consuming app must:

1. Build `VerusCoin/verus-android-wallet-sdk` at `f725d03c` (`./gradlew publishToMavenLocal`) and
   vendor the resulting `com/github/VerusCoin/*` artifacts in a Maven-layout folder.
2. Vendor Verus Mobile's 16 KB-page backend `verus-android-backend:2.1.2-16k.1` (from
   `mcstoer/verus-mobile` `android/local-maven`) in the same folder, and force that version:
   ```groovy
   configurations.all {
     resolutionStrategy.eachDependency { d ->
       if (d.requested.group == 'com.github.VerusCoin' && d.requested.name == 'verus-android-backend') {
         d.useVersion '2.1.2-16k.1'
       }
     }
   }
   ```
3. Vendor `com.github.komputing.khash:sha256:1.1.1` and `sha256-jvm:1.1.1` too (JitPack-only
   upstream), and serve both groups from the vendored repo with `exclusiveContent`.
4. Enable core library desugaring in the app (`coreLibraryDesugaring
   'com.android.tools:desugar_jdk_libs:2.0.4'`); the Verus AARs require it.

## iOS

The pod compiles the Verus Swift SDK sources (`ios/ZCashLightClientKit/`), the Rust header
(`ios/zcashlc.h`) and links `ios/libzcashlc.xcframework`. These are gitignored build outputs, and
CocoaPods never runs `prepare_command` for the `:path` pods that autolinking creates, so they must
exist **before `pod install`**:

- **Prebuilt (recommended):** run the `iOS artifacts` workflow
  (`.github/workflows/ios-artifacts.yml`) on a macOS runner. Copy the URL and sha256 from its job
  summary into `ios-artifacts.lock` and commit. From then on, `pod install` fetches and verifies
  the archive itself (the podspec runs `scripts/fetch-ios-artifacts.sh` when the files are
  missing), so app builds need no Rust.
- **From source:** on a Mac with full Xcode and `rustup`, run `RNV_BUILD_IOS=1 npm run update-sources`.
  The fetch script keeps a locally built set unless `RNV_FORCE_FETCH=1`.

If the files are still missing, `pod install` fails with a message saying what to do. Set
`RNV_ALLOW_MISSING_IOS_ARTIFACTS=1` to skip that check (the app will then not compile).

The checkpoint resource bundles are no longer shipped. Only the unused light-wallet code reads
them.

## Pins

| Component | Pin |
| --- | --- |
| Upstream fork point | `VerusCoin/react-native-verus` `971a75cdd4d2efdf0097c9f0ad379d478a6ca68f` (v0.6.10) |
| Android SDK | `VerusCoin/verus-android-wallet-sdk` `f725d03c` (2.1.2) |
| Android backend | `verus-android-backend` `2.1.2-16k.1` (Verus Mobile's 16 KB rebuild) |
| `verus_zfunc` (Android backend lock) | `df9dc2d` |
| Swift SDK | `VerusCoin/verus-swift-wallet-sdk` `f6d871b292555f849abbd7b5626fcbdc41be9333` |
| iOS FFI | `VerusCoin/verus-lightclient-ffi` `8a1c24f4ff4fef1c73e87e79c44240210c5abe73` |

The iOS pins live in `scripts/updateSources.ts`.

## Installing

Install by a pinned commit, never a branch:

```json
"react-native-verus": "github:mcstoer/react-native-verus#<full commit sha>"
```

The package has no `prepare` or `postinstall` scripts, so a git install runs nothing.
