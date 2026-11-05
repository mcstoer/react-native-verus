/*
 * Typed wrapper over the VerusCrypto Expo module. Bytes cross the bridge as
 * lowercase hex; addresses and the 169-byte keys as bech32. Callers own all
 * conversion to and from raw bytes.
 *
 * Never log the arguments or results of these functions: they carry seeds,
 * spending keys, viewing keys and symmetric keys.
 */
import { requireNativeModule } from 'expo-modules-core'

export interface NativeChannelKeys {
  /** Sapling payment address, bech32 "zs1..." (43-byte payload). */
  address: string
  /** Extended full viewing key, bech32 "zxviews1..." (169-byte payload). */
  extfvk: string
  /** Incoming viewing key, hex (32 bytes). */
  ivk: string
  /**
   * Extended spending key, bech32 "secret-extended-key-main1..." (169-byte
   * payload). Only present when returnSecret was set.
   */
  spendingKey?: string
}

export interface NativeEncryptedPayload {
  /** Ephemeral public key, hex (32 bytes). */
  ephemeralPublicKey: string
  /** Ciphertext, hex. */
  encryptedData: string
  /** Symmetric key, hex (32 bytes). Only present when returnSsk was set. */
  symmetricKey?: string
}

export interface EncryptionAddressOptions {
  /** Raw 32 or 64 byte seed as hex. Mnemonics are not accepted. */
  seedHex?: string | null
  /** 169 byte Sapling extended spending key as hex. */
  extskHex?: string | null
  /** 20 byte identity hash as hex. */
  fromIdHex?: string | null
  /** 20 byte identity hash as hex. */
  toIdHex?: string | null
  /** HD account index; -1 (the default) means none. */
  hdIndex?: number
  /** Defaults to 0. */
  encryptionIndex?: number
  /** Also return the derived spending key. Defaults to false. */
  returnSecret?: boolean
}

interface VerusCryptoNativeModule {
  zGetEncryptionAddress(
    options: Required<EncryptionAddressOptions>
  ): Promise<NativeChannelKeys>
  encryptVerusData(
    address: string,
    dataHex: string,
    returnSsk: boolean
  ): Promise<NativeEncryptedPayload>
  decryptVerusData(
    ivkHex: string | null,
    epkHex: string | null,
    dataHex: string,
    sskHex: string | null
  ): Promise<string>
}

const VerusCrypto = requireNativeModule<VerusCryptoNativeModule>('VerusCrypto')

/**
 * Derives a Sapling encryption address and its keys, as the daemon's
 * z_getencryptionaddress does. Pass exactly one of seedHex and extskHex.
 */
export function zGetEncryptionAddress(
  options: EncryptionAddressOptions
): Promise<NativeChannelKeys> {
  return VerusCrypto.zGetEncryptionAddress({
    seedHex: options.seedHex ?? null,
    extskHex: options.extskHex ?? null,
    fromIdHex: options.fromIdHex ?? null,
    toIdHex: options.toIdHex ?? null,
    hdIndex: options.hdIndex ?? -1,
    encryptionIndex: options.encryptionIndex ?? 0,
    returnSecret: options.returnSecret ?? false
  })
}

/**
 * Encrypts dataHex to a "zs1..." address. With returnSsk, the result also
 * carries the symmetric key, which can decrypt without the ivk.
 */
export function encryptVerusData(
  address: string,
  dataHex: string,
  returnSsk: boolean = false
): Promise<NativeEncryptedPayload> {
  return VerusCrypto.encryptVerusData(address, dataHex, returnSsk)
}

/**
 * Decrypts with ivkHex plus epkHex, or with sskHex alone. When sskHex is
 * given it takes precedence. Resolves with the plaintext as hex.
 */
export function decryptVerusData(
  ivkHex: string | null,
  epkHex: string | null,
  dataHex: string,
  sskHex: string | null
): Promise<string> {
  return VerusCrypto.decryptVerusData(ivkHex, epkHex, dataHex, sskHex)
}
