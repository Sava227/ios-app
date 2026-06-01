import Foundation
import SwiftUI

private struct SharedState: Codable {
    var users: [User] = []
    var contactPairs: [ContactPair] = []
    var invitations: [SharedInvitation] = []
    var conversations: [SharedConversation] = []
    var nextInvitationID = 1
    var nextConversationID = 1
    var nextMessageID = 1

    mutating func addContactPair(userID: Int, contactID: Int) {
        let pair = ContactPair(userID: userID, contactID: contactID)
        if !contactPairs.contains(pair) {
            contactPairs.append(pair)
        }
    }
}

private struct ContactPair: Codable, Hashable {
    var userID: Int
    var contactID: Int
}

private struct SharedInvitation: Codable, Identifiable, Hashable {
    var id: Int
    var senderID: Int
    var recipientID: Int
    var createdAt: Date
}

private struct SharedConversation: Codable, Identifiable, Hashable {
    var id: Int
    var title: String?
    var isGroup: Bool
    var memberIDs: [Int]
    var messages: [SharedMessage]
    var createdAt: Date
}

private struct SharedMessage: Codable, Identifiable, Hashable {
    var id: Int
    var conversationID: Int
    var senderID: Int
    var senderName: String
    var body: String
    var attachments: [SharedAttachment]
    var reactions: [MessageReaction]
    var createdAt: Date
}

private struct SharedAttachment: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var kind: MessageAttachmentKind
    var duration: TimeInterval?
    var data: Data?
    var fileURL: URL?

    init(_ attachment: MessageAttachment) {
        id = attachment.id
        title = attachment.title
        kind = attachment.kind
        duration = attachment.duration
        data = attachment.data
        fileURL = attachment.fileURL
    }

    var messageAttachment: MessageAttachment {
        MessageAttachment(
            id: id,
            title: title,
            kind: kind,
            duration: duration,
            data: data,
            fileURL: fileURL
        )
    }
}

private struct NativeSyncRequest: Encodable {
    var user: User
}

private struct NativeOpenDirectRequest: Encodable {
    var user: User
    var contactID: Int
}

private struct NativeSendMessageRequest: Encodable {
    var user: User
    var body: String
}

private struct NativeSyncResponse: Decodable {
    var contacts: [User]
    var conversations: [NativeConversation]
    var conversationID: Int?
}

private struct NativeConversation: Decodable {
    var id: Int
    var title: String
    var isGroup: Bool
    var members: [User]
    var messages: [NativeMessage]
    var peerAvatarURL: URL?
    var createdAt: Date
}

private struct NativeMessage: Decodable {
    var id: Int
    var conversationID: Int
    var senderID: Int
    var senderName: String
    var body: String
    var createdAt: Date
}

@MainActor
final class KnotLinkStore: ObservableObject {
    @Published var currentUser: User?
    @Published var conversations: [Conversation] = []
    @Published var contacts: [User] = []
    @Published var incomingInvitations: [ContactInvitation] = []
    @Published var outgoingInvitations: [ContactInvitation] = []
    @Published var selectedSection: AppSection = .chats
    @Published var selectedConversationID: Int?
    @Published var authModeIsSignup = false
    @Published var notice: String?
    @Published var isLoading = false

    private static let savedUserKey = "knotlink.savedUser"
    private static let sharedStateKey = "knotlink.sharedLocalState.v1"
    private static let testUserID = 900_001
    private var nextMessageID = 1000
    private let bridge = WebSessionBridge()
    private let nativeServerBaseURLs = [
        URL(string: "http://localhost:5001")!,
        URL(string: "http://127.0.0.1:5001")!,
        URL(string: "http://10.35.110.87:5001")!,
    ]
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let googleOAuthService = GoogleOAuthService()
    private let mailRuOAuthService = MailRuOAuthService()

    init() {
        currentUser = loadSavedUser()
        if let currentUser {
            upsertSharedUser(currentUser)
            ensureTestChat(for: currentUser)
            refreshAccountData()
            Task {
                await refreshFromServer(showErrors: false)
            }
        } else {
            clearAccountData()
        }
    }

    var isAuthenticated: Bool { currentUser != nil }

    var selectedConversation: Conversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.id == selectedConversationID }
    }

    func authenticate(with provider: AuthProvider) async {
        isLoading = true
        defer { isLoading = false }

        do {
            switch provider {
            case .google:
                let profile = try await googleOAuthService.authenticate()
                currentUser = user(from: profile)
            case .mailRu:
                let profile = try await mailRuOAuthService.authenticate()
                currentUser = user(from: profile)
            }
            if let currentUser {
                upsertSharedUser(currentUser)
                ensureTestChat(for: currentUser)
            }
            saveCurrentUser()
            refreshAccountData()
            Task {
                await refreshFromServer(showErrors: false)
            }
            notice = copy.t("loginSuccessful")
            selectedSection = .chats
        } catch {
            let fallbackMessage = provider == .mailRu ? copy.t("mailRuSignInFailed") : copy.t("googleSignInFailed")
            notice = (error as? LocalizedError)?.errorDescription ?? fallbackMessage
        }
    }

    func loginWithEmail(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }

        let cleanEmail = normalizedEmail(email)
        guard isValidEmail(cleanEmail) else {
            notice = copy.t("enterValidEmail")
            return
        }
        guard password.count >= 8 else {
            notice = copy.t("passwordMin")
            return
        }

        let state = loadSharedState()
        currentUser = state.users.first { $0.email?.caseInsensitiveCompare(cleanEmail) == .orderedSame }
            ?? manualUser(email: cleanEmail, displayName: usernameBase(from: cleanEmail))
        if let currentUser {
            upsertSharedUser(currentUser)
            ensureTestChat(for: currentUser)
        }
        saveCurrentUser()
        refreshAccountData()
        Task {
            await refreshFromServer(showErrors: false)
        }
        notice = copy.t("loginSuccessful")
        selectedSection = .chats
    }

    func registerWithEmail(
        displayName: String,
        username: String,
        email: String,
        phoneNumber: String,
        password: String,
        confirmPassword: String
    ) async {
        isLoading = true
        defer { isLoading = false }

        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "").lowercased()
        let cleanEmail = normalizedEmail(email)
        let cleanPhone = normalizedPhone(phoneNumber)

        guard cleanName.count >= 2 else {
            notice = copy.t("displayNameMin")
            return
        }
        guard cleanUsername.count >= 3, cleanUsername.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil else {
            notice = copy.t("usernameInvalid")
            return
        }
        guard isValidEmail(cleanEmail) else {
            notice = copy.t("enterValidEmail")
            return
        }
        guard isValidPhone(cleanPhone) else {
            notice = copy.t("enterValidPhone")
            return
        }
        guard password.count >= 8 else {
            notice = copy.t("passwordMin")
            return
        }
        guard password == confirmPassword else {
            notice = copy.t("passwordsNoMatch")
            return
        }

        let state = loadSharedState()
        guard !state.users.contains(where: { $0.username.caseInsensitiveCompare(cleanUsername) == .orderedSame }) else {
            notice = copy.t("usernameInvalid")
            return
        }
        guard !state.users.contains(where: { $0.email?.caseInsensitiveCompare(cleanEmail) == .orderedSame }) else {
            notice = copy.t("enterValidEmail")
            return
        }
        guard !state.users.contains(where: { $0.phoneNumber?.filter(\.isNumber) == cleanPhone.filter(\.isNumber) }) else {
            notice = copy.t("enterValidPhone")
            return
        }

        currentUser = manualUser(email: cleanEmail, phoneNumber: cleanPhone, username: cleanUsername, displayName: cleanName)
        if let currentUser {
            upsertSharedUser(currentUser)
            ensureTestChat(for: currentUser)
        }
        saveCurrentUser()
        refreshAccountData()
        Task {
            await refreshFromServer(showErrors: false)
        }
        notice = copy.t("accountCreatedEmailVerification")
        selectedSection = .chats
    }

    func logout() {
        currentUser = nil
        clearSavedUser()
        selectedConversationID = nil
        clearAccountData()
        selectedSection = .chats
    }

    func sendMessage(_ text: String, attachments: [MessageAttachment] = [], in conversationID: Int) {
        guard let user = currentUser else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else {
            notice = copy.t("messageCannotBeEmpty")
            return
        }
        guard trimmed.count <= 2_000 else {
            notice = copy.t("messageTooLong")
            return
        }
        var state = loadSharedState()
        if let index = state.conversations.firstIndex(where: { $0.id == conversationID }) {
            state.conversations[index].messages.append(
                SharedMessage(
                    id: state.nextMessageID,
                    conversationID: conversationID,
                    senderID: user.id,
                    senderName: user.displayName,
                    body: trimmed,
                    attachments: attachments.map(SharedAttachment.init),
                    reactions: [],
                    createdAt: Date()
                )
            )
            state.nextMessageID += 1
            saveSharedState(state)
            refreshAccountData(selecting: conversationID)
            return
        }

        if attachments.isEmpty {
            Task {
                await sendServerMessage(trimmed, in: conversationID)
            }
            return
        }

        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let message = Message(id: nextMessageID, conversationID: conversationID, senderID: user.id, senderName: user.displayName, body: trimmed, attachments: attachments, createdAt: Date())
        nextMessageID += 1
        conversations[index].messages.append(message)
        conversations.sort { $0.lastActivity > $1.lastActivity }
    }

    func setReaction(_ emoji: String?, to messageID: Int, in conversationID: Int) {
        guard let user = currentUser else { return }
        var state = loadSharedState()
        if let conversationIndex = state.conversations.firstIndex(where: { $0.id == conversationID }),
           let messageIndex = state.conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) {
            state.conversations[conversationIndex].messages[messageIndex].reactions.removeAll { $0.userID == user.id }
            if let emoji, !emoji.isEmpty {
                state.conversations[conversationIndex].messages[messageIndex].reactions.append(
                    MessageReaction(emoji: emoji, userID: user.id, userName: user.displayName)
                )
            }
            saveSharedState(state)
            refreshAccountData(selecting: conversationID)
            return
        }

        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        var message = conversations[conversationIndex].messages[messageIndex]
        message.reactions.removeAll { $0.userID == user.id }
        if let emoji, !emoji.isEmpty {
            message.reactions.append(MessageReaction(emoji: emoji, userID: user.id, userName: user.displayName))
        }
        conversations[conversationIndex].messages[messageIndex] = message
    }

    func inviteContact(lookup: String) {
        guard let currentUser else { return }
        let normalized = lookup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            notice = copy.t("enterContactLookup")
            return
        }

        var state = loadSharedState()
        let cleanUsername = normalized.replacingOccurrences(of: "@", with: "")
        let cleanPhone = normalized.filter(\.isNumber)
        guard let person = state.users.first(where: { user in
            user.id != currentUser.id &&
                (user.username.caseInsensitiveCompare(cleanUsername) == .orderedSame ||
                 user.email?.caseInsensitiveCompare(normalized.lowercased()) == .orderedSame ||
                 (!cleanPhone.isEmpty && user.phoneNumber?.filter(\.isNumber) == cleanPhone))
        }) else {
            notice = copy.t("noUserFound")
            return
        }

        if state.contactPairs.contains(where: { $0.userID == currentUser.id && $0.contactID == person.id }) {
            notice = copy.t("invitationAccepted")
            return
        }
        if state.invitations.contains(where: { invitation in
            (invitation.senderID == currentUser.id && invitation.recipientID == person.id) ||
                (invitation.senderID == person.id && invitation.recipientID == currentUser.id)
        }) {
            notice = copy.f("invitationSent", person.displayName)
            return
        }

        state.invitations.append(
            SharedInvitation(
                id: state.nextInvitationID,
                senderID: currentUser.id,
                recipientID: person.id,
                createdAt: Date()
            )
        )
        state.nextInvitationID += 1
        saveSharedState(state)
        refreshAccountData()
        notice = copy.f("invitationSent", person.displayName)
    }

    func acceptInvitation(_ invitation: ContactInvitation) {
        guard let currentUser else { return }
        var state = loadSharedState()
        guard state.invitations.contains(where: { $0.id == invitation.id && $0.recipientID == currentUser.id }) else { return }
        state.invitations.removeAll { $0.id == invitation.id }
        state.addContactPair(userID: currentUser.id, contactID: invitation.person.id)
        state.addContactPair(userID: invitation.person.id, contactID: currentUser.id)
        saveSharedState(state)
        refreshAccountData()
        notice = copy.t("invitationAccepted")
    }

    func declineInvitation(_ invitation: ContactInvitation) {
        var state = loadSharedState()
        state.invitations.removeAll { $0.id == invitation.id }
        saveSharedState(state)
        refreshAccountData()
        notice = copy.t("invitationDeclined")
    }

    func openConversation(with contact: User) {
        Task {
            await openServerConversation(with: contact)
        }
    }

    @discardableResult
    func createGroup(title: String, memberIDs: Set<Int>) -> Bool {
        guard let currentUser else { return false }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.count >= 2 else {
            notice = copy.t("enterGroupName")
            return false
        }

        let selectedContacts = contacts
            .filter { memberIDs.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        guard !selectedContacts.isEmpty else {
            notice = copy.t("selectAtLeastOneGroupMember")
            return false
        }

        var state = loadSharedState()
        let conversationID = state.nextConversationID
        state.nextConversationID += 1
        state.conversations.append(
            SharedConversation(
                id: conversationID,
                title: cleanTitle,
                isGroup: true,
                memberIDs: ([currentUser] + selectedContacts).map(\.id),
                messages: [],
                createdAt: Date()
            )
        )
        saveSharedState(state)
        refreshAccountData(selecting: conversationID)
        notice = copy.t("groupCreated")
        return true
    }

    func availableGroupInviteContacts(for conversationID: Int) -> [User] {
        guard let conversation = conversations.first(where: { $0.id == conversationID }),
              conversation.isGroup else {
            return []
        }
        let memberIDs = Set(conversation.members.map(\.id))
        return contacts
            .filter { !memberIDs.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @discardableResult
    func inviteContacts(_ contactsToInvite: [User], toGroup conversationID: Int) -> Bool {
        var state = loadSharedState()
        guard let index = state.conversations.firstIndex(where: { $0.id == conversationID }),
              state.conversations[index].isGroup else {
            return false
        }

        let memberIDs = Set(state.conversations[index].memberIDs)
        let newContacts = contactsToInvite.filter { !memberIDs.contains($0.id) }
        guard !newContacts.isEmpty else {
            notice = copy.t("allContactsInGroup")
            return false
        }

        state.conversations[index].memberIDs.append(contentsOf: newContacts.map(\.id))
        saveSharedState(state)
        refreshAccountData(selecting: conversationID)

        notice = newContacts.count == 1
            ? copy.f("addedToGroup", newContacts[0].displayName)
            : copy.f("addedPeopleToGroup", newContacts.count)
        return true
    }

    func clearHistory(conversationID: Int) {
        var state = loadSharedState()
        if let index = state.conversations.firstIndex(where: { $0.id == conversationID }) {
            state.conversations[index].messages.removeAll()
            saveSharedState(state)
            refreshAccountData(selecting: conversationID)
        } else if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].messages.removeAll()
        }
        notice = copy.t("chatHistoryDeleted")
    }

    func deleteChat(conversationID: Int) {
        var state = loadSharedState()
        state.conversations.removeAll { $0.id == conversationID }
        saveSharedState(state)
        conversations.removeAll { $0.id == conversationID }
        selectedConversationID = nil
        notice = copy.t("chatDeleted")
    }

    func updateProfile(displayName: String, username: String, firstName: String, lastName: String) {
        guard var user = currentUser else { return }
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "").lowercased()

        guard cleanName.count >= 2 else {
            notice = copy.t("displayNameMin")
            return
        }
        guard cleanUsername.count >= 3, cleanUsername.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil else {
            notice = copy.t("usernameInvalid")
            return
        }

        user.displayName = cleanName
        user.username = cleanUsername
        user.firstName = firstName.nilIfBlank
        user.lastName = lastName.nilIfBlank
        currentUser = user
        upsertSharedUser(user)
        saveCurrentUser()
        refreshAccountData()
        notice = copy.t("profileUpdated")
    }

    func updateAvatar(data: Data) {
        guard var user = currentUser else { return }
        do {
            let directory = try avatarDirectory()
            let fileURL = directory.appendingPathComponent("current-user-avatar.jpg")
            try data.write(to: fileURL, options: [.atomic])
            user.avatarURL = fileURL
            currentUser = user
            upsertSharedUser(user)
            refreshCurrentUserReferences(user)
            saveCurrentUser()
            refreshAccountData()
            notice = copy.t("profilePhotoUpdated")
        } catch {
            notice = copy.t("profilePhotoUpdateFailed")
        }
    }

    private func refreshCurrentUserReferences(_ user: User) {
        conversations = conversations.map { conversation in
            var updated = conversation
            updated.members = conversation.members.map { member in
                member.id == user.id ? user : member
            }
            return updated
        }
    }

    func saveSettingsSummary(_ message: String) {
        notice = message
    }

    func openServerSession(path: String) -> URL? {
        bridge.url(for: path)
    }

    func syncLoop() async {
        while !Task.isCancelled {
            if isAuthenticated {
                await refreshFromServer(showErrors: false)
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        }
    }

    func refreshServerData() {
        Task {
            await refreshFromServer(showErrors: false)
        }
    }

    private func refreshFromServer(showErrors: Bool) async {
        guard let user = currentUser else { return }
        do {
            let response: NativeSyncResponse = try await postNativeJSON(
                path: "api/native/sync",
                body: NativeSyncRequest(user: user)
            )
            applyNativeSyncResponse(response)
        } catch {
            if showErrors {
                notice = "Server sync failed."
            }
        }
    }

    private func openServerConversation(with contact: User) async {
        guard let user = currentUser else { return }
        do {
            let response: NativeSyncResponse = try await postNativeJSON(
                path: "api/native/conversations/direct",
                body: NativeOpenDirectRequest(user: user, contactID: contact.id)
            )
            applyNativeSyncResponse(response, selecting: response.conversationID)
            selectedSection = .chats
        } catch {
            notice = "Could not open server conversation."
        }
    }

    private func sendServerMessage(_ text: String, in conversationID: Int) async {
        guard let user = currentUser else { return }
        do {
            let response: NativeSyncResponse = try await postNativeJSON(
                path: "api/native/conversations/\(conversationID)/messages",
                body: NativeSendMessageRequest(user: user, body: text)
            )
            applyNativeSyncResponse(response, selecting: conversationID)
        } catch {
            notice = "Message could not be sent to the server."
        }
    }

    private func postNativeJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        let bodyData = try jsonEncoder.encode(body)
        var lastError: Error?

        for baseURL in nativeServerBaseURLs {
            do {
                let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
                let url = baseURL.appending(path: cleanPath)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    throw URLError(.badServerResponse)
                }
                return try jsonDecoder.decode(ResponseBody.self, from: data)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? URLError(.badURL)
    }

    private func applyNativeSyncResponse(_ response: NativeSyncResponse, selecting conversationID: Int? = nil) {
        contacts = response.contacts
            .filter { $0.id != currentUser?.id }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        incomingInvitations = []
        outgoingInvitations = []
        conversations = response.conversations.map { nativeConversation in
            Conversation(
                id: nativeConversation.id,
                title: nativeConversation.title,
                isGroup: nativeConversation.isGroup,
                members: nativeConversation.members,
                messages: nativeConversation.messages.map {
                    Message(
                        id: $0.id,
                        conversationID: $0.conversationID,
                        senderID: $0.senderID,
                        senderName: $0.senderName,
                        body: $0.body,
                        createdAt: $0.createdAt
                    )
                },
                peerAvatarURL: nativeConversation.peerAvatarURL,
                createdAt: nativeConversation.createdAt
            )
        }
        if let conversationID {
            selectedConversationID = conversationID
        } else if let selectedConversationID, !conversations.contains(where: { $0.id == selectedConversationID }) {
            self.selectedConversationID = nil
        }
    }

    private func clearAccountData() {
        conversations = []
        contacts = []
        incomingInvitations = []
        outgoingInvitations = []
    }

    private func refreshAccountData(selecting conversationID: Int? = nil) {
        guard let currentUser else {
            clearAccountData()
            return
        }

        let state = loadSharedState()
        let usersByID = Dictionary(uniqueKeysWithValues: state.users.map { ($0.id, $0) })

        contacts = state.contactPairs
            .filter { $0.userID == currentUser.id }
            .compactMap { usersByID[$0.contactID] }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        incomingInvitations = state.invitations
            .filter { $0.recipientID == currentUser.id }
            .compactMap { invitation in
                usersByID[invitation.senderID].map {
                    ContactInvitation(id: invitation.id, person: $0, direction: .incoming, createdAt: invitation.createdAt)
                }
            }
            .sorted { $0.createdAt > $1.createdAt }

        outgoingInvitations = state.invitations
            .filter { $0.senderID == currentUser.id }
            .compactMap { invitation in
                usersByID[invitation.recipientID].map {
                    ContactInvitation(id: invitation.id, person: $0, direction: .outgoing, createdAt: invitation.createdAt)
                }
            }
            .sorted { $0.createdAt > $1.createdAt }

        conversations = state.conversations
            .filter { $0.memberIDs.contains(currentUser.id) }
            .compactMap { sharedConversation in
                let members = sharedConversation.memberIDs.compactMap { usersByID[$0] }
                guard members.contains(where: { $0.id == currentUser.id }) else { return nil }
                let otherMember = members.first { $0.id != currentUser.id }
                let title = sharedConversation.isGroup
                    ? (sharedConversation.title ?? "Group")
                    : (otherMember?.displayName ?? "Chat")
                return Conversation(
                    id: sharedConversation.id,
                    title: title,
                    isGroup: sharedConversation.isGroup,
                    members: members,
                    messages: sharedConversation.messages.map {
                        Message(
                            id: $0.id,
                            conversationID: $0.conversationID,
                            senderID: $0.senderID,
                            senderName: $0.senderName,
                            body: $0.body,
                            attachments: $0.attachments.map(\.messageAttachment),
                            reactions: $0.reactions,
                            createdAt: $0.createdAt
                        )
                    },
                    peerAvatarURL: otherMember?.avatarURL,
                    createdAt: sharedConversation.createdAt
                )
            }
            .sorted { $0.lastActivity > $1.lastActivity }

        if let conversationID {
            selectedConversationID = conversationID
            selectedSection = .chats
        } else if let selectedConversationID, !conversations.contains(where: { $0.id == selectedConversationID }) {
            self.selectedConversationID = nil
        }
    }

    private func upsertSharedUser(_ user: User) {
        var state = loadSharedState()
        if let index = state.users.firstIndex(where: { $0.id == user.id }) {
            state.users[index] = user
        } else {
            state.users.append(user)
        }
        saveSharedState(state)
    }

    private func loadSharedState() -> SharedState {
        guard let data = UserDefaults.standard.data(forKey: Self.sharedStateKey),
              let state = try? JSONDecoder().decode(SharedState.self, from: data) else {
            return SharedState()
        }
        return state
    }

    private func saveSharedState(_ state: SharedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.sharedStateKey)
    }

    private func ensureTestChat(for user: User) {
        guard user.id != Self.testUserID else { return }

        var state = loadSharedState()
        let testUser = User(
            id: Self.testUserID,
            username: "knotlink_test",
            email: "test@knotlink.local",
            phoneNumber: nil,
            firstName: "KnotLink",
            lastName: "Test",
            displayName: "KnotLink Test",
            avatarURL: nil,
            createdAt: Date().addingTimeInterval(-86400)
        )

        if let index = state.users.firstIndex(where: { $0.id == testUser.id }) {
            state.users[index] = testUser
        } else {
            state.users.append(testUser)
        }
        state.addContactPair(userID: user.id, contactID: testUser.id)
        state.addContactPair(userID: testUser.id, contactID: user.id)

        let hasTestConversation = state.conversations.contains { conversation in
            !conversation.isGroup &&
                conversation.memberIDs.contains(user.id) &&
                conversation.memberIDs.contains(testUser.id)
        }
        guard !hasTestConversation else {
            saveSharedState(state)
            return
        }

        let conversationID = max(state.nextConversationID, 900_001)
        let firstMessageID = state.nextMessageID
        let createdAt = Date().addingTimeInterval(-180)
        state.conversations.append(
            SharedConversation(
                id: conversationID,
                title: nil,
                isGroup: false,
                memberIDs: [user.id, testUser.id],
                messages: [
                    SharedMessage(
                        id: firstMessageID,
                        conversationID: conversationID,
                        senderID: testUser.id,
                        senderName: testUser.displayName,
                        body: "This is a test chat on iOS.",
                        attachments: [],
                        reactions: [],
                        createdAt: createdAt
                    ),
                    SharedMessage(
                        id: firstMessageID + 1,
                        conversationID: conversationID,
                        senderID: testUser.id,
                        senderName: testUser.displayName,
                        body: "Use this thread to check messages, reactions, voice notes, and the lower panel.",
                        attachments: [],
                        reactions: [],
                        createdAt: createdAt.addingTimeInterval(60)
                    )
                ],
                createdAt: createdAt
            )
        )
        state.nextConversationID = conversationID + 1
        state.nextMessageID = firstMessageID + 2
        saveSharedState(state)
    }

    private func user(from profile: GoogleOAuthProfile) -> User {
        let displayName = profile.name.nilIfBlank ?? profile.email ?? "Google User"
        let username = usernameBase(from: profile.email ?? displayName)

        return User(
            id: stableUserID(from: profile.subject),
            username: username,
            email: profile.email,
            phoneNumber: nil,
            firstName: profile.givenName,
            lastName: profile.familyName,
            displayName: displayName,
            avatarURL: profile.pictureURL,
            createdAt: Date()
        )
    }

    private func user(from profile: MailRuOAuthProfile) -> User {
        let displayName = profile.name.nilIfBlank ?? profile.email ?? "Mail.ru User"
        let username = usernameBase(from: profile.email ?? displayName)

        return User(
            id: stableUserID(from: "mailru-\(profile.subject)"),
            username: username,
            email: profile.email,
            phoneNumber: nil,
            firstName: profile.firstName,
            lastName: profile.lastName,
            displayName: displayName,
            avatarURL: profile.pictureURL,
            createdAt: Date()
        )
    }

    private func usernameBase(from value: String) -> String {
        var normalized = value
            .split(separator: "@")
            .first
            .map(String.init) ?? value
        normalized = normalized
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber || character == "_" ? character : "_"
            }
            .reduce(into: "") { partialResult, character in
                if character != "_" || !partialResult.hasSuffix("_") {
                    partialResult.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        if normalized.count < 3 {
            normalized = "\(normalized)_user"
        }
        return normalized.nilIfBlank ?? "knotlink_user"
    }

    private func manualUser(email: String, phoneNumber: String? = nil, username: String? = nil, displayName: String) -> User {
        let cleanUsername = username ?? usernameBase(from: email)
        return User(
            id: stableUserID(from: "email-\(email)"),
            username: cleanUsername,
            email: email,
            phoneNumber: phoneNumber,
            firstName: displayName.split(separator: " ").first.map(String.init),
            lastName: nil,
            displayName: displayName,
            avatarURL: nil,
            createdAt: Date()
        )
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    private func normalizedPhone(_ phoneNumber: String) -> String {
        phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidPhone(_ phoneNumber: String) -> Bool {
        let digitCount = phoneNumber.filter(\.isNumber).count
        let allowedCharacters = CharacterSet(charactersIn: "+0123456789 -()")
        return (7...15).contains(digitCount) &&
            phoneNumber.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }

    private var copy: AppCopy {
        AppCopy.current
    }

    private func stableUserID(from subject: String) -> Int {
        let value = subject.unicodeScalars.reduce(17) { partialResult, scalar in
            partialResult &* 31 &+ Int(scalar.value)
        }
        return max(1, abs(value % 900_000) + 10_000)
    }

    private func nextConversationID() -> Int {
        (conversations.map(\.id).max() ?? 0) + 1
    }

    private func loadSavedUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: Self.savedUserKey) else { return nil }
        if let payload = try? JSONDecoder().decode(EncryptedPayload.self, from: data),
           let decrypted = EndToEndEncryptionService.decryptData(payload, conversationID: 0, purpose: .localProfile) {
            return try? JSONDecoder().decode(User.self, from: decrypted)
        }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    private func saveCurrentUser() {
        guard let currentUser, let data = try? JSONEncoder().encode(currentUser) else { return }
        guard let encrypted = EndToEndEncryptionService.encryptData(data, conversationID: 0, purpose: .localProfile),
              let sealedData = try? JSONEncoder().encode(encrypted) else {
            return
        }
        UserDefaults.standard.set(sealedData, forKey: Self.savedUserKey)
    }

    private func avatarDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("KnotLink/Avatars", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func clearSavedUser() {
        UserDefaults.standard.removeObject(forKey: Self.savedUserKey)
    }

    private func seedPreviewData() {
        let current = User(id: 1, username: "sava", email: "sava@example.com", phoneNumber: "+15551234567", firstName: "Sava", lastName: nil, displayName: "Sava", avatarURL: nil, createdAt: Date().addingTimeInterval(-86400 * 86))
        let maya = User(id: 2, username: "maya", email: "maya@example.com", phoneNumber: "+15550001111", firstName: "Maya", lastName: "Chen", displayName: "Maya Chen", avatarURL: nil, createdAt: Date().addingTimeInterval(-86400 * 120))
        let alex = User(id: 3, username: "alex_ops", email: "alex@example.com", phoneNumber: "+15550002222", firstName: "Alex", lastName: "Rivera", displayName: "Alex Rivera", avatarURL: nil, createdAt: Date().addingTimeInterval(-86400 * 44))
        let nina = User(id: 4, username: "nina", email: nil, phoneNumber: "+15550003333", firstName: "Nina", lastName: "Patel", displayName: "Nina Patel", avatarURL: nil, createdAt: Date().addingTimeInterval(-86400 * 7))

        contacts = [maya, alex, nina]
        incomingInvitations = [
            ContactInvitation(id: 1, person: nina, direction: .incoming, createdAt: Date().addingTimeInterval(-3600))
        ]
        outgoingInvitations = [
            ContactInvitation(id: 2, person: alex, direction: .outgoing, createdAt: Date().addingTimeInterval(-7200))
        ]
        conversations = [
            Conversation(
                id: 1,
                title: maya.displayName,
                isGroup: false,
                members: [current, maya],
                messages: [
                    Message(id: 1, conversationID: 1, senderID: maya.id, senderName: maya.displayName, body: "Can you send the project link again?", createdAt: Date().addingTimeInterval(-7200)),
                    Message(id: 2, conversationID: 1, senderID: current.id, senderName: current.displayName, body: "Sure: https://knotlink.local/chat", createdAt: Date().addingTimeInterval(-6900))
                ],
                peerAvatarURL: nil,
                createdAt: Date().addingTimeInterval(-10_000)
            ),
            Conversation(
                id: 2,
                title: "Launch Team",
                isGroup: true,
                members: [current, maya, alex],
                messages: [
                    Message(id: 3, conversationID: 2, senderID: alex.id, senderName: alex.displayName, body: "Staging account checks are ready.", createdAt: Date().addingTimeInterval(-18_000))
                ],
                peerAvatarURL: nil,
                createdAt: Date().addingTimeInterval(-40_000)
            )
        ]
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
