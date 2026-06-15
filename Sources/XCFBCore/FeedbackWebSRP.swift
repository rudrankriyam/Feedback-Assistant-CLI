import BigInt
import CryptoKit
import Foundation
import Security

struct FeedbackWebSRPProof: Equatable, Sendable {
    let m1: String
    let m2: String
}

enum FeedbackWebSRP {
    static let generator = BigUInt(2)
    static let modulus = BigUInt(
        """
        AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC319294\
        3DB56050A37329CBB4A099ED8193E0757767A13DD52312AB4B03310D\
        CD7F48A9DA04FD50E8083969EDB767B0CF6095179A163AB3661A05FB\
        D5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF74\
        7359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A\
        436C6481F1D2B9078717461A5B9D32E688F87748544523B524B0D57D\
        5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6AF874E73\
        03CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB6\
        94B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F\
        9E4AFF73
        """.replacingOccurrences(of: "\n", with: ""),
        radix: 16
    )!

    static func randomSecret(byteCount: Int = 256) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw XCFBError.web("could not generate Apple authentication key material")
        }
        return Data(bytes)
    }

    static func publicValue(secret: Data) -> BigUInt {
        generator.power(BigUInt(secret), modulus: modulus)
    }

    static func derivePassword(
        password: String,
        protocolName: String,
        salt: Data,
        iterations: Int
    ) throws -> Data {
        let passwordDigest = sha256(Data(password.utf8))
        let preparedPassword: Data
        switch protocolName {
        case "s2k":
            preparedPassword = passwordDigest
        case "s2k_fo":
            preparedPassword = Data(passwordDigest.hexString.utf8)
        default:
            throw XCFBError.web("Apple returned unsupported SRP protocol \(protocolName)")
        }
        return try pbkdf2SHA256(
            password: preparedPassword,
            salt: salt,
            iterations: iterations,
            keyLength: 32
        )
    }

    static func calculateProof(
        username: String,
        secret: Data,
        publicValue: BigUInt,
        serverPublicValue: Data,
        derivedPassword: Data,
        salt: Data
    ) throws -> FeedbackWebSRPProof {
        let privateValue = BigUInt(secret)
        let serverValue = BigUInt(serverPublicValue)
        guard !serverValue.isZero, !(serverValue % modulus).isZero else {
            throw XCFBError.web("Apple returned an invalid SRP server value")
        }

        let inner = sha256(Data([0x3A]) + derivedPassword)
        let x = BigUInt(sha256(salt + inner))
        let multiplier = BigUInt(
            sha256(
                try padded(modulus)
                    + padded(generator)
            )
        )
        let scramblingParameter = BigUInt(
            sha256(
                try padded(publicValue)
                    + padded(serverValue)
            )
        )
        guard !scramblingParameter.isZero else {
            throw XCFBError.web("Apple returned an invalid SRP scrambling parameter")
        }

        let gx = generator.power(x, modulus: modulus)
        let kgx = (multiplier * gx) % modulus
        let base = (serverValue + modulus - kgx) % modulus
        let exponent = privateValue + (scramblingParameter * x)
        let sharedSecret = base.power(exponent, modulus: modulus)
        let sessionKey = sha256(serializedNumber(sharedSecret))

        let modulusHash = BigUInt(sha256(try padded(modulus)))
        let generatorHash = BigUInt(sha256(try padded(generator)))
        let parameterHash = modulusHash ^ generatorHash
        let m1Data = sha256(
            serializedNumber(parameterHash)
                + sha256(Data(username.utf8))
                + salt
                + serializedNumber(publicValue)
                + serverPublicValue
                + sessionKey
        )
        let m2Data = strippingLeadingZeroBytes(
            sha256(
                serializedNumber(publicValue)
                    + m1Data
                    + sessionKey
            )
        )

        return FeedbackWebSRPProof(
            m1: m1Data.base64EncodedString(),
            m2: m2Data.base64EncodedString()
        )
    }

    static func makeHashcash(
        bits: Int,
        challenge: String,
        date: Date = Date()
    ) throws -> String {
        guard bits >= 0, bits <= Insecure.SHA1.byteCount * 8 else {
            throw XCFBError.web("Apple returned an invalid hashcash difficulty")
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = formatter.string(from: date)

        var counter = 0
        while true {
            let candidate = "1:\(bits):\(timestamp):\(challenge)::\(counter)"
            let digest = Data(Insecure.SHA1.hash(data: Data(candidate.utf8)))
            if hasLeadingZeroBits(digest, count: bits) {
                return candidate
            }
            counter += 1
        }
    }

    static func hasLeadingZeroBits(_ data: Data, count: Int) -> Bool {
        guard count >= 0, count <= data.count * 8 else {
            return false
        }
        let bytes = [UInt8](data)
        let fullBytes = count / 8
        let remainingBits = count % 8
        for index in 0..<fullBytes where bytes[index] != 0 {
            return false
        }
        guard remainingBits > 0 else {
            return true
        }
        let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - remainingBits))
        return bytes[fullBytes] & mask == 0
    }

    private static func padded(_ value: BigUInt) throws -> Data {
        let width = serializedNumber(modulus).count
        let data = serializedNumber(value)
        guard data.count <= width else {
            throw XCFBError.web("Apple SRP value exceeds the group width")
        }
        return Data(repeating: 0, count: width - data.count) + data
    }

    private static func serializedNumber(_ value: BigUInt) -> Data {
        let data = value.serialize()
        return data.isEmpty ? Data([0]) : data
    }

    private static func strippingLeadingZeroBytes(_ data: Data) -> Data {
        let bytes = data.drop(while: { $0 == 0 })
        return bytes.isEmpty ? Data([0]) : Data(bytes)
    }

    private static func sha256(_ data: Data) -> Data {
        Data(CryptoKit.SHA256.hash(data: data))
    }

    private static func pbkdf2SHA256(
        password: Data,
        salt: Data,
        iterations: Int,
        keyLength: Int
    ) throws -> Data {
        guard iterations > 0, keyLength > 0 else {
            throw XCFBError.web("Apple returned invalid password derivation parameters")
        }

        let key = SymmetricKey(data: password)
        let digestLength = CryptoKit.SHA256.byteCount
        let blockCount = (keyLength + digestLength - 1) / digestLength
        var derived = Data()
        derived.reserveCapacity(blockCount * digestLength)

        for blockIndex in 1...blockCount {
            var index = UInt32(blockIndex).bigEndian
            let indexData = withUnsafeBytes(of: &index) { Data($0) }
            var u = Data(HMAC<CryptoKit.SHA256>.authenticationCode(
                for: salt + indexData,
                using: key
            ))
            var block = [UInt8](u)

            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<CryptoKit.SHA256>.authenticationCode(
                        for: u,
                        using: key
                    ))
                    let bytes = [UInt8](u)
                    for byteIndex in block.indices {
                        block[byteIndex] ^= bytes[byteIndex]
                    }
                }
            }
            derived.append(contentsOf: block)
        }

        return derived.prefix(keyLength)
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
