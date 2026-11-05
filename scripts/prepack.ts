// Run this script as `node -r sucrase/register ./scripts/prepack.ts`
//
// Builds the gitignored iOS inputs the podspec compiles against, which nothing
// else produces: CocoaPods skips the podspec's `prepare_command` for `:path`
// pods. The rebuild needs macOS with a full Xcode install, and is skipped when
// impossible or already up to date.
//
// RNV_BUILD_IOS=0 always skips; RNV_BUILD_IOS=1 rebuilds even if present.

import { execSync } from 'child_process'
import { createHash } from 'crypto'
import {
  existsSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync
} from 'fs'
import { join } from 'path'

const root = join(__dirname, '..')
const xcframework = join(root, 'ios/libzcashlc.xcframework')
const swiftSources = join(root, 'ios/ZCashLightClientKit')
const rustHeader = join(root, 'ios/zcashlc.h')
const stampFile = join(root, 'ios/.prepack-stamp')

// What the artifacts are built out of, so that changing it makes what is on
// disk stale. The pinned commits live in updateSources.ts, which also rewrites
// what it copies.
const inputFiles = ['scripts/updateSources.ts']

function isNonEmptyDir(path: string): boolean {
  return existsSync(path) && readdirSync(path).length > 0
}

// Every gitignored path the podspec compiles against, so a partial build does
// not pass for a finished one:
function hasArtifacts(): boolean {
  return (
    isNonEmptyDir(xcframework) &&
    isNonEmptyDir(swiftSources) &&
    existsSync(rustHeader) &&
    statSync(rustHeader).size > 0
  )
}

function inputHash(): string {
  const hash = createHash('sha256')
  for (const file of inputFiles) hash.update(readFileSync(join(root, file)))
  return hash.digest('hex')
}

function isStamped(hash: string): boolean {
  try {
    return readFileSync(stampFile, 'utf8') === hash
  } catch (error) {
    return false
  }
}

function hasIosSdk(): boolean {
  try {
    execSync('xcrun --sdk iphoneos --show-sdk-path', { stdio: 'ignore' })
    return true
  } catch (error) {
    return false
  }
}

function skip(...lines: string[]): void {
  for (const line of lines) console.log(`[react-native-verus] ${line}`)
  if (!hasArtifacts()) {
    console.log(
      '[react-native-verus] iOS builds need these; run `npm run update-sources` on a mac with Xcode to create them.'
    )
  }
}

function main(): void {
  const force = process.env.RNV_BUILD_IOS === '1'

  if (process.env.RNV_BUILD_IOS === '0') {
    return skip('RNV_BUILD_IOS=0, skipping the iOS source rebuild.')
  }
  if (process.platform !== 'darwin') {
    return skip(
      `Not running on macOS (${process.platform}), skipping the iOS source rebuild.`
    )
  }
  const hash = inputHash()
  if (!force && hasArtifacts() && isStamped(hash)) {
    return skip(
      'The iOS artifacts are up to date, skipping the rebuild.',
      'Set RNV_BUILD_IOS=1 to rebuild them anyway.'
    )
  }
  if (!hasIosSdk()) {
    return skip(
      'No iphoneos SDK found, skipping the iOS source rebuild.',
      'This needs a full Xcode install; the Command Line Tools are not enough.'
    )
  }

  // Drop the stamp first, so an interrupted build leaves the artifacts marked
  // unusable rather than passing for the ones the current scripts describe:
  rmSync(stampFile, { force: true })
  execSync('npm run update-sources', { cwd: root, stdio: 'inherit' })
  writeFileSync(stampFile, hash)
}

main()
