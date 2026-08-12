import { Disklet, justFiles, navigateDisklet } from 'disklet'

export const checkpointPath =
  'android/src/main/assets/co.electriccoin.zcash/checkpoint/vrsc'

const toPath = 'ios/ZCashLightClientKit/Resources/checkpoints/mainnet'

/**
 * Copies checkpoints over from the Android side to the iOS side.
 */
export async function copyCheckpoints(disklet: Disklet): Promise<void> {
  console.log('Copying checkpoints...')
  const fromDisklet = navigateDisklet(disklet, checkpointPath)
  const toDisklet = navigateDisklet(disklet, toPath)

  const files = justFiles(await fromDisklet.list())
  for (const file of files) {
    const text = await fromDisklet.getText(file)
    await toDisklet.setText(file, text)
  }
}
