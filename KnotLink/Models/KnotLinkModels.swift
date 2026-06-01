import Foundation
import CryptoKit
import Security

struct User: Identifiable, Hashable, Codable {
    var id: Int
    var username: String
    var email: String?
    var phoneNumber: String?
    var firstName: String?
    var lastName: String?
    var displayName: String
    var avatarURL: URL?
    var createdAt: Date

    var initials: String {
        displayName.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
            .nilIfEmpty ?? String(displayName.prefix(1)).uppercased()
    }
}

struct Conversation: Identifiable, Hashable {
    var id: Int
    var title: String
    var isGroup: Bool
    var members: [User]
    var messages: [Message]
    var peerAvatarURL: URL?
    var createdAt: Date

    func preview(currentUserID: Int) -> String {
        guard let message = messages.last else { return "No messages yet." }
        let prefix = message.senderID == currentUserID ? "You: " : ""
        if !message.body.isEmpty {
            return prefix + message.body.replacingOccurrences(of: "\n", with: " ")
        }
        if let attachment = message.attachments.first {
            return prefix + attachment.title
        }
        return prefix
    }

    var lastActivity: Date {
        messages.last?.createdAt ?? createdAt
    }

    func sharedLinks(limit: Int = 8) -> [URL] {
        var urls: [URL] = []
        var seen = Set<URL>()
        for message in messages {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let range = NSRange(message.body.startIndex..., in: message.body)
            let matches = detector?.matches(in: message.body, range: range) ?? []
            for match in matches {
                if let url = match.url, !seen.contains(url) {
                    urls.append(url)
                    seen.insert(url)
                    if urls.count >= limit { return urls }
                }
            }
        }
        return urls
    }
}

struct Message: Identifiable, Hashable {
    var id: Int
    var conversationID: Int
    var senderID: Int
    var senderName: String
    private var encryptedBody: EncryptedPayload?
    var attachments: [MessageAttachment] = []
    var reactions: [MessageReaction] = []
    var createdAt: Date

    init(
        id: Int,
        conversationID: Int,
        senderID: Int,
        senderName: String,
        body: String,
        attachments: [MessageAttachment] = [],
        reactions: [MessageReaction] = [],
        createdAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.senderName = senderName
        encryptedBody = body.isEmpty
            ? nil
            : EndToEndEncryptionService.encryptString(body, conversationID: conversationID, purpose: .messageBody)
        self.attachments = attachments.map { $0.sealed(for: conversationID) }
        self.reactions = reactions
        self.createdAt = createdAt
    }

    var body: String {
        guard let encryptedBody else { return "" }
        return EndToEndEncryptionService.decryptString(encryptedBody, conversationID: conversationID, purpose: .messageBody)
            ?? "[Unable to decrypt]"
    }
}

struct MessageReaction: Identifiable, Hashable, Codable {
    var id = UUID()
    var emoji: String
    var userID: Int
    var userName: String
}

struct MessageAttachment: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var kind: MessageAttachmentKind
    var duration: TimeInterval?
    private var encryptedData: EncryptedPayload?
    private var localPlainData: Data?
    private var encryptionConversationID: Int?
    var fileURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        kind: MessageAttachmentKind,
        duration: TimeInterval? = nil,
        data: Data?,
        fileURL: URL?
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.duration = duration
        encryptedData = nil
        localPlainData = data
        encryptionConversationID = nil
        self.fileURL = fileURL
    }

    var data: Data? {
        if let encryptedData {
            guard let encryptionConversationID else { return nil }
            return EndToEndEncryptionService.decryptData(encryptedData, conversationID: encryptionConversationID, purpose: .attachmentData)
        }
        return localPlainData
    }

    func sealed(for conversationID: Int) -> MessageAttachment {
        guard let data else { return self }
        var copy = self
        copy.encryptedData = EndToEndEncryptionService.encryptData(data, conversationID: conversationID, purpose: .attachmentData)
        copy.localPlainData = nil
        copy.encryptionConversationID = conversationID
        return copy
    }

    func decryptedData(conversationID: Int) -> Data? {
        if let encryptedData {
            return EndToEndEncryptionService.decryptData(encryptedData, conversationID: conversationID, purpose: .attachmentData)
        }
        return localPlainData
    }

    var systemImage: String {
        switch kind {
        case .photo:
            "photo.fill"
        case .video:
            "play.rectangle.fill"
        case .file:
            "doc.fill"
        case .videoCircle:
            "video.circle.fill"
        case .voice:
            "mic.fill"
        }
    }
}

enum MessageAttachmentKind: Hashable, Codable {
    case photo
    case video
    case file
    case videoCircle
    case voice
}

struct EncryptedPayload: Hashable, Codable {
    var version = 1
    var algorithm = "AES-GCM-256"
    var keyID: String
    var nonce: Data
    var ciphertext: Data
    var tag: Data
}

enum EncryptionPurpose: String {
    case messageBody = "message-body"
    case attachmentData = "attachment-data"
    case localProfile = "local-profile"
}

enum EndToEndEncryptionService {
    private static let keychainService = "com.knotlink.app.e2ee"
    private static let masterKeyAccount = "local-master-key-v1"
    private static let salt = Data("KnotLink-E2EE-v1".utf8)

    static func encryptString(_ value: String, conversationID: Int, purpose: EncryptionPurpose) -> EncryptedPayload? {
        encryptData(Data(value.utf8), conversationID: conversationID, purpose: purpose)
    }

    static func decryptString(_ payload: EncryptedPayload, conversationID: Int, purpose: EncryptionPurpose) -> String? {
        guard let data = decryptData(payload, conversationID: conversationID, purpose: purpose) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func encryptData(_ data: Data, conversationID: Int, purpose: EncryptionPurpose) -> EncryptedPayload? {
        guard !data.isEmpty else { return nil }
        let key = conversationKey(conversationID: conversationID)
        let nonce = AES.GCM.Nonce()
        let aad = authenticatedContext(conversationID: conversationID, purpose: purpose)
        guard let sealedBox = try? AES.GCM.seal(data, using: key, nonce: nonce, authenticating: aad) else {
            return nil
        }
        return EncryptedPayload(
            keyID: keyID(conversationID: conversationID),
            nonce: Data(nonce),
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    static func decryptData(_ payload: EncryptedPayload, conversationID: Int, purpose: EncryptionPurpose) -> Data? {
        let key = conversationKey(conversationID: conversationID)
        let aad = authenticatedContext(conversationID: conversationID, purpose: purpose)
        guard let nonce = try? AES.GCM.Nonce(data: payload.nonce),
              let sealedBox = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: payload.ciphertext, tag: payload.tag) else {
            return nil
        }
        return try? AES.GCM.open(sealedBox, using: key, authenticating: aad)
    }

    private static func conversationKey(conversationID: Int) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: masterKeyData()),
            salt: salt,
            info: Data("conversation:\(conversationID)".utf8),
            outputByteCount: 32
        )
    }

    private static func authenticatedContext(conversationID: Int, purpose: EncryptionPurpose) -> Data {
        Data("knotlink:v1:\(purpose.rawValue):\(conversationID)".utf8)
    }

    private static func keyID(conversationID: Int) -> String {
        "local-\(conversationID)-v1"
    }

    private static func masterKeyData() -> Data {
        if let existing = keychainData(account: masterKeyAccount) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let generated = status == errSecSuccess ? Data(bytes) : Data(UUID().uuidString.utf8).sha256Data
        setKeychainData(generated, account: masterKeyAccount)
        return generated
    }

    private static func keychainData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    private static func setKeychainData(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

private extension Data {
    var sha256Data: Data {
        Data(SHA256.hash(data: self))
    }
}

struct ContactInvitation: Identifiable, Hashable {
    enum Direction {
        case incoming
        case outgoing
    }

    var id: Int
    var person: User
    var direction: Direction
    var createdAt: Date
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
