import ExpoModulesCore

/*
 * Encryption-only bridge over the Verus Swift SDK (verus_zfunc). The JS
 * boundary is hex for bytes and bech32 for addresses and long keys, the same
 * as Android.
 *
 * Key material rule: never log inputs or outputs, and never put inputs in
 * exception messages. Decoded byte arrays are zeroed once the SDK call
 * returns. The strings that crossed the bridge cannot be zeroed.
 *
 * DerivationTool, Bech32 and the ChannelKeys / EncryptedPayload /
 * DecryptedData members are internal to the SDK, which works because
 * scripts/updateSources.ts copies the SDK sources into this pod's module.
 */

/// Options for zGetEncryptionAddress. Every byte value is hex. Exactly one of
/// seedHex and extskHex must be set.
struct EncryptionAddressOptions: Record {
  /// 32 or 64 byte seed. Raw bytes only, never a mnemonic.
  @Field var seedHex: String? = nil
  /// 169 byte Sapling extended spending key.
  @Field var extskHex: String? = nil
  /// 20 byte identity hash (i-address payload).
  @Field var fromIdHex: String? = nil
  /// 20 byte identity hash (i-address payload).
  @Field var toIdHex: String? = nil
  /// -1 means none, which verus_zfunc treats as 0 for seeds.
  @Field var hdIndex: Int = -1
  @Field var encryptionIndex: Int = 0
  @Field var returnSecret: Bool = false
}

private let saplingHrp = "zs"
private let extfvkHrp = "zxviews"
private let extskHrp = "secret-extended-key-main"
private let addressLength = 43
private let keyLength = 169
/// verus_zfunc's ChildIndex::hardened panics at 2^31, and a Rust panic
/// across the C FFI aborts the app, so reject these before calling in.
private let maxIndex = 0x7fff_ffff

private func verusError(_ code: String, _ description: String, _ cause: Error? = nil) -> Exception {
  return Exception(name: code, description: description, code: code).causedBy(cause)
}

/// Runs body and rethrows anything that is not already an Exception as one
/// with the given code, so JS sees a stable error code.
private func wrapErrors<T>(_ code: String, _ description: String, _ body: () throws -> T) throws -> T {
  do {
    return try body()
  } catch let error as Exception {
    throw error
  } catch {
    throw verusError(code, description, error)
  }
}

/*
 * Mutates in place rather than through a copy, which would trigger
 * copy-on-write and leave the original buffer untouched.
 */
private func zero(_ bytes: inout [UInt8]?) {
  bytes?.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
  bytes = nil
}

private func zero(_ bytes: inout [UInt8]) {
  bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
}

/// Hex decoder whose errors never echo the input.
private func bytes(fromHex hex: String, _ name: String) throws -> [UInt8] {
  let chars = Array(hex.utf8)
  guard chars.count % 2 == 0 else {
    throw verusError("ERR_VERUS_HEX", "\(name): hex must have an even length")
  }
  func nibble(_ c: UInt8) -> UInt8? {
    switch c {
    case 0x30...0x39: return c - 0x30
    case 0x61...0x66: return c - 0x61 + 10
    case 0x41...0x46: return c - 0x41 + 10
    default: return nil
    }
  }
  var out = [UInt8](repeating: 0, count: chars.count / 2)
  for i in 0..<out.count {
    guard let hi = nibble(chars[i * 2]), let lo = nibble(chars[i * 2 + 1]) else {
      zero(&out)
      throw verusError("ERR_VERUS_HEX", "\(name): invalid hex character")
    }
    out[i] = hi << 4 | lo
  }
  return out
}

private func hexString(_ bytes: [UInt8]) -> String {
  let digits = Array("0123456789abcdef".utf8)
  var out = [UInt8]()
  out.reserveCapacity(bytes.count * 2)
  for b in bytes {
    out.append(digits[Int(b >> 4)])
    out.append(digits[Int(b & 0x0f)])
  }
  return String(decoding: out, as: UTF8.self)
}

private func decodeSaplingAddress(_ address: String) throws -> [UInt8] {
  let decoded: (hrp: String, data: [UInt8])
  do {
    decoded = try Bech32.decode(address)
  } catch {
    throw verusError("ERR_VERUS_ADDRESS", "Invalid Sapling address", error)
  }
  guard decoded.hrp == saplingHrp else {
    throw verusError("ERR_VERUS_ADDRESS", "Invalid Sapling address prefix: \(decoded.hrp)")
  }
  guard decoded.data.count == addressLength else {
    throw verusError(
      "ERR_VERUS_ADDRESS",
      "Unexpected address length \(decoded.data.count), expected \(addressLength)")
  }
  return decoded.data
}

private func encodeKey(_ hrp: String, _ data: [UInt8]) throws -> String {
  guard data.count == keyLength else {
    throw verusError("ERR_VERUS_KEY_LENGTH", "Unexpected key length \(data.count), expected \(keyLength)")
  }
  return try Bech32.encode(hrp: hrp, data: data)
}

public class VerusCryptoModule: Module {
  public func definition() -> ModuleDefinition {
    Name("VerusCrypto")

    AsyncFunction("zGetEncryptionAddress") { (o: EncryptionAddressOptions) throws -> [String: Any] in
      try wrapErrors("ERR_VERUS_ENCRYPTION_ADDRESS", "Failed to get encryption address") {
        guard o.hdIndex >= -1, o.hdIndex <= maxIndex,
              o.encryptionIndex >= 0, o.encryptionIndex <= maxIndex else {
          throw verusError("ERR_VERUS_ENCRYPTION_ADDRESS", "hdIndex or encryptionIndex is out of range")
        }
        var seed: [UInt8]? = nil
        var extsk: [UInt8]? = nil
        defer {
          zero(&seed)
          zero(&extsk)
        }
        seed = try o.seedHex.map { try bytes(fromHex: $0, "seed") }
        extsk = try o.extskHex.map { try bytes(fromHex: $0, "extsk") }
        let fromId = try o.fromIdHex.map { try bytes(fromHex: $0, "fromId") }
        let toId = try o.toIdHex.map { try bytes(fromHex: $0, "toId") }

        // The network is irrelevant to Verus encryption keys.
        let keys = try DerivationTool(networkType: .mainnet).zGetEncryptionAddress(
          seed: seed,
          extsk: extsk,
          hdIndex: o.hdIndex,
          encryptionIndex: o.encryptionIndex,
          fromId: fromId,
          toId: toId,
          returnSecret: o.returnSecret)

        var result: [String: Any] = [
          "address": keys.address,
          "extfvk": try encodeKey(extfvkHrp, keys.fullViewingKey),
          "ivk": hexString(keys.incomingViewingKey),
        ]
        if let sk = keys.spendingKey {
          result["spendingKey"] = try encodeKey(extskHrp, sk)
        }
        return result
      }
    }

    AsyncFunction("encryptVerusData") { (address: String, dataHex: String, returnSsk: Bool) throws -> [String: Any] in
      try wrapErrors("ERR_VERUS_ENCRYPT", "Failed to encrypt data") {
        var data = try bytes(fromHex: dataHex, "data")
        defer { zero(&data) }
        let payload = try DerivationTool(networkType: .mainnet).encryptVerusData(
          address: try decodeSaplingAddress(address),
          dataToEncrypt: data,
          returnSsk: returnSsk)
        var result: [String: Any] = [
          "ephemeralPublicKey": hexString(payload.ephemeralPublicKey),
          "encryptedData": hexString(payload.encryptedData),
        ]
        if let ssk = payload.symmetricKey {
          result["symmetricKey"] = hexString(ssk)
        }
        return result
      }
    }

    AsyncFunction("decryptVerusData") { (ivkHex: String?, epkHex: String?, dataHex: String, sskHex: String?) throws -> String in
      try wrapErrors("ERR_VERUS_DECRYPT", "Failed to decrypt data") {
        var ivk: [UInt8]? = nil
        var ssk: [UInt8]? = nil
        defer {
          zero(&ivk)
          zero(&ssk)
        }
        ivk = try ivkHex.map { try bytes(fromHex: $0, "ivk") }
        ssk = try sskHex.map { try bytes(fromHex: $0, "ssk") }
        let epk = try epkHex.map { try bytes(fromHex: $0, "epk") }
        var out = try DerivationTool(networkType: .mainnet).decryptVerusData(
          incomingViewingKey: ivk,
          ephemeralPublicKey: epk,
          dataToDecrypt: try bytes(fromHex: dataHex, "data"),
          symmetricKey: ssk
        ).data
        defer { zero(&out) }
        return hexString(out)
      }
    }
  }
}
