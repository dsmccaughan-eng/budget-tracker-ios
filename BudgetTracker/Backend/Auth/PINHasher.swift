import CommonCrypto
import Foundation

enum PINHasherError: Error {
    case randomGenerationFailed
    case derivationFailed
}

enum PINHasher {
    static let iterations: UInt32 = 120_000
    static let derivedKeyLength = 32
    static let saltLength = 16

    static func generateSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltLength, &bytes)
        guard status == errSecSuccess else {
            throw PINHasherError.randomGenerationFailed
        }
        return Data(bytes)
    }

    static func hash(pin: String, salt: Data) throws -> Data {
        let pinBytes = Array(pin.utf8)
        var derived = Data(count: derivedKeyLength)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pinBytes,
                    pinBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                    derivedKeyLength
                )
            }
        }
        guard status == kCCSuccess else {
            throw PINHasherError.derivationFailed
        }
        return derived
    }

    static func verify(pin: String, salt: Data, expectedHash: Data) -> Bool {
        guard let computed = try? hash(pin: pin, salt: salt) else { return false }
        return constantTimeEqual(computed, expectedHash)
    }

    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return false }
        return lhs.withUnsafeBytes { left in
            rhs.withUnsafeBytes { right in
                guard left.count == right.count else { return false }
                var difference: UInt8 = 0
                for index in 0..<left.count {
                    difference |= left[index] ^ right[index]
                }
                return difference == 0
            }
        }
    }

    static func isValidPINFormat(_ pin: String) -> Bool {
        pin.allSatisfy(\.isNumber) && pin.count == AppLockPolicy.pinLength
    }
}
