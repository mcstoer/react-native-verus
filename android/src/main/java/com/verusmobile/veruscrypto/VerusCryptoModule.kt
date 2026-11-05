package com.verusmobile.veruscrypto

import cash.z.ecc.android.sdk.model.Bech32
import cash.z.ecc.android.sdk.model.ChannelKeys
import cash.z.ecc.android.sdk.model.EncryptedPayload
import cash.z.ecc.android.sdk.tool.DerivationTool
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.functions.Coroutine
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record
import expo.modules.kotlin.types.OptimizedRecord
import kotlin.coroutines.cancellation.CancellationException

/**
 * Options for zGetEncryptionAddress. Every byte value is hex. Exactly one of
 * seedHex and extskHex must be set.
 */
@OptimizedRecord
class EncryptionAddressOptions : Record {
  /** 32 or 64 byte seed. Raw bytes only, never a mnemonic. */
  @Field var seedHex: String? = null

  /** 169 byte Sapling extended spending key. */
  @Field var extskHex: String? = null

  /** 20 byte identity hash (i-address payload). */
  @Field var fromIdHex: String? = null

  /** 20 byte identity hash (i-address payload). */
  @Field var toIdHex: String? = null

  /** -1 means none, which verus_zfunc treats as 0 for seeds. */
  @Field var hdIndex: Int = -1

  @Field var encryptionIndex: Int = 0

  @Field var returnSecret: Boolean = false
}

/*
 * Encryption-only bridge over the Verus Android SDK (verus_zfunc). The JS
 * boundary is hex for bytes and bech32 for addresses and long keys, the same
 * as the old VerusLightClient module.
 *
 * Key material rule: never log inputs or outputs, and never put inputs in
 * exception messages. Decoded byte arrays are zeroed once the SDK call
 * returns. The strings that crossed the bridge cannot be zeroed.
 */
class VerusCryptoModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("VerusCrypto")

    AsyncFunction("zGetEncryptionAddress") Coroutine { o: EncryptionAddressOptions ->
      var seed: ByteArray? = null
      var extsk: ByteArray? = null
      try {
        seed = o.seedHex?.let { Hex.decode(it, "seed") }
        extsk = o.extskHex?.let { Hex.decode(it, "extsk") }
        val fromId = o.fromIdHex?.let { Hex.decode(it, "fromId") }
        val toId = o.toIdHex?.let { Hex.decode(it, "toId") }
        DerivationTool.getInstance()
          .getVerusEncryptionAddress(
            seed = seed,
            spendingKey = extsk,
            fromId = fromId,
            toId = toId,
            hdIndex = o.hdIndex,
            encryptionIndex = o.encryptionIndex,
            returnSecret = o.returnSecret,
          )
          .toMap()
      } catch (e: CodedException) {
        throw e
      } catch (e: CancellationException) {
        // Let coroutine cancellation propagate untouched.
        throw e
      } catch (e: Exception) {
        throw CodedException(
          "ERR_VERUS_ENCRYPTION_ADDRESS",
          e.message ?: "Failed to get encryption address",
          e,
        )
      } finally {
        seed?.fill(0)
        extsk?.fill(0)
      }
    }

    AsyncFunction("encryptVerusData") Coroutine { address: String, dataHex: String, returnSsk: Boolean ->
      val data = Hex.decode(dataHex, "data")
      try {
        DerivationTool.getInstance()
          .encryptVerusData(decodeSaplingAddress(address), data, returnSsk)
          .toMap()
      } catch (e: CodedException) {
        throw e
      } catch (e: CancellationException) {
        // Let coroutine cancellation propagate untouched.
        throw e
      } catch (e: Exception) {
        throw CodedException("ERR_VERUS_ENCRYPT", e.message ?: "Failed to encrypt data", e)
      } finally {
        data.fill(0)
      }
    }

    AsyncFunction("decryptVerusData") Coroutine { ivkHex: String?, epkHex: String?, dataHex: String, sskHex: String? ->
      var ivk: ByteArray? = null
      var ssk: ByteArray? = null
      try {
        ivk = ivkHex?.let { Hex.decode(it, "ivk") }
        ssk = sskHex?.let { Hex.decode(it, "ssk") }
        val epk = epkHex?.let { Hex.decode(it, "epk") }
        val out = DerivationTool.getInstance()
          .decryptVerusData(ivk, epk, Hex.decode(dataHex, "data"), ssk)
          .copyDecryptedDataBytes()
        try {
          Hex.encode(out)
        } finally {
          out.fill(0)
        }
      } catch (e: CodedException) {
        throw e
      } catch (e: CancellationException) {
        // Let coroutine cancellation propagate untouched.
        throw e
      } catch (e: Exception) {
        throw CodedException("ERR_VERUS_DECRYPT", e.message ?: "Failed to decrypt data", e)
      } finally {
        ivk?.fill(0)
        ssk?.fill(0)
      }
    }
  }

  private fun ChannelKeys.toMap(): Map<String, Any> {
    val extfvk = copyExtendedFullViewingKeyBytes()
    val ivk = copyInternalViewingKeyBytes()
    val sk = copySpendingKeyBytes()
    try {
      return buildMap {
        put("address", copyAddress())
        put("extfvk", Bech32.encodeBytes(EXTFVK_HRP, requireKeyLength(extfvk), Bech32.Encoding.Bech32))
        put("ivk", Hex.encode(ivk))
        if (sk != null) {
          put("spendingKey", Bech32.encodeBytes(EXTSK_HRP, requireKeyLength(sk), Bech32.Encoding.Bech32))
        }
      }
    } finally {
      extfvk.fill(0)
      ivk.fill(0)
      sk?.fill(0)
    }
  }

  private fun EncryptedPayload.toMap(): Map<String, Any> {
    val ssk = copySymmetricKeyBytes()
    try {
      return buildMap {
        put("ephemeralPublicKey", Hex.encode(copyEphemeralPublicKeyBytes()))
        put("encryptedData", Hex.encode(copyEncryptedDataBytes()))
        if (ssk != null) put("symmetricKey", Hex.encode(ssk))
      }
    } finally {
      ssk?.fill(0)
    }
  }

  private fun requireKeyLength(bytes: ByteArray): ByteArray {
    if (bytes.size != KEY_LENGTH) {
      throw CodedException("ERR_VERUS_KEY_LENGTH", "Unexpected key length ${bytes.size}, expected $KEY_LENGTH", null)
    }
    return bytes
  }

  private fun decodeSaplingAddress(address: String): ByteArray {
    val (hrp, bytes, _) = try {
      Bech32.decodeBytes(address)
    } catch (e: Exception) {
      throw CodedException("ERR_VERUS_ADDRESS", "Invalid Sapling address", e)
    }
    if (hrp != SAPLING_HRP) {
      throw CodedException("ERR_VERUS_ADDRESS", "Invalid Sapling address prefix: $hrp", null)
    }
    if (bytes.size != ADDRESS_LENGTH) {
      throw CodedException("ERR_VERUS_ADDRESS", "Unexpected address length ${bytes.size}, expected $ADDRESS_LENGTH", null)
    }
    return bytes
  }

  /** Hex codec whose errors never echo the input. */
  private object Hex {
    private val DIGITS = "0123456789abcdef".toCharArray()

    fun decode(hex: String, name: String): ByteArray {
      if (hex.length % 2 != 0) {
        throw CodedException("ERR_VERUS_HEX", "$name: hex must have an even length", null)
      }
      val out = ByteArray(hex.length / 2)
      for (i in out.indices) {
        val hi = nibble(hex[i * 2])
        val lo = nibble(hex[i * 2 + 1])
        if (hi < 0 || lo < 0) {
          out.fill(0)
          throw CodedException("ERR_VERUS_HEX", "$name: invalid hex character", null)
        }
        out[i] = ((hi shl 4) or lo).toByte()
      }
      return out
    }

    /** ASCII-only, unlike Character.digit, which also accepts other Unicode digits. */
    private fun nibble(c: Char): Int = when (c) {
      in '0'..'9' -> c - '0'
      in 'a'..'f' -> c - 'a' + 10
      in 'A'..'F' -> c - 'A' + 10
      else -> -1
    }

    fun encode(bytes: ByteArray): String {
      val out = CharArray(bytes.size * 2)
      for (i in bytes.indices) {
        val v = bytes[i].toInt() and 0xff
        out[i * 2] = DIGITS[v ushr 4]
        out[i * 2 + 1] = DIGITS[v and 0x0f]
      }
      return String(out)
    }
  }

  private companion object {
    const val SAPLING_HRP = "zs"
    const val EXTFVK_HRP = "zxviews"
    const val EXTSK_HRP = "secret-extended-key-main"
    const val ADDRESS_LENGTH = 43
    const val KEY_LENGTH = 169
  }
}
