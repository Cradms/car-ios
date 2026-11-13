import Foundation
import Security

/// 长安控车用的 RSA-OAEP(SHA256) 加密
enum RSACrypto {

    /// 把服务端返回的公钥（PEM / 裸 base64 / DER）转成 SecKey
    static func publicKey(from raw: String) -> SecKey? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉 PEM 头尾和换行
        s = s.replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
             .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
             .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
             .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
             .replacingOccurrences(of: "\n", with: "")
             .replacingOccurrences(of: "\r", with: "")
             .replacingOccurrences(of: " ", with: "")
        guard let der = Data(base64Encoded: s, options: .ignoreUnknownCharacters) else {
            return nil
        }

        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 2048
        ]
        var err: Unmanaged<CFError>?
        if let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &err) {
            return key
        }
        // 可能是 PKCS#1 格式，包一层 SubjectPublicKeyInfo 再试
        if let spki = wrapPKCS1ToSPKI(der) {
            return SecKeyCreateWithData(spki as CFData, attrs as CFDictionary, &err)
        }
        return nil
    }

    /// RSA/ECB/OAEPWithSHA-256AndMGF1Padding
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

    // PKCS#1 RSAPublicKey -> SubjectPublicKeyInfo
    private static func wrapPKCS1ToSPKI(_ pkcs1: Data) -> Data? {
        let algoId: [UInt8] = [
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00
        ]
        let bitString = [UInt8](arrayLiteral: 0x00) + [UInt8](pkcs1)   // 前导 0（无未用位）
        var inner = algoId + derTag(0x03, bitString)
        return Data(derTag(0x30, inner))
    }

    private static func derTag(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        var out = [tag]
        let n = body.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else if n < 0x100 {
            out.append(contentsOf: [0x81, UInt8(n)])
        } else {
            out.append(contentsOf: [0x82, UInt8((n >> 8) & 0xff), UInt8(n & 0xff)])
        }
        out.append(contentsOf: body)
        return out
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
