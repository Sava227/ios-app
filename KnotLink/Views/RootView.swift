import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: KnotLinkStore

    var body: some View {
        ZStack {
            KnotBackground()
            if store.isAuthenticated {
                MainShellView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                AuthView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.snappy, value: store.isAuthenticated)
        .task {
            await store.syncLoop()
        }
        .overlay(alignment: .top) {
            if let notice = store.notice {
                GeometryReader { proxy in
                    VStack {
                        DynamicIslandNotice(
                            text: notice,
                            maxWidth: max(126, min(proxy.size.width - 28, 350))
                        ) {
                            withAnimation(.snappy(duration: 0.24)) {
                                store.notice = nil
                            }
                        }
                        .id(notice)
                        .padding(.top, max(10, proxy.safeAreaInsets.top - 47))

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .ignoresSafeArea(edges: .top)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity
                ))
                .zIndex(20)
            }
        }
    }
}

private struct DynamicIslandNotice: View {
    var text: String
    var maxWidth: CGFloat
    var dismiss: () -> Void
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    @State private var isDropped = false
    @State private var isClosing = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(symbolColor)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 13)
        .padding(.trailing, 15)
        .padding(.vertical, 11)
        .opacity(isDropped ? 1 : 0)
        .frame(width: isDropped ? maxWidth : 126, height: isDropped ? 64 : 37, alignment: .leading)
        .clipped()
        .background(.black, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(isDropped ? 0.16 : 0), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isDropped ? 0.28 : 0.05), radius: isDropped ? 24 : 0, x: 0, y: isDropped ? 14 : 0)
        .contentShape(Capsule(style: .continuous))
        .offset(y: isDropped ? 56 : 0)
        .onTapGesture {
            close()
        }
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                isDropped = true
            }
        }
        .task(id: text) {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                close()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(text)")
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isDropped = false
        }

        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                dismiss()
            }
        }
    }

    private var title: String {
        switch noticeKind {
        case .success:
            "KnotLink"
        case .warning:
            copy.t("checkThis")
        case .destructive:
            copy.t("updated")
        case .info:
            "KnotLink"
        }
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }

    private var symbol: String {
        switch noticeKind {
        case .success:
            "checkmark"
        case .warning:
            "exclamationmark"
        case .destructive:
            "trash"
        case .info:
            "sparkles"
        }
    }

    private var symbolColor: Color {
        switch noticeKind {
        case .success:
            Color.green
        case .warning:
            Color.yellow
        case .destructive:
            Color.red
        case .info:
            Color.white
        }
    }

    private var noticeKind: NoticeKind {
        let lowercasedText = text.lowercased()
        if lowercasedText.contains("deleted") || lowercasedText.contains("declined") {
            return .destructive
        }
        if lowercasedText.contains("failed") ||
            lowercasedText.contains("enter") ||
            lowercasedText.contains("must") ||
            lowercasedText.contains("cannot") ||
            lowercasedText.contains("too long") ||
            lowercasedText.contains("do not match") ||
            lowercasedText.contains("no user") {
            return .warning
        }
        if lowercasedText.contains("successful") ||
            lowercasedText.contains("created") ||
            lowercasedText.contains("sent") ||
            lowercasedText.contains("accepted") ||
            lowercasedText.contains("updated") ||
            lowercasedText.contains("signed in") {
            return .success
        }
        return .info
    }

    private enum NoticeKind {
        case success
        case warning
        case destructive
        case info
    }
}

struct MainShellView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    SidebarView()
                } content: {
                    SectionContentView()
                } detail: {
                    ConversationDetailHost()
                }
            } else {
                NavigationStack {
                    SectionContentView()
                        .navigationDestination(item: $store.selectedConversationID) { _ in
                            ConversationDetailHost()
                        }
                }
                .safeAreaInset(edge: .bottom) {
                    if store.selectedConversationID == nil {
                        BottomGlassBar()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.24), value: store.selectedConversationID)
            }
        }
        .tint(Color.knotBlue)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id

    var body: some View {
        List {
            Section {
                ForEach(AppSection.allCases) { section in
                    Button {
                        store.selectedSection = section
                    } label: {
                        Label(copy.sectionTitle(section), systemImage: section.symbol)
                    }
                    .foregroundStyle(store.selectedSection == section ? Color.knotBlue : Color.primary)
                }
            }
        }
        .navigationTitle("KnotLink")
        .scrollContentBackground(.hidden)
        .background(.clear)
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}

private struct SectionContentView: View {
    @EnvironmentObject private var store: KnotLinkStore

    var body: some View {
        switch store.selectedSection {
        case .chats:
            ChatListView()
        case .contacts:
            ContactsView()
        case .settings:
            SettingsView()
        case .profile:
            ProfileView()
        }
    }
}

private struct ConversationDetailHost: View {
    @EnvironmentObject private var store: KnotLinkStore
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id

    var body: some View {
        if let conversation = store.selectedConversation {
            ConversationView(conversation: conversation)
        } else {
            ContentUnavailableView(copy.t("selectChat"), systemImage: "bubble.left.and.bubble.right", description: Text(copy.t("conversationOpensHere")))
                .background(.clear)
        }
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}

private struct BottomGlassBar: View {
    @EnvironmentObject private var store: KnotLinkStore
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    private let horizontalInset: CGFloat = 7
    private let selectedPillHeight: CGFloat = 66

    private var sections: [AppSection] {
        AppSection.allCases
    }

    private var selectedIndex: Int {
        sections.firstIndex(of: store.selectedSection) ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            let tabWidth = max(0, (proxy.size.width - horizontalInset * 2) / CGFloat(sections.count))
            let selectedOffset = horizontalInset + tabWidth * CGFloat(selectedIndex)

            ZStack(alignment: .topLeading) {
                SelectedTabBackground()
                    .frame(width: tabWidth, height: selectedPillHeight)
                    .offset(x: selectedOffset, y: horizontalInset)
                    .animation(.snappy(duration: 0.30, extraBounce: 0.10), value: selectedIndex)

                HStack(spacing: 0) {
                    ForEach(sections) { section in
                        TelegramGlassTab(
                            section: section,
                            title: copy.sectionTitle(section),
                            isSelected: store.selectedSection == section
                        ) {
                            withAnimation(.snappy(duration: 0.30, extraBounce: 0.10)) {
                                store.selectedSection = section
                            }
                        }
                    }
                }
                .padding(horizontalInset)
            }
        }
        .frame(maxWidth: 390)
        .frame(height: 82)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.10))
                .allowsHitTesting(false)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.44), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 14)
        .sensoryFeedback(.selection, trigger: store.selectedSection)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(.clear)
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}

private struct TelegramGlassTab: View {
    var section: AppSection
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: section.symbol)
                    .font(.system(size: isSelected ? 25 : 24, weight: isSelected ? .bold : .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(width: 32, height: 29)

                Text(title)
                    .font(.caption.weight(isSelected ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(maxWidth: .infinity, minHeight: 66)
            .contentShape(Capsule(style: .continuous))
            .animation(.snappy(duration: 0.22, extraBounce: 0.06), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct SelectedTabBackground: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.white.opacity(0.18))
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.52), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}
