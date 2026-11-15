import Foundation
import Security

/// 长安控车用的 RSA-OAEP(SHA256) 加密
enum RSACrypto {

    /// 把服务端返回的公钥转成 SecKey
    /// 长安下发的是 SPKI(X.509) base64；iOS 只吃 PKCS#1，需要拆 BIT STRING
    static func publicKey(from raw: String) -> SecKey? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
             .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
             .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
             .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
        s = s.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let der = Data(base64Encoded: s, options: .ignoreUnknownCharacters) else {
            return nil
        }

        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]

        // 1) 先直接试（万一已经是 PKCS#1）
        if let k = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, nil) {
            return k
        }
        // 2) SPKI → 提取 BIT STRING 里的 RSAPublicKey
        if let pkcs1 = extractPKCS1(der),
           let k = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, nil) {
            return k
        }
        return nil
    }

    /// RSA/ECB/OAEPWithSHA-256AndMGF1Padding（与 Python 端 rsa_enc.encrypt_oaep 一致）
    static func encryptOAEP(_ plaintext: String, publicKeyPEM: String) -> String? {
        guard let key = publicKey(from: publicKeyPEM),
              let data = plaintext.data(using: .utf8) else { return nil }
        var err: Unmanaged<CFError>?
        guard let cipher = SecKeyCreateEncryptedData(key, .rsaEncryptionOAEPSHA256,
                                                     data as CFData, &err) else {
            return nil
        }
        return (cipher as Data).base64EncodedString()
    }

    // MARK: - DER

    /// 读一个 TLV，返回 (tag, value, nextIndex)
    private static func readTLV(_ b: [UInt8], _ i: Int) -> (UInt8, [UInt8], Int)? {
        guard i + 2 <= b.count else { return nil }
        let tag = b[i]
        var idx = i + 1
        var len = Int(b[idx]); idx += 1
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n > 0, idx + n <= b.count else { return nil }
            len = 0
            for k in 0..<n { len = (len << 8) | Int(b[idx + k]) }
            idx += n
        }
        guard idx + len <= b.count else { return nil }
        return (tag, Array(b[idx..<(idx + len)]), idx + len)
    }

    /// SPKI: SEQUENCE { AlgorithmIdentifier SEQUENCE, BIT STRING }
    /// 返回 BIT STRING 内（去掉 unused-bits 字节）的 RSAPublicKey 内容
    private static func extractPKCS1(_ der: Data) -> Data? {
        let b = [UInt8](der)
        guard let (tag0, body0, _) = readTLV(b, 0), tag0 == 0x30 else { return nil }

        var i = 0
        // 第一个子项：AlgorithmIdentifier
        guard let (t1, _, next1) = readTLV(body0, i), t1 == 0x30 else { return nil }
        i = next1
        // 第二个子项：BIT STRING
        guard let (t2, bitStr, _) = readTLV(body0, i), t2 == 0x03 else { return nil }
        guard bitStr.count > 1 else { return nil }
        // 第一个字节是 unused bits 数，跳过
        let inner = Array(bitStr.dropFirst())

        // 内层应是 SEQUENCE { INTEGER n, INTEGER e }
        guard let (t3, seqBody, _) = readTLV(inner, 0), t3 == 0x30 else { return nil }
        // 重新拼一个完整的 SEQUENCE TLV 交给 SecKeyCreateWithData
        var out: [UInt8] = [0x30]
        let n = seqBody.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else if n < 0x100 {
            out.append(contentsOf: [0x81, UInt8(n)])
        } else {
            out.append(contentsOf: [0x82, UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
        }
        out.append(contentsOf: seqBody)
        return Data(out)
    }
}

/// 登录态存储（Keychain）
enum TokenStore {
    private static let service = "com.yg.carapp.tokens"

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func set(_ value: String, for key: String) {
        let q = query(key)
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = value.data(using: .utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func remove(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
