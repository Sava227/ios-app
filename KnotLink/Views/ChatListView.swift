import SwiftUI
import UIKit

struct ChatListView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    @State private var searchText = ""
    @State private var filter: ChatFilter = .all
    @State private var showCreateGroup = false

    private enum ChatFilter: String, CaseIterable, Identifiable {
        case all
        case groups
        case bots
        var id: String { rawValue }

        var textKey: String {
            switch self {
            case .all: "allChats"
            case .groups: "groups"
            case .bots: "bots"
            }
        }
    }

    private var filteredConversations: [Conversation] {
        store.conversations.filter { conversation in
            let matchesFilter = filter == .all || (filter == .groups && conversation.isGroup)
            let searchBlob = "\(conversation.title) \(conversation.preview(currentUserID: store.currentUser?.id ?? 0))"
            let matchesSearch = searchText.isEmpty || searchBlob.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Header(title: "KnotLink", subtitle: copy.f("conversationsCount", store.conversations.count))

                    Button {
                        showCreateGroup = true
                    } label: {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .glassCard(tint: .white.opacity(0.16), in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copy.t("createGroup"))
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    TextField(copy.t("searchChats"), text: $searchText)
                        .textInputAutocapitalization(.never)
                }
                .padding(14)
                .glassCard(in: Capsule(), interactive: true)

                Picker(copy.t("filter"), selection: $filter) {
                    ForEach(ChatFilter.allCases) { item in
                        Text(copy.t(item.textKey)).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                LazyVStack(spacing: 12) {
                    if filter == .bots {
                        ContentUnavailableView(copy.t("botChatsWillAppear"), systemImage: "bolt.horizontal.circle")
                            .glassCard(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else if filteredConversations.isEmpty {
                        ContentUnavailableView(copy.t("noChatsFound"), systemImage: "bubble.left")
                            .glassCard(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        ForEach(filteredConversations) { conversation in
                            ConversationRow(conversation: conversation)
                        }
                    }
                }
            }
            .padding()
            .padding(.bottom, 88)
        }
        .navigationTitle(copy.t("chats"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupView()
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}

private struct CreateGroupView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    @State private var groupName = ""
    @State private var selectedMemberIDs: Set<Int> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(copy.t("groupName"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField(copy.t("groupNamePlaceholder"), text: $groupName)
                            .textInputAutocapitalization(.words)
                            .padding(14)
                            .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(16)
                    .glassCard(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)

                    HStack {
                        Text(copy.t("chooseMembers").uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(copy.f("selectedMembersCount", selectedMemberIDs.count))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    LazyVStack(spacing: 10) {
                        if store.contacts.isEmpty {
                            ContentUnavailableView(copy.t("noContactsYet"), systemImage: "person.crop.circle.badge.plus")
                                .glassCard(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        } else {
                            ForEach(store.contacts) { contact in
                                GroupMemberPickerRow(
                                    contact: contact,
                                    isSelected: selectedMemberIDs.contains(contact.id)
                                ) {
                                    toggle(contact)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(copy.t("createGroup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.t("cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.t("createGroup")) {
                        if store.createGroup(title: groupName, memberIDs: selectedMemberIDs) {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggle(_ contact: User) {
        withAnimation(.snappy(duration: 0.18)) {
            if selectedMemberIDs.contains(contact.id) {
                selectedMemberIDs.remove(contact.id)
            } else {
                selectedMemberIDs.insert(contact.id)
            }
        }
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}

private struct GroupMemberPickerRow: View {
    var contact: User
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                AvatarView(title: contact.displayName, id: contact.id, imageURL: contact.avatarURL, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(contact.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("@\(contact.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.knotBlue : Color(.tertiaryLabel))
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassCard(tint: isSelected ? Color.knotSky.opacity(0.18) : nil, in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
    }
}

private struct ConversationRow: View {
    @EnvironmentObject private var store: KnotLinkStore
    var conversation: Conversation

    var body: some View {
        Button {
            store.selectedConversationID = conversation.id
        } label: {
            HStack(spacing: 14) {
                AvatarView(title: conversation.title, id: conversation.id, imageURL: conversation.peerAvatarURL)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(conversation.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(conversation.lastActivity, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(conversation.preview(currentUserID: store.currentUser?.id ?? 0))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassCard(tint: store.selectedConversationID == conversation.id ? Color.knotSky.opacity(0.18) : nil, in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
    }
}

struct Header: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AvatarView: View {
    var title: String
    var id: Int
    var imageURL: URL? = nil
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [avatarColor.opacity(0.92), avatarColor.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let imageURL {
                if imageURL.isFileURL, let uiImage = UIImage(contentsOfFile: imageURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        Text(title.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined().nilIfEmpty ?? String(title.prefix(1)).uppercased())
            .font(initialsFont)
            .foregroundStyle(.white)
    }

    private var initialsFont: Font {
        if size <= 30 {
            return .caption.weight(.bold)
        }
        if size <= 40 {
            return .subheadline.weight(.bold)
        }
        if size >= 68 {
            return .title2.weight(.bold)
        }
        return .headline.weight(.bold)
    }

    private var avatarColor: Color {
        Color(hue: Double((id * 37) % 360) / 360.0, saturation: 0.58, brightness: 0.82)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
