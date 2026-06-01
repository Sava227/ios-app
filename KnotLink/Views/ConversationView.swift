import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import AVFoundation
import AVKit

struct ConversationView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    @AppStorage("knotlink.autoTranslate") private var autoTranslate = false
    @AppStorage("knotlink.translateToCode") private var translateToCode = AppLanguageOption.english.id
    var conversation: Conversation
    @State private var draft = ""
    @State private var showInfo = false
    @State private var showSearch = false
    @State private var showAttachmentTray = false
    @State private var showFileImporter = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingAttachments: [MessageAttachment] = []
    @State private var photoEditorQueue: [PhotoEditorDraft] = []
    @State private var activePhotoEditor: PhotoEditorDraft?
    @State private var searchText = ""
    @State private var showVideoCircleCapture = false
    @State private var plusLongPressTriggered = false
    @StateObject private var voiceRecorder = VoiceMessageRecorder()

    private var visibleMessages: [Message] {
        if searchText.isEmpty { return conversation.messages }
        return conversation.messages.filter { $0.body.localizedCaseInsensitiveContains(searchText) }
    }

    private var messageList: some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                messageRow(message: message, index: index)
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let headerHeight = conversationHeaderHeight(safeTop: proxy.safeAreaInsets.top)

            ZStack(alignment: .top) {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if showSearch {
                        searchBar
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            messageList
                            .padding(.horizontal, 14)
                            .padding(.top, showSearch ? 6 : 10)
                            .padding(.bottom, 12)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onAppear {
                            if let last = conversation.messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: conversation.messages.count) {
                            if let last = conversation.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
                .padding(.top, headerHeight)

                conversationHeader(safeTop: proxy.safeAreaInsets.top)
                    .frame(height: headerHeight)
                    .ignoresSafeArea(edges: .top)
                    .zIndex(2)
            }
        }
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showInfo) {
            ChatInfoView(conversation: conversation)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(item: $activePhotoEditor) { draft in
            PhotoAttachmentEditorView(
                draft: draft,
                copy: copy,
                onComplete: { attachment in
                    pendingAttachments.append(attachment)
                    store.notice = copy.f("attachmentsAdded", 1)
                    advancePhotoEditorQueue()
                },
                onCancel: {
                    advancePhotoEditorQueue()
                }
            )
        }
        .fullScreenCover(isPresented: $showVideoCircleCapture) {
            VideoCircleCaptureView(
                onComplete: { attachment in
                    pendingAttachments.append(attachment)
                    showVideoCircleCapture = false
                    store.notice = copy.f("attachmentsAdded", 1)
                },
                onCancel: {
                    showVideoCircleCapture = false
                }
            )
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            handlePhotoSelection(newItems)
        }
    }

    private func conversationHeaderHeight(safeTop: CGFloat) -> CGFloat {
        safeTop + 116
    }

    private func conversationHeader(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: safeTop + 28)

            HStack(alignment: .center, spacing: 12) {
                headerCircleButton(systemImage: "chevron.left", accessibilityLabel: copy.t("back")) {
                    store.selectedConversationID = nil
                    dismiss()
                }

                Spacer(minLength: 8)

                MessagesContactHeader(conversation: conversation, avatarSize: 50)
                    .frame(maxWidth: 190)

                Spacer(minLength: 8)

                threadMenu
                    .font(.system(size: 25, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .glassCard(tint: .white.opacity(0.14), in: Circle(), interactive: true)
                    .accessibilityLabel(conversation.isGroup ? copy.t("chatInfo") : copy.t("contactInfo"))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            .white.opacity(0.42),
                            .white.opacity(0.20),
                            .white.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.16)
        }
        .shadow(color: .black.opacity(0.04), radius: 18, y: 10)
    }

    private func headerCircleButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 25, weight: .semibold))
                .frame(width: 54, height: 54)
                .glassCard(tint: .white.opacity(0.14), in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(copy.t("search"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(copy.t("cancel")) {
                withAnimation(.snappy) {
                    searchText = ""
                    showSearch = false
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: Capsule(style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var threadMenu: some View {
        Menu {
            Button(copy.t("search"), systemImage: "magnifyingglass") {
                withAnimation(.snappy) { showSearch = true }
            }
            Button(conversation.isGroup ? copy.t("chatInfo") : copy.t("contactInfo"), systemImage: "person.crop.circle") {
                showInfo = true
            }
            Button(copy.t("links"), systemImage: "link") {
                showInfo = true
            }
            Button(autoTranslate ? copy.t("stopTranslation") : copy.t("translateChat"), systemImage: "translate") {
                toggleThreadTranslation()
            }
            Divider()
            Button(copy.t("clearHistory"), systemImage: "trash") {
                store.clearHistory(conversationID: conversation.id)
            }
            Button(copy.t("deleteChat"), systemImage: "trash.fill", role: .destructive) {
                store.deleteChat(conversationID: conversation.id)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }

    private func shouldShowSender(for message: Message, at index: Int) -> Bool {
        guard message.senderID != store.currentUser?.id else { return false }
        guard conversation.isGroup else { return false }
        return startsMessageGroup(at: index)
    }

    private func startsMessageGroup(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !belongsToSameGroup(visibleMessages[index], visibleMessages[index - 1])
    }

    private func endsMessageGroup(at index: Int) -> Bool {
        guard index < visibleMessages.count - 1 else { return true }
        return !belongsToSameGroup(visibleMessages[index], visibleMessages[index + 1])
    }

    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = visibleMessages[index - 1]
        let current = visibleMessages[index]
        return current.createdAt.timeIntervalSince(previous.createdAt) > 15 * 60
    }

    private func belongsToSameGroup(_ message: Message, _ otherMessage: Message) -> Bool {
        message.senderID == otherMessage.senderID &&
            abs(message.createdAt.timeIntervalSince(otherMessage.createdAt)) < 5 * 60
    }

    private func toggleThreadTranslation() {
        autoTranslate.toggle()
        let targetLanguage = AppLanguageOption.supported.first { $0.id == translateToCode } ?? .english
        store.notice = autoTranslate
            ? copy.f("translationEnabledForChat", targetLanguage.nativeName)
            : copy.t("translationDisabledForChat")
    }

    private func avatarTitle(for message: Message) -> String {
        conversation.members.first { $0.id == message.senderID }?.displayName ?? message.senderName
    }

    private func translatedBody(for message: Message) -> String? {
        guard autoTranslate else { return nil }
        guard message.senderID != store.currentUser?.id else { return nil }
        return LocalMessageTranslator.translate(message.body, to: translateToCode)
    }

    private var composer: some View {
        VStack(spacing: 9) {
            if showAttachmentTray {
                attachmentTray
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            if !pendingAttachments.isEmpty {
                pendingAttachmentStrip
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if voiceRecorder.isActive {
                VoiceRecordingPanel(
                    recorder: voiceRecorder,
                    onCancel: {
                        withAnimation(.snappy(duration: 0.22)) {
                            voiceRecorder.cancel()
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    if plusLongPressTriggered {
                        plusLongPressTriggered = false
                        return
                    }
                    withAnimation(.snappy(duration: 0.26, extraBounce: 0.08)) {
                        showAttachmentTray.toggle()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 25, weight: .semibold))
                        .rotationEffect(.degrees(showAttachmentTray ? 45 : 0))
                        .frame(width: 43, height: 43)
                        .foregroundStyle(showAttachmentTray ? .white : Color.knotBlue)
                        .background(showAttachmentTray ? Color.knotBlue.opacity(0.76) : Color.white.opacity(0.18), in: Circle())
                        .glassCard(tint: Color.knotSky.opacity(0.16), in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.42)
                        .onEnded { _ in
                            plusLongPressTriggered = true
                            openVideoCircleCapture()
                        }
                )
                .accessibilityLabel("Add attachment. Hold for video circle.")
                .accessibilityHint("Tap to open attachments. Hold to record a video circle.")

                HStack(alignment: .bottom, spacing: 8) {
                    TextField(copy.t("message"), text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textInputAutocapitalization(.sentences)
                        .padding(.leading, 12)
                        .padding(.vertical, 8)

                    Button {
                        handleComposerAction()
                    } label: {
                        Image(systemName: composerActionIcon)
                            .font(.system(size: composerShowsMicrophone ? 21 : 28, weight: .semibold))
                            .foregroundStyle(composerActionColor)
                            .frame(width: 34, height: 34)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .disabled(composerActionDisabled)
                    .padding(.trailing, 4)
                    .padding(.bottom, 3)
                    .accessibilityLabel(composerActionLabel)
                }
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(.separator).opacity(0.42), lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .animation(.snappy(duration: 0.24), value: showAttachmentTray)
        .animation(.snappy(duration: 0.24), value: pendingAttachments)
        .animation(.snappy(duration: 0.24), value: voiceRecorder.isActive)
        .animation(.snappy(duration: 0.18), value: composerActionIcon)
    }

    private var attachmentTray: some View {
        HStack(spacing: 10) {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            ) {
                AttachmentActionButton(
                    systemImage: "photo.on.rectangle.angled",
                    title: copy.t("photosAndVideos"),
                    subtitle: copy.t("photosAndVideosDetail")
                )
            }
            .buttonStyle(.plain)

            Button {
                showFileImporter = true
                withAnimation(.snappy(duration: 0.22)) {
                    showAttachmentTray = false
                }
            } label: {
                AttachmentActionButton(
                    systemImage: "doc.badge.plus",
                    title: copy.t("files"),
                    subtitle: copy.t("filesDetail")
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .glassCard(tint: .white.opacity(0.18), in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
    }

    private var pendingAttachmentStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(pendingAttachments) { attachment in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: attachment.systemImage)
                                .font(.caption.weight(.bold))
                            Text(attachment.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 190)
                        .background(.white.opacity(0.32), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copy.t("removeAttachment"))
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    private var composerShowsMicrophone: Bool {
        !canSend && !voiceRecorder.isActive
    }

    private var composerActionIcon: String {
        if voiceRecorder.isActive {
            return "stop.circle.fill"
        }
        return composerShowsMicrophone ? "mic.fill" : "arrow.up.circle.fill"
    }

    private var composerActionColor: Color {
        if voiceRecorder.isActive {
            return .red
        }
        if composerShowsMicrophone {
            return Color.knotBlue
        }
        return canSend ? .blue : Color(.tertiaryLabel)
    }

    private var composerActionDisabled: Bool {
        !composerShowsMicrophone && !voiceRecorder.isActive && !canSend
    }

    private var composerActionLabel: String {
        if voiceRecorder.isActive {
            return "Finish voice message"
        }
        return composerShowsMicrophone ? "Record voice message" : "Send message"
    }

    private func handleComposerAction() {
        if voiceRecorder.isActive {
            if let attachment = voiceRecorder.finish() {
                withAnimation(.snappy(duration: 0.22)) {
                    pendingAttachments.append(attachment)
                }
            }
            return
        }

        if composerShowsMicrophone {
            voiceRecorder.start()
            return
        }

        sendDraft()
    }

    private func openVideoCircleCapture() {
        guard VideoCircleCaptureView.canCaptureVideoCircle else {
            store.notice = UIImagePickerController.isSourceTypeAvailable(.camera)
                ? "Video recording is unavailable on this device."
                : "Camera is unavailable on this device."
            return
        }

        withAnimation(.snappy(duration: 0.22)) {
            showAttachmentTray = false
        }
        showVideoCircleCapture = true
    }

    private func sendDraft() {
        store.sendMessage(draft, attachments: pendingAttachments, in: conversation.id)
        draft = ""
        selectedPhotoItems = []
        withAnimation(.snappy(duration: 0.22)) {
            pendingAttachments = []
            showAttachmentTray = false
        }
    }

    private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        selectedPhotoItems = []
        withAnimation(.snappy(duration: 0.22)) {
            showAttachmentTray = false
        }

        Task { @MainActor in
            var attachments: [MessageAttachment] = []
            var photoDrafts: [PhotoEditorDraft] = []

            for (index, item) in items.enumerated() {
                let isVideo = item.supportedContentTypes.contains { type in
                    type.conforms(to: .movie) || type.conforms(to: .video)
                }
                let title = items.count == 1
                    ? copy.t(isVideo ? "videoAttachment" : "photoAttachment")
                    : "\(copy.t(isVideo ? "videoAttachment" : "photoAttachment")) \(index + 1)"
                if isVideo {
                    attachments.append(
                        MessageAttachment(
                            title: title,
                            kind: .video,
                            data: nil,
                            fileURL: nil
                        )
                    )
                    continue
                }

                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    continue
                }
                photoDrafts.append(PhotoEditorDraft(title: title, image: image))
            }

            if !attachments.isEmpty {
                pendingAttachments.append(contentsOf: attachments)
                store.notice = copy.f("attachmentsAdded", attachments.count)
            }

            photoEditorQueue.append(contentsOf: photoDrafts)
            presentNextPhotoEditorIfNeeded()
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            let attachments = urls.map { url in
                let didAccess = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                return MessageAttachment(
                    title: url.lastPathComponent.nilIfBlank ?? copy.t("fileAttachment"),
                    kind: .file,
                    data: data,
                    fileURL: nil
                )
            }
            pendingAttachments.append(contentsOf: attachments)
            store.notice = copy.f("attachmentsAdded", attachments.count)
        case .failure:
            store.notice = copy.t("fileImportFailed")
        }
    }

    private func thumbnailData(for item: PhotosPickerItem) async -> Data? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        guard let image = UIImage(data: data) else { return data }
        return image.preparingThumbnail(of: CGSize(width: 720, height: 720))?.jpegData(compressionQuality: 0.84)
            ?? image.jpegData(compressionQuality: 0.84)
    }

    private func presentNextPhotoEditorIfNeeded() {
        guard activePhotoEditor == nil, !photoEditorQueue.isEmpty else { return }
        activePhotoEditor = photoEditorQueue.removeFirst()
    }

    private func advancePhotoEditorQueue() {
        activePhotoEditor = nil
        guard !photoEditorQueue.isEmpty else { return }
        DispatchQueue.main.async {
            presentNextPhotoEditorIfNeeded()
        }
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }

    @ViewBuilder
    private func messageRow(message: Message, index: Int) -> some View {
        if shouldShowDateSeparator(at: index) {
            MessageDateSeparator(date: message.createdAt)
                .padding(.vertical, index == 0 ? 8 : 14)
        }

        MessageBubble(
            message: message,
            isMine: message.senderID == store.currentUser?.id,
            showSender: shouldShowSender(for: message, at: index),
            startsGroup: startsMessageGroup(at: index),
            endsGroup: endsMessageGroup(at: index),
            avatarTitle: avatarTitle(for: message),
            translatedBody: translatedBody(for: message),
            currentUserID: store.currentUser?.id,
            onReact: { emoji in
                store.setReaction(emoji, to: message.id, in: conversation.id)
            }
        )
        .id(message.id)
        .padding(.top, startsMessageGroup(at: index) ? 6 : 0)
    }
}

private struct PhotoEditorDraft: Identifiable {
    var id = UUID()
    var title: String
    var image: UIImage
}

private struct PhotoAttachmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var draft: PhotoEditorDraft
    var copy: AppCopy
    var onComplete: (MessageAttachment) -> Void
    var onCancel: () -> Void

    @State private var aspect: PhotoEditorAspect = .original
    @State private var tool: PhotoEditorTool = .crop
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var rotation: Angle = .zero
    @State private var imageOffset = CGSize.zero
    @State private var lastImageOffset = CGSize.zero
    @State private var caption = ""
    @State private var captionSize: CGFloat = 34
    @State private var captionColor: PhotoEditorTextColor = .white
    @State private var captionOffset = CGSize.zero
    @State private var lastCaptionOffset = CGSize.zero
    @State private var brightness = 0.0
    @State private var saturation = 1.0
    @State private var cropRectUnit = CGRect.zero
    @State private var cropResizeStartUnit: CGRect?
    @State private var activeStageSize = CGSize.zero
    @State private var activeCanvasSize = CGSize.zero

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar

                GeometryReader { proxy in
                    let stageSize = proxy.size
                    let cropFrame = cropRect(in: stageSize)

                    ZStack {
                        PhotoEditorBackdrop(
                            image: draft.image,
                            brightness: brightness,
                            saturation: saturation
                        )

                        PhotoEditorCanvas(
                            image: draft.image,
                            aspect: aspect,
                            zoom: zoom,
                            rotation: rotation,
                            imageOffset: imageOffset,
                            caption: caption,
                            captionSize: captionSize,
                            captionColor: captionColor.color,
                            captionOffset: captionOffset,
                            brightness: brightness,
                            saturation: saturation,
                            cornerRadius: 24,
                            showsCropGuides: false
                        )
                        .frame(width: cropFrame.width, height: cropFrame.height)
                        .position(x: cropFrame.midX, y: cropFrame.midY)
                        .shadow(color: .black.opacity(0.42), radius: 24, y: 10)
                        .contentShape(Rectangle())
                        .gesture(canvasDragGesture(in: cropFrame.size))
                        .simultaneousGesture(canvasMagnificationGesture(in: cropFrame.size))

                        if tool == .crop {
                            PhotoCropResizeOverlay(cornerRadius: 24) { handle, translation, ended in
                                handleCropResize(handle, translation: translation, in: stageSize, ended: ended)
                            }
                            .frame(width: cropFrame.width, height: cropFrame.height)
                            .position(x: cropFrame.midX, y: cropFrame.midY)
                        }
                    }
                    .frame(width: stageSize.width, height: stageSize.height)
                    .onAppear {
                        updateStageSize(stageSize)
                    }
                    .onChange(of: stageSize) { _, newSize in
                        updateStageSize(newSize)
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)

                editorControls
            }
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onCancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassCard(tint: .white.opacity(0.12), in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy.t("cancel"))

            Text(copy.t("editPhoto"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button {
                completeEdit()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassCard(tint: Color.knotSky.opacity(0.28), in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy.t("done"))
        }
        .padding(.horizontal, 16)
    }

    private var editorControls: some View {
        VStack(spacing: 12) {
            aspectPicker
            toolPicker

            Group {
                switch tool {
                case .crop:
                    cropControls
                case .text:
                    textControls
                case .tune:
                    tuneControls
                }
            }
            .frame(minHeight: 86)
        }
        .padding(12)
        .glassCard(tint: .white.opacity(0.16), in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: true)
        .padding(.horizontal, 12)
    }

    private var aspectPicker: some View {
        HStack(spacing: 8) {
            ForEach(PhotoEditorAspect.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        aspect = option
                        resetCropFrame(for: option, in: activeStageSize)
                    }
                } label: {
                    Text(option.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(aspect == option ? .black : .white.opacity(0.76))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(aspect == option ? .white.opacity(0.92) : .white.opacity(0.10), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var toolPicker: some View {
        HStack(spacing: 8) {
            ForEach(PhotoEditorTool.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        tool = option
                    }
                } label: {
                    Label(option.title(copy), systemImage: option.systemImage)
                        .font(.caption.weight(.bold))
                        .labelStyle(.iconOnly)
                        .foregroundStyle(tool == option ? .black : .white.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(tool == option ? .white.opacity(0.92) : .white.opacity(0.10), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title(copy))
            }
        }
    }

    private var cropControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.72))
                Slider(value: zoomBinding, in: 1...3)
                    .tint(.white)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 10) {
                glassToolButton(systemImage: "rotate.right") {
                    withAnimation(.snappy(duration: 0.22)) {
                        let nextRotation = rotation + .degrees(90)
                        rotation = nextRotation
                        imageOffset = clampedImageOffset(imageOffset, in: activeCanvasSize, zoom: zoom, rotation: nextRotation)
                        lastImageOffset = imageOffset
                    }
                }
                glassToolButton(systemImage: "arrow.counterclockwise") {
                    withAnimation(.snappy(duration: 0.22)) {
                        resetCrop()
                    }
                }
            }
        }
    }

    private var textControls: some View {
        VStack(spacing: 10) {
            TextField(copy.t("addText"), text: $caption)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(.white.opacity(0.12), in: Capsule(style: .continuous))

            HStack(spacing: 10) {
                Image(systemName: "textformat.size.smaller")
                    .foregroundStyle(.white.opacity(0.72))
                Slider(value: captionSizeBinding, in: 18...72)
                    .tint(.white)
                Image(systemName: "textformat.size.larger")
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 10) {
                ForEach(PhotoEditorTextColor.allCases) { option in
                    Button {
                        captionColor = option
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(.white.opacity(captionColor == option ? 0.95 : 0.30), lineWidth: captionColor == option ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                glassToolButton(systemImage: "trash") {
                    caption = ""
                }
            }
        }
    }

    private var tuneControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.white.opacity(0.72))
                Slider(value: $brightness, in: -0.35...0.35)
                    .tint(.white)
                Image(systemName: "sun.max")
                    .foregroundStyle(.white.opacity(0.72))
            }
            HStack(spacing: 10) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.white.opacity(0.72))
                Slider(value: $saturation, in: 0...1.8)
                    .tint(.white)
                Image(systemName: "circle.fill")
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private func glassToolButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 36)
                .background(.white.opacity(0.14), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var zoomBinding: Binding<Double> {
        Binding(
            get: { Double(zoom) },
            set: {
                let nextZoom = CGFloat($0)
                zoom = nextZoom
                imageOffset = clampedImageOffset(imageOffset, in: activeCanvasSize, zoom: nextZoom)
                lastImageOffset = imageOffset
                lastZoom = zoom
            }
        )
    }

    private var captionSizeBinding: Binding<Double> {
        Binding(
            get: { Double(captionSize) },
            set: { captionSize = CGFloat($0) }
        )
    }

    private func canvasMagnificationGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard tool == .crop else { return }
                let nextZoom = min(max(lastZoom * value, 1), 3)
                zoom = nextZoom
                imageOffset = clampedImageOffset(imageOffset, in: size, zoom: nextZoom)
            }
            .onEnded { _ in
                lastZoom = zoom
                lastImageOffset = imageOffset
            }
    }

    private func canvasDragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let normalized = CGSize(
                    width: value.translation.width / size.width,
                    height: value.translation.height / size.height
                )

                if tool == .text {
                    captionOffset = CGSize(
                        width: lastCaptionOffset.width + normalized.width,
                        height: lastCaptionOffset.height + normalized.height
                    )
                } else {
                    let nextOffset = CGSize(
                        width: lastImageOffset.width + normalized.width,
                        height: lastImageOffset.height + normalized.height
                    )
                    imageOffset = clampedImageOffset(nextOffset, in: size)
                }
            }
            .onEnded { _ in
                if tool == .text {
                    lastCaptionOffset = captionOffset
                } else {
                    lastImageOffset = imageOffset
                }
            }
    }

    private func resetCrop() {
        zoom = 1
        lastZoom = 1
        rotation = .zero
        imageOffset = .zero
        lastImageOffset = .zero
        resetCropFrame(for: aspect, in: activeStageSize)
        brightness = 0
        saturation = 1
    }

    private func completeEdit() {
        let image = renderEditedImage() ?? draft.image
        let data = image.jpegData(compressionQuality: 0.88)
        onComplete(
            MessageAttachment(
                title: draft.title,
                kind: .photo,
                data: data,
                fileURL: nil
            )
        )
        dismiss()
    }

    private func renderEditedImage() -> UIImage? {
        let cropSize = activeCanvasSize.width > 0 && activeCanvasSize.height > 0
            ? activeCanvasSize
            : aspect.outputSize(for: draft.image)
        let outputSize = PhotoEditorGeometry.outputSize(for: cropSize)
        let renderer = ImageRenderer(
            content: PhotoEditorCanvas(
                image: draft.image,
                aspect: aspect,
                zoom: zoom,
                rotation: rotation,
                imageOffset: imageOffset,
                caption: caption,
                captionSize: captionSize * (outputSize.width / 360),
                captionColor: captionColor.color,
                captionOffset: captionOffset,
                brightness: brightness,
                saturation: saturation,
                cornerRadius: 0
            )
            .frame(width: outputSize.width, height: outputSize.height)
        )
        renderer.scale = 1
        return renderer.uiImage
    }

    private func updateStageSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        activeStageSize = size
        if cropRectUnit.width <= 0 || cropRectUnit.height <= 0 {
            resetCropFrame(for: aspect, in: size)
        }
        updateCanvasSize(cropRect(in: size).size)
    }

    private func updateCanvasSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        activeCanvasSize = size
        imageOffset = clampedImageOffset(imageOffset, in: size)
        lastImageOffset = imageOffset
    }

    private func cropRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        if cropRectUnit.width > 0, cropRectUnit.height > 0 {
            return PhotoEditorGeometry.rect(from: cropRectUnit, in: size)
        }
        return PhotoEditorGeometry.centeredCropRect(
            for: aspect.ratio(for: draft.image),
            in: size
        )
    }

    private func resetCropFrame(for aspect: PhotoEditorAspect, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let nextRect = PhotoEditorGeometry.centeredCropRect(
            for: aspect.ratio(for: draft.image),
            in: size
        )
        cropRectUnit = PhotoEditorGeometry.unitRect(from: nextRect, in: size)
        cropResizeStartUnit = nil
        updateCanvasSize(nextRect.size)
    }

    private func handleCropResize(
        _ handle: CropResizeHandle,
        translation: CGSize,
        in stageSize: CGSize,
        ended: Bool
    ) {
        guard stageSize.width > 0, stageSize.height > 0 else { return }
        if cropResizeStartUnit == nil {
            cropResizeStartUnit = cropRectUnit
        }
        let startUnit = cropResizeStartUnit ?? cropRectUnit
        let startRect = PhotoEditorGeometry.rect(from: startUnit, in: stageSize)
        let nextRect = PhotoEditorGeometry.resizedCropRect(
            startRect,
            handle: handle,
            translation: translation,
            in: stageSize,
            lockedRatio: aspect.lockedRatio(for: draft.image)
        )
        cropRectUnit = PhotoEditorGeometry.unitRect(from: nextRect, in: stageSize)
        updateCanvasSize(nextRect.size)
        if ended {
            cropResizeStartUnit = nil
        }
    }

    private func clampedImageOffset(
        _ offset: CGSize,
        in size: CGSize,
        zoom explicitZoom: CGFloat? = nil,
        rotation explicitRotation: Angle? = nil
    ) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let resolvedZoom = explicitZoom ?? zoom
        let resolvedRotation = explicitRotation ?? rotation
        let displaySize = PhotoEditorGeometry.imageBoundingSize(
            for: draft.image.size,
            in: size,
            zoom: resolvedZoom,
            rotation: resolvedRotation
        )
        let maxX = max((displaySize.width - size.width) / 2 / size.width, 0)
        let maxY = max((displaySize.height - size.height) / 2 / size.height, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}

private struct PhotoEditorCanvas: View {
    var image: UIImage
    var aspect: PhotoEditorAspect
    var zoom: CGFloat
    var rotation: Angle
    var imageOffset: CGSize
    var caption: String
    var captionSize: CGFloat
    var captionColor: Color
    var captionOffset: CGSize
    var brightness: Double
    var saturation: Double
    var cornerRadius: CGFloat
    var showsCropGuides = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                let imageFrame = PhotoEditorGeometry.imageFrameSize(
                    for: image.size,
                    in: proxy.size,
                    rotation: rotation
                )

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .scaleEffect(zoom)
                    .rotationEffect(rotation)
                    .offset(
                        x: imageOffset.width * proxy.size.width,
                        y: imageOffset.height * proxy.size.height
                    )
                    .brightness(brightness)
                    .saturation(saturation)

                if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(caption)
                        .font(.system(size: captionSize, weight: .bold, design: .rounded))
                        .foregroundStyle(captionColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
                        .padding(.horizontal, 16)
                        .offset(
                            x: captionOffset.width * proxy.size.width,
                            y: captionOffset.height * proxy.size.height
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if showsCropGuides {
                    PhotoCropGuideOverlay(cornerRadius: cornerRadius)
                }
            }
        }
    }
}

private struct PhotoEditorBackdrop: View {
    var image: UIImage
    var brightness: Double
    var saturation: Double

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .brightness(brightness)
                .saturation(saturation)
                .blur(radius: 30)
                .opacity(0.16)
                .overlay(Color.black.opacity(0.58))
                .clipped()
        }
        .allowsHitTesting(false)
    }
}

private struct PhotoCropGuideOverlay: View {
    var cornerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cornerLength = max(26, min(min(size.width, size.height) * 0.14, 46))

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.86), lineWidth: 1.4)

                CropGrid()
                    .stroke(.white.opacity(0.34), lineWidth: 0.9)

                CropCorners(length: cornerLength, radius: cornerRadius)
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                CropEdgeHandles()
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PhotoCropResizeOverlay: View {
    var cornerRadius: CGFloat
    var onResize: (CropResizeHandle, CGSize, Bool) -> Void

    var body: some View {
        ZStack {
            PhotoCropGuideOverlay(cornerRadius: cornerRadius)

            GeometryReader { proxy in
                ForEach(CropResizeHandle.allCases) { handle in
                    handle.hitShape
                        .fill(.white.opacity(0.001))
                        .frame(width: handle.hitSize.width, height: handle.hitSize.height)
                        .position(handle.position(in: proxy.size))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    onResize(handle, value.translation, false)
                                }
                                .onEnded { value in
                                    onResize(handle, value.translation, true)
                                }
                        )
                }
            }
        }
    }
}

private enum CropResizeHandle: CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var id: Self { self }

    var hitSize: CGSize {
        switch self {
        case .top, .bottom:
            CGSize(width: 96, height: 44)
        case .left, .right:
            CGSize(width: 44, height: 96)
        default:
            CGSize(width: 76, height: 76)
        }
    }

    var hitShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    func position(in size: CGSize) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: 0, y: 0)
        case .top:
            CGPoint(x: size.width / 2, y: 0)
        case .topRight:
            CGPoint(x: size.width, y: 0)
        case .right:
            CGPoint(x: size.width, y: size.height / 2)
        case .bottomRight:
            CGPoint(x: size.width, y: size.height)
        case .bottom:
            CGPoint(x: size.width / 2, y: size.height)
        case .bottomLeft:
            CGPoint(x: 0, y: size.height)
        case .left:
            CGPoint(x: 0, y: size.height / 2)
        }
    }
}

private struct CropGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
            let x = rect.minX + rect.width * fraction
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))

            let y = rect.minY + rect.height * fraction
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct CropCorners: Shape {
    var length: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 2
        let minX = rect.minX + inset
        let maxX = rect.maxX - inset
        let minY = rect.minY + inset
        let maxY = rect.maxY - inset
        let cornerRadius = min(radius, length * 0.55)

        path.move(to: CGPoint(x: minX + cornerRadius, y: minY))
        path.addLine(to: CGPoint(x: minX + length, y: minY))
        path.move(to: CGPoint(x: minX, y: minY + cornerRadius))
        path.addLine(to: CGPoint(x: minX, y: minY + length))

        path.move(to: CGPoint(x: maxX - cornerRadius, y: minY))
        path.addLine(to: CGPoint(x: maxX - length, y: minY))
        path.move(to: CGPoint(x: maxX, y: minY + cornerRadius))
        path.addLine(to: CGPoint(x: maxX, y: minY + length))

        path.move(to: CGPoint(x: minX + cornerRadius, y: maxY))
        path.addLine(to: CGPoint(x: minX + length, y: maxY))
        path.move(to: CGPoint(x: minX, y: maxY - cornerRadius))
        path.addLine(to: CGPoint(x: minX, y: maxY - length))

        path.move(to: CGPoint(x: maxX - cornerRadius, y: maxY))
        path.addLine(to: CGPoint(x: maxX - length, y: maxY))
        path.move(to: CGPoint(x: maxX, y: maxY - cornerRadius))
        path.addLine(to: CGPoint(x: maxX, y: maxY - length))

        return path
    }
}

private struct CropEdgeHandles: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let handleLength = max(38, min(min(size.width, size.height) * 0.18, 54))
            let handleThickness: CGFloat = 5

            ZStack {
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: handleLength, height: handleThickness)
                    .position(x: size.width / 2, y: 2)
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: handleLength, height: handleThickness)
                    .position(x: size.width / 2, y: size.height - 2)
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: handleThickness, height: handleLength)
                    .position(x: 2, y: size.height / 2)
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: handleThickness, height: handleLength)
                    .position(x: size.width - 2, y: size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

private enum PhotoEditorGeometry {
    static func cropSize(for ratio: CGFloat, in availableSize: CGSize) -> CGSize {
        guard ratio > 0, availableSize.width > 0, availableSize.height > 0 else { return .zero }
        let availableRatio = availableSize.width / availableSize.height
        if ratio > availableRatio {
            return CGSize(width: availableSize.width, height: availableSize.width / ratio)
        }
        return CGSize(width: availableSize.height * ratio, height: availableSize.height)
    }

    static func centeredCropRect(for ratio: CGFloat, in availableSize: CGSize) -> CGRect {
        guard availableSize.width > 0, availableSize.height > 0 else { return .zero }
        let insetSize = CGSize(
            width: max(availableSize.width - 20, 1),
            height: max(availableSize.height - 20, 1)
        )
        let size = cropSize(for: ratio, in: insetSize)
        return CGRect(
            x: (availableSize.width - size.width) / 2,
            y: (availableSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func rect(from unitRect: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGRect(
            x: unitRect.minX * size.width,
            y: unitRect.minY * size.height,
            width: unitRect.width * size.width,
            height: unitRect.height * size.height
        )
    }

    static func unitRect(from rect: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let clamped = rect.standardized.intersection(CGRect(origin: .zero, size: size))
        return CGRect(
            x: clamped.minX / size.width,
            y: clamped.minY / size.height,
            width: clamped.width / size.width,
            height: clamped.height / size.height
        )
    }

    static func resizedCropRect(
        _ rect: CGRect,
        handle: CropResizeHandle,
        translation: CGSize,
        in stageSize: CGSize,
        lockedRatio: CGFloat?
    ) -> CGRect {
        if let lockedRatio, lockedRatio > 0 {
            return resizedFixedRatioCropRect(
                rect,
                handle: handle,
                translation: translation,
                ratio: lockedRatio,
                in: stageSize
            )
        }

        let minSide = min(max(stageSize.width * 0.26, 104), 150)
        var next = rect

        switch handle {
        case .topLeft:
            next.origin.x += translation.width
            next.size.width -= translation.width
            next.origin.y += translation.height
            next.size.height -= translation.height
        case .top:
            next.origin.y += translation.height
            next.size.height -= translation.height
        case .topRight:
            next.size.width += translation.width
            next.origin.y += translation.height
            next.size.height -= translation.height
        case .right:
            next.size.width += translation.width
        case .bottomRight:
            next.size.width += translation.width
            next.size.height += translation.height
        case .bottom:
            next.size.height += translation.height
        case .bottomLeft:
            next.origin.x += translation.width
            next.size.width -= translation.width
            next.size.height += translation.height
        case .left:
            next.origin.x += translation.width
            next.size.width -= translation.width
        }

        if next.width < minSide {
            if handle.movesLeftEdge {
                next.origin.x = rect.maxX - minSide
            }
            next.size.width = minSide
        }
        if next.height < minSide {
            if handle.movesTopEdge {
                next.origin.y = rect.maxY - minSide
            }
            next.size.height = minSide
        }

        if next.minX < 0 {
            if handle.movesLeftEdge {
                next.size.width += next.minX
            }
            next.origin.x = 0
        }
        if next.minY < 0 {
            if handle.movesTopEdge {
                next.size.height += next.minY
            }
            next.origin.y = 0
        }
        if next.maxX > stageSize.width {
            if handle.movesRightEdge {
                next.size.width = stageSize.width - next.minX
            } else {
                next.origin.x = stageSize.width - next.width
            }
        }
        if next.maxY > stageSize.height {
            if handle.movesBottomEdge {
                next.size.height = stageSize.height - next.minY
            } else {
                next.origin.y = stageSize.height - next.height
            }
        }

        next.size.width = max(next.width, minSide)
        next.size.height = max(next.height, minSide)
        next.origin.x = min(max(next.minX, 0), max(stageSize.width - next.width, 0))
        next.origin.y = min(max(next.minY, 0), max(stageSize.height - next.height, 0))
        return next
    }

    private static func resizedFixedRatioCropRect(
        _ rect: CGRect,
        handle: CropResizeHandle,
        translation: CGSize,
        ratio: CGFloat,
        in stageSize: CGSize
    ) -> CGRect {
        guard stageSize.width > 0, stageSize.height > 0 else { return rect }
        let minSide = min(max(stageSize.width * 0.24, 96), 136)
        let widthDriven = handle.prefersWidthDrivenResize(for: translation, ratio: ratio)
        let proposedWidth: CGFloat

        if widthDriven {
            proposedWidth = handle.movesLeftEdge
                ? rect.width - translation.width
                : rect.width + translation.width
        } else {
            let proposedHeight = handle.movesTopEdge
                ? rect.height - translation.height
                : rect.height + translation.height
            proposedWidth = proposedHeight * ratio
        }

        let width = clampedFixedRatioWidth(
            proposedWidth,
            ratio: ratio,
            minSide: minSide,
            in: stageSize
        )
        let next = fixedRatioRect(
            from: rect,
            handle: handle,
            width: width,
            ratio: ratio
        )
        return shiftedInsideStage(next, in: stageSize)
    }

    private static func clampedFixedRatioWidth(
        _ proposedWidth: CGFloat,
        ratio: CGFloat,
        minSide: CGFloat,
        in stageSize: CGSize
    ) -> CGFloat {
        let minWidth = ratio >= 1 ? minSide * ratio : minSide
        let maxWidth = max(1, min(stageSize.width, stageSize.height * ratio))
        return min(max(proposedWidth, min(minWidth, maxWidth)), maxWidth)
    }

    private static func fixedRatioRect(
        from rect: CGRect,
        handle: CropResizeHandle,
        width: CGFloat,
        ratio: CGFloat
    ) -> CGRect {
        let height = width / ratio
        switch handle {
        case .topLeft:
            return CGRect(x: rect.maxX - width, y: rect.maxY - height, width: width, height: height)
        case .top:
            return CGRect(x: rect.midX - width / 2, y: rect.maxY - height, width: width, height: height)
        case .topRight:
            return CGRect(x: rect.minX, y: rect.maxY - height, width: width, height: height)
        case .right:
            return CGRect(x: rect.minX, y: rect.midY - height / 2, width: width, height: height)
        case .bottomRight:
            return CGRect(x: rect.minX, y: rect.minY, width: width, height: height)
        case .bottom:
            return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        case .bottomLeft:
            return CGRect(x: rect.maxX - width, y: rect.minY, width: width, height: height)
        case .left:
            return CGRect(x: rect.maxX - width, y: rect.midY - height / 2, width: width, height: height)
        }
    }

    private static func shiftedInsideStage(_ rect: CGRect, in stageSize: CGSize) -> CGRect {
        var next = rect.standardized
        if next.width > stageSize.width {
            next.size.width = stageSize.width
        }
        if next.height > stageSize.height {
            next.size.height = stageSize.height
        }
        next.origin.x = min(max(next.minX, 0), max(stageSize.width - next.width, 0))
        next.origin.y = min(max(next.minY, 0), max(stageSize.height - next.height, 0))
        return next
    }

    static func outputSize(for cropSize: CGSize) -> CGSize {
        guard cropSize.width > 0, cropSize.height > 0 else {
            return CGSize(width: 1600, height: 1600)
        }
        let ratio = cropSize.width / cropSize.height
        let maxSide: CGFloat = 1600
        if ratio >= 1 {
            return CGSize(width: maxSide, height: maxSide / ratio)
        }
        return CGSize(width: maxSide * ratio, height: maxSide)
    }

    static func imageFrameSize(for imageSize: CGSize, in cropSize: CGSize, rotation: Angle) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, cropSize.width > 0, cropSize.height > 0 else {
            return cropSize
        }
        let effectiveRatio = rotation.isSidewaysQuarterTurn
            ? imageSize.height / imageSize.width
            : imageSize.width / imageSize.height
        let rotatedBoundingSize = scaledToFillSize(for: effectiveRatio, in: cropSize)
        if rotation.isSidewaysQuarterTurn {
            return CGSize(width: rotatedBoundingSize.height, height: rotatedBoundingSize.width)
        }
        return rotatedBoundingSize
    }

    static func imageBoundingSize(for imageSize: CGSize, in cropSize: CGSize, zoom: CGFloat, rotation: Angle) -> CGSize {
        let frameSize = imageFrameSize(for: imageSize, in: cropSize, rotation: rotation)
        let boundingSize = rotation.isSidewaysQuarterTurn
            ? CGSize(width: frameSize.height, height: frameSize.width)
            : frameSize
        return CGSize(width: boundingSize.width * zoom, height: boundingSize.height * zoom)
    }

    private static func scaledToFillSize(for ratio: CGFloat, in containerSize: CGSize) -> CGSize {
        guard ratio > 0, containerSize.width > 0, containerSize.height > 0 else { return containerSize }
        let containerRatio = containerSize.width / containerSize.height
        if ratio > containerRatio {
            return CGSize(width: containerSize.height * ratio, height: containerSize.height)
        }
        return CGSize(width: containerSize.width, height: containerSize.width / ratio)
    }
}

private extension CropResizeHandle {
    func prefersWidthDrivenResize(for translation: CGSize, ratio: CGFloat) -> Bool {
        switch self {
        case .left, .right:
            true
        case .top, .bottom:
            false
        default:
            abs(translation.width) >= abs(translation.height * ratio)
        }
    }

    var movesLeftEdge: Bool {
        switch self {
        case .topLeft, .bottomLeft, .left:
            true
        default:
            false
        }
    }

    var movesRightEdge: Bool {
        switch self {
        case .topRight, .bottomRight, .right:
            true
        default:
            false
        }
    }

    var movesTopEdge: Bool {
        switch self {
        case .topLeft, .topRight, .top:
            true
        default:
            false
        }
    }

    var movesBottomEdge: Bool {
        switch self {
        case .bottomLeft, .bottomRight, .bottom:
            true
        default:
            false
        }
    }
}

private extension Angle {
    var isSidewaysQuarterTurn: Bool {
        let normalizedDegrees = degrees.truncatingRemainder(dividingBy: 360) + (degrees < 0 ? 360 : 0)
        let quarterTurns = Int((normalizedDegrees / 90).rounded()) % 4
        return quarterTurns == 1 || quarterTurns == 3
    }
}

private enum PhotoEditorAspect: CaseIterable, Identifiable {
    case original
    case square
    case portrait
    case landscape
    case story

    var id: Self { self }

    var label: String {
        switch self {
        case .original:
            "Auto"
        case .square:
            "1:1"
        case .portrait:
            "4:5"
        case .landscape:
            "16:9"
        case .story:
            "9:16"
        }
    }

    func ratio(for image: UIImage) -> CGFloat {
        switch self {
        case .original:
            max(image.size.width / max(image.size.height, 1), 0.2)
        case .square:
            1
        case .portrait:
            4 / 5
        case .landscape:
            16 / 9
        case .story:
            9 / 16
        }
    }

    func lockedRatio(for image: UIImage) -> CGFloat? {
        switch self {
        case .original:
            nil
        default:
            ratio(for: image)
        }
    }

    func outputSize(for image: UIImage) -> CGSize {
        let ratio = ratio(for: image)
        let maxSide: CGFloat = 1600
        if ratio >= 1 {
            return CGSize(width: maxSide, height: maxSide / ratio)
        }
        return CGSize(width: maxSide * ratio, height: maxSide)
    }
}

private enum PhotoEditorTool: CaseIterable, Identifiable {
    case crop
    case text
    case tune

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .crop:
            "crop"
        case .text:
            "textformat"
        case .tune:
            "wand.and.sparkles"
        }
    }

    func title(_ copy: AppCopy) -> String {
        switch self {
        case .crop:
            copy.t("crop")
        case .text:
            copy.t("text")
        case .tune:
            copy.t("tune")
        }
    }
}

private enum PhotoEditorTextColor: CaseIterable, Identifiable {
    case white
    case black
    case yellow
    case blue

    var id: Self { self }

    var color: Color {
        switch self {
        case .white:
            .white
        case .black:
            .black
        case .yellow:
            .yellow
        case .blue:
            .blue
        }
    }
}

private struct MessageDateSeparator: View {
    var date: Date

    var body: some View {
        Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(.tertiaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemBackground), in: Capsule(style: .continuous))
            .frame(maxWidth: .infinity)
    }
}

private struct AttachmentActionButton: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.30), in: Circle())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .padding(13)
        .background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.42), lineWidth: 1)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var fileExtensionLabel: String? {
        URL(fileURLWithPath: self).pathExtension.uppercased().nilIfBlank
    }
}

private enum LocalMessageTranslator {
    private static let phraseTranslations: [String: [String: String]] = [
        "can you send the project link again?": [
            "ru": "Можешь отправить ссылку на проект еще раз?",
            "th": "ช่วยส่งลิงก์โปรเจกต์อีกครั้งได้ไหม?",
            "de": "Kannst du den Projektlink noch einmal senden?",
            "uk": "Можеш надіслати посилання на проєкт ще раз?",
            "pl": "Możesz ponownie wysłać link do projektu?",
            "zh": "你能再发送一次项目链接吗？",
            "hi": "क्या आप प्रोजेक्ट लिंक फिर से भेज सकते हैं?",
            "fil": "Puwede mo bang ipadala ulit ang project link?",
            "fr": "Peux-tu renvoyer le lien du projet ?",
            "es": "¿Puedes enviar el enlace del proyecto otra vez?"
        ],
        "staging account checks are ready.": [
            "ru": "Проверки staging-аккаунта готовы.",
            "th": "การตรวจสอบบัญชี staging พร้อมแล้ว",
            "de": "Die Prüfungen des Staging-Kontos sind bereit.",
            "uk": "Перевірки staging-акаунта готові.",
            "pl": "Kontrole konta staging są gotowe.",
            "zh": "预发布账号检查已准备好。",
            "hi": "स्टेजिंग खाते की जांच तैयार है।",
            "fil": "Handa na ang staging account checks.",
            "fr": "Les vérifications du compte de staging sont prêtes.",
            "es": "Las comprobaciones de la cuenta de staging están listas."
        ],
        "sure: https://knotlink.local/chat": [
            "ru": "Конечно: https://knotlink.local/chat",
            "th": "ได้เลย: https://knotlink.local/chat",
            "de": "Klar: https://knotlink.local/chat",
            "uk": "Звісно: https://knotlink.local/chat",
            "pl": "Jasne: https://knotlink.local/chat",
            "zh": "当然：https://knotlink.local/chat",
            "hi": "ज़रूर: https://knotlink.local/chat",
            "fil": "Sige: https://knotlink.local/chat",
            "fr": "Bien sûr : https://knotlink.local/chat",
            "es": "Claro: https://knotlink.local/chat"
        ]
    ]

    private static let wordTranslations: [String: [String: String]] = [
        "hello": ["ru": "привет", "th": "สวัสดี", "de": "hallo", "uk": "привіт", "pl": "cześć", "zh": "你好", "hi": "नमस्ते", "fil": "kumusta", "fr": "bonjour", "es": "hola"],
        "thanks": ["ru": "спасибо", "th": "ขอบคุณ", "de": "danke", "uk": "дякую", "pl": "dzięki", "zh": "谢谢", "hi": "धन्यवाद", "fil": "salamat", "fr": "merci", "es": "gracias"],
        "yes": ["ru": "да", "th": "ใช่", "de": "ja", "uk": "так", "pl": "tak", "zh": "是", "hi": "हाँ", "fil": "oo", "fr": "oui", "es": "sí"],
        "no": ["ru": "нет", "th": "ไม่", "de": "nein", "uk": "ні", "pl": "nie", "zh": "不", "hi": "नहीं", "fil": "hindi", "fr": "non", "es": "no"],
        "can": ["ru": "можешь", "th": "สามารถ", "de": "kannst", "uk": "можеш", "pl": "możesz", "zh": "能", "hi": "कर सकते", "fil": "puwede", "fr": "peux", "es": "puedes"],
        "you": ["ru": "ты", "th": "คุณ", "de": "du", "uk": "ти", "pl": "ty", "zh": "你", "hi": "आप", "fil": "mo", "fr": "tu", "es": "tú"],
        "send": ["ru": "отправить", "th": "ส่ง", "de": "senden", "uk": "надіслати", "pl": "wysłać", "zh": "发送", "hi": "भेजें", "fil": "ipadala", "fr": "envoyer", "es": "enviar"],
        "project": ["ru": "проект", "th": "โปรเจกต์", "de": "Projekt", "uk": "проєкт", "pl": "projekt", "zh": "项目", "hi": "प्रोजेक्ट", "fil": "project", "fr": "projet", "es": "proyecto"],
        "link": ["ru": "ссылка", "th": "ลิงก์", "de": "Link", "uk": "посилання", "pl": "link", "zh": "链接", "hi": "लिंक", "fil": "link", "fr": "lien", "es": "enlace"],
        "again": ["ru": "снова", "th": "อีกครั้ง", "de": "nochmal", "uk": "знову", "pl": "ponownie", "zh": "再次", "hi": "फिर", "fil": "ulit", "fr": "encore", "es": "otra vez"],
        "staging": ["ru": "staging", "th": "staging", "de": "Staging", "uk": "staging", "pl": "staging", "zh": "预发布", "hi": "स्टेजिंग", "fil": "staging", "fr": "staging", "es": "staging"],
        "account": ["ru": "аккаунт", "th": "บัญชี", "de": "Konto", "uk": "акаунт", "pl": "konto", "zh": "账号", "hi": "खाता", "fil": "account", "fr": "compte", "es": "cuenta"],
        "checks": ["ru": "проверки", "th": "การตรวจสอบ", "de": "Prüfungen", "uk": "перевірки", "pl": "kontrole", "zh": "检查", "hi": "जांच", "fil": "checks", "fr": "vérifications", "es": "comprobaciones"],
        "ready": ["ru": "готовы", "th": "พร้อม", "de": "bereit", "uk": "готові", "pl": "gotowe", "zh": "准备好了", "hi": "तैयार", "fil": "handa", "fr": "prêtes", "es": "listas"]
    ]

    static func translate(_ text: String, to languageCode: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, languageCode != AppLanguageOption.english.id else { return nil }

        let normalized = trimmed.lowercased()
        if let phrase = phraseTranslations[normalized]?[languageCode] {
            return phrase
        }

        let translated = translateWords(in: trimmed, to: languageCode)
        return translated == trimmed ? nil : translated
    }

    private static func translateWords(in text: String, to languageCode: String) -> String {
        var output = ""
        var currentWord = ""

        func flushWord() {
            guard !currentWord.isEmpty else { return }
            let lowercased = currentWord.lowercased()
            let replacement = wordTranslations[lowercased]?[languageCode] ?? currentWord
            output += replacement
            currentWord = ""
        }

        for character in text {
            if character.isLetter {
                currentWord.append(character)
            } else {
                flushWord()
                output.append(character)
            }
        }
        flushWord()
        return output
    }
}

private struct MessagesContactHeader: View {
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    var conversation: Conversation
    var avatarSize: CGFloat = 50

    var body: some View {
        VStack(spacing: 4) {
            AvatarView(title: conversation.title, id: conversation.id, imageURL: conversation.peerAvatarURL, size: avatarSize)
            HStack(spacing: 3) {
                Text(conversation.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.title), \(copy.f("participants", conversation.members.count))")
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}

private struct MessageBubble: View {
    var message: Message
    var isMine: Bool
    var showSender: Bool
    var startsGroup: Bool
    var endsGroup: Bool
    var avatarTitle: String
    var translatedBody: String?
    var currentUserID: Int?
    var onReact: (String?) -> Void
    @State private var showReactionPicker = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 72) }

            if !isMine {
                if endsGroup {
                    AvatarView(title: avatarTitle, id: message.senderID, size: 28)
                        .padding(.trailing, 1)
                } else {
                    Color.clear
                        .frame(width: 29, height: 1)
                }
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if showSender {
                    Text(message.senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.leading, 12)
                        .padding(.bottom, 2)
                }

                if !message.attachments.isEmpty {
                    VStack(alignment: isMine ? .trailing : .leading, spacing: 7) {
                        ForEach(message.attachments) { attachment in
                            MessageAttachmentBubble(attachment: attachment, isMine: isMine)
                        }
                    }
                }

                if !message.body.isEmpty {
                    VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                        Text(translatedBody ?? message.body)
                            .font(.body)
                            .foregroundStyle(isMine ? .white : .primary)
                            .textSelection(.enabled)

                        if let translatedBody, translatedBody != message.body {
                            Divider()
                                .opacity(0.22)
                            Text("Original: \(message.body)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(isMine ? .white.opacity(0.70) : .secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(bubbleColor, in: bubbleShape)
                }

                if !message.reactions.isEmpty {
                    ReactionSummaryView(reactions: message.reactions, isMine: isMine)
                        .padding(.top, -1)
                }

                if showReactionPicker {
                    MessageReactionPicker(
                        selectedEmoji: currentUserReaction,
                        onSelect: { emoji in
                            onReact(emoji == currentUserReaction ? nil : emoji)
                            withAnimation(.snappy(duration: 0.18)) {
                                showReactionPicker = false
                            }
                        }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .padding(.top, 3)
                }
            }
            .frame(maxWidth: 286, alignment: isMine ? .trailing : .leading)

            if !isMine {
                Spacer(minLength: 36)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                showReactionPicker.toggle()
            }
        }
        .overlay(alignment: isMine ? .bottomTrailing : .bottomLeading) {
            if endsGroup {
                Text(message.createdAt, style: .time)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(.horizontal, 8)
                    .offset(x: isMine ? -2 : 35, y: 17)
            }
        }
        .padding(.bottom, endsGroup ? 18 : 0)
    }

    private var currentUserReaction: String? {
        guard let currentUserID else { return nil }
        return message.reactions.first { $0.userID == currentUserID }?.emoji
    }

    private var bubbleColor: Color {
        isMine ? Color.blue : Color(.systemGray5)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: isMine ? 18 : (startsGroup ? 18 : 7),
                bottomLeading: isMine ? 18 : (endsGroup ? 6 : 7),
                bottomTrailing: isMine ? (endsGroup ? 6 : 7) : 18,
                topTrailing: isMine ? (startsGroup ? 18 : 7) : 18
            ),
            style: .continuous
        )
    }
}

private struct MessageReactionPicker: View {
    var selectedEmoji: String?
    var onSelect: (String) -> Void

    private let emojis = ["❤️", "👍", "😂", "😮", "😢", "🙏"]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 19))
                        .frame(width: 34, height: 34)
                        .background(
                            selectedEmoji == emoji
                                ? Color.blue.opacity(0.18)
                                : Color.white.opacity(0.28),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(selectedEmoji == emoji ? Color.blue.opacity(0.36) : Color.white.opacity(0.28), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .glassCard(tint: .white.opacity(0.12), in: Capsule(style: .continuous), interactive: true)
    }
}

private struct ReactionSummaryView: View {
    var reactions: [MessageReaction]
    var isMine: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(groupedReactions, id: \.emoji) { item in
                HStack(spacing: 3) {
                    Text(item.emoji)
                    if item.count > 1 {
                        Text("\(item.count)")
                            .font(.caption2.weight(.bold))
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(isMine ? .white : .primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(isMine ? .white.opacity(0.18) : .white.opacity(0.78), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(isMine ? 0.18 : 0.42), lineWidth: 1)
                }
            }
        }
    }

    private var groupedReactions: [(emoji: String, count: Int)] {
        Dictionary(grouping: reactions, by: \.emoji)
            .map { (emoji: $0.key, count: $0.value.count) }
            .sorted { $0.emoji < $1.emoji }
    }
}

private struct MessageAttachmentBubble: View {
    var attachment: MessageAttachment
    var isMine: Bool
    @State private var showPhotoPreview = false

    var body: some View {
        switch attachment.kind {
        case .photo:
            photoView
                .fullScreenCover(isPresented: $showPhotoPreview) {
                    if let image = photoImage {
                        FullscreenPhotoViewer(image: image, title: attachment.title)
                    }
                }
        case .video:
            fileStyleView(icon: "play.fill", title: attachment.title, subtitle: "Video")
        case .videoCircle:
            VideoCircleMessagePlayer(attachment: attachment, isMine: isMine)
        case .file:
            fileStyleView(icon: "doc.fill", title: attachment.title, subtitle: attachment.title.fileExtensionLabel ?? "File")
        case .voice:
            VoiceMessagePlayer(attachment: attachment, isMine: isMine)
        }
    }

    private var photoView: some View {
        Group {
            if let image = photoImage {
                Button {
                    showPhotoPreview = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 252, height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Label(attachment.title, systemImage: "photo.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.30), in: Capsule(style: .continuous))
                                .padding(8)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(attachment.title)
            } else {
                fileStyleView(icon: "photo.fill", title: attachment.title, subtitle: "Photo")
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }

    private var photoImage: UIImage? {
        guard let data = attachment.data else { return nil }
        return UIImage(data: data)
    }

    private func fileStyleView(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isMine ? .white : Color.knotBlue)
                .frame(width: 42, height: 42)
                .background(isMine ? .white.opacity(0.18) : .white.opacity(0.56), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isMine ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isMine ? .white.opacity(0.72) : .secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 252)
        .frame(minHeight: 68)
        .padding(10)
        .background(isMine ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(isMine ? 0.18 : 0.42), lineWidth: 1)
        }
    }
}

@MainActor
private final class VoiceMessageRecorder: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var isPaused = false
    @Published var duration: TimeInterval = 0
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var timer: Timer?

    func start() {
        errorMessage = nil
        let permissionHandler: (Bool) -> Void = { [weak self] allowed in
            Task { @MainActor in
                guard let self else { return }
                guard allowed else {
                    self.errorMessage = "Microphone permission is needed."
                    return
                }
                self.beginRecording()
            }
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: permissionHandler)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(permissionHandler)
        }
    }

    func togglePause() {
        guard let recorder else { return }
        if recorder.isRecording {
            accumulatedDuration += Date().timeIntervalSince(startedAt ?? Date())
            recorder.pause()
            timer?.invalidate()
            timer = nil
            isPaused = true
            return
        }

        startedAt = Date()
        recorder.record()
        startTimer()
        isPaused = false
    }

    func finish() -> MessageAttachment? {
        guard let recorder, let recordingURL else { return nil }
        if recorder.isRecording {
            accumulatedDuration += Date().timeIntervalSince(startedAt ?? Date())
        }
        recorder.stop()
        timer?.invalidate()
        timer = nil

        defer { resetState(keepingFile: false) }

        guard
            let data = try? Data(contentsOf: recordingURL),
            !data.isEmpty
        else {
            errorMessage = "Voice message could not be saved."
            return nil
        }

        return MessageAttachment(
            title: "Voice message",
            kind: .voice,
            duration: max(duration, accumulatedDuration),
            data: data,
            fileURL: nil
        )
    }

    func cancel() {
        recorder?.stop()
        resetState(keepingFile: false)
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("knotlink-voice-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            recorder.record()

            self.recorder = recorder
            recordingURL = url
            startedAt = Date()
            accumulatedDuration = 0
            duration = 0
            isPaused = false
            isActive = true
            startTimer()
        } catch {
            errorMessage = "Voice recording could not start."
            resetState(keepingFile: false)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.recorder?.isRecording == true {
                    self.duration = self.accumulatedDuration + Date().timeIntervalSince(self.startedAt ?? Date())
                }
            }
        }
    }

    private func resetState(keepingFile: Bool) {
        timer?.invalidate()
        timer = nil
        recorder = nil
        startedAt = nil
        accumulatedDuration = 0
        duration = 0
        isPaused = false
        isActive = false
        if !keepingFile, let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }
}

private struct VoiceRecordingPanel: View {
    @ObservedObject var recorder: VoiceMessageRecorder
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Circle()
                    .fill(recorder.isPaused ? Color.orange : Color.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: (recorder.isPaused ? Color.orange : Color.red).opacity(0.28), radius: 8)
                Text(recorder.isPaused ? "Paused" : "Recording")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatVoiceDuration(recorder.duration))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VoiceWaveform(isActive: !recorder.isPaused, tint: Color.knotSky)
                .frame(height: 42)

            HStack(spacing: 9) {
                Button {
                    recorder.togglePause()
                } label: {
                    Label(recorder.isPaused ? "Resume" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                Button(role: .destructive, action: onCancel) {
                    Label("Cancel", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.bordered)
        }
        .padding(12)
        .glassCard(tint: .white.opacity(0.18), in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
    }
}

private struct VoiceMessagePlayer: View {
    var attachment: MessageAttachment
    var isMine: Bool
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var speedIndex = 0
    @State private var playbackTimer: Timer?

    private let speeds: [Float] = [1, 1.5, 2]

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.22), in: Circle())
            }
            .buttonStyle(.plain)

            VoiceWaveform(isActive: isPlaying, tint: .white)
                .frame(height: 34)

            Text(formatVoiceDuration(attachment.duration ?? player?.duration ?? 0))
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white.opacity(0.82))

            Button {
                cycleSpeed()
            } label: {
                Text(speedLabel)
                    .font(.caption2.weight(.black))
                    .frame(minWidth: 34)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.20), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .frame(width: 264)
        .padding(10)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.56, blue: 0.95),
                    Color(red: 0.05, green: 0.38, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(.white.opacity(0.26), lineWidth: 1)
        }
        .shadow(color: Color.blue.opacity(0.18), radius: 12, y: 6)
        .onDisappear {
            stopPlayback()
        }
    }

    private var speedLabel: String {
        speeds[speedIndex].truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(speeds[speedIndex]))x"
            : "\(speeds[speedIndex])x"
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        if player == nil {
            guard let data = attachment.data, let newPlayer = try? AVAudioPlayer(data: data) else { return }
            newPlayer.enableRate = true
            newPlayer.prepareToPlay()
            player = newPlayer
        }

        player?.rate = speeds[speedIndex]
        player?.play()
        isPlaying = true
        startPlaybackTimer()
    }

    private func cycleSpeed() {
        speedIndex = (speedIndex + 1) % speeds.count
        player?.rate = speeds[speedIndex]
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            if player?.isPlaying != true {
                isPlaying = false
                playbackTimer?.invalidate()
                playbackTimer = nil
            }
        }
    }

    private func stopPlayback() {
        player?.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
    }
}

private struct VoiceWaveform: View {
    var isActive: Bool
    var tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<22, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(tint.opacity(isActive ? 0.88 : 0.52))
                    .frame(width: 3, height: waveHeight(for: index))
                    .scaleEffect(y: isActive ? activeScale(for: index) : 1, anchor: .center)
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.54 + Double(index % 5) * 0.04).repeatForever(autoreverses: true).delay(Double(index) * 0.018)
                            : .default,
                        value: isActive
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func waveHeight(for index: Int) -> CGFloat {
        CGFloat(10 + (index * 7 % 24))
    }

    private func activeScale(for index: Int) -> CGFloat {
        CGFloat(0.72 + Double((index * 5) % 7) * 0.12)
    }
}

private func formatVoiceDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration.rounded()))
    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
}

private struct VideoCircleCaptureView: UIViewControllerRepresentable {
    var onComplete: (MessageAttachment) -> Void
    var onCancel: () -> Void
    static var canCaptureVideoCircle: Bool {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return false }
        return UIImagePickerController.availableMediaTypes(for: .camera)?.contains(UTType.movie.identifier) == true
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        if UIImagePickerController.availableMediaTypes(for: .camera)?.contains(UTType.movie.identifier) == true {
            picker.mediaTypes = [UTType.movie.identifier]
        }
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeMedium
        if UIImagePickerController.availableCaptureModes(for: .front)?.contains(NSNumber(value: UIImagePickerController.CameraCaptureMode.video.rawValue)) == true {
            picker.cameraDevice = .front
            picker.cameraCaptureMode = .video
        } else if UIImagePickerController.availableCaptureModes(for: .rear)?.contains(NSNumber(value: UIImagePickerController.CameraCaptureMode.video.rawValue)) == true {
            picker.cameraDevice = .rear
            picker.cameraCaptureMode = .video
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onComplete: (MessageAttachment) -> Void
        var onCancel: () -> Void

        init(onComplete: @escaping (MessageAttachment) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let sourceURL = info[.mediaURL] as? URL else {
                onCancel()
                return
            }

            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("knotlink-video-circle-\(UUID().uuidString)")
                .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension)

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                onCancel()
                return
            }

            let asset = AVURLAsset(url: destinationURL)
            let duration = CMTimeGetSeconds(asset.duration)
            onComplete(
                MessageAttachment(
                    title: "Video circle",
                    kind: .videoCircle,
                    duration: duration.isFinite ? duration : nil,
                    data: nil,
                    fileURL: destinationURL
                )
            )
        }
    }
}

private struct VideoCircleMessagePlayer: View {
    var attachment: MessageAttachment
    var isMine: Bool
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        Button {
            togglePlayback()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.19, green: 0.55, blue: 0.95),
                                Color(red: 0.05, green: 0.35, blue: 0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let player {
                    VideoPlayer(player: player)
                        .clipShape(Circle())
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: "video.circle.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Circle()
                    .stroke(.white.opacity(0.34), lineWidth: 2)

                VStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.caption.weight(.black))
                        Text(formatVoiceDuration(attachment.duration ?? 0))
                            .font(.caption2.monospacedDigit().weight(.black))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.28), in: Capsule(style: .continuous))
                    .padding(.bottom, 10)
                }
            }
            .frame(width: 176, height: 176)
            .shadow(color: Color.blue.opacity(0.18), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .onAppear {
            preparePlayer()
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    private func preparePlayer() {
        guard player == nil, let fileURL = attachment.fileURL else { return }
        player = AVPlayer(url: fileURL)
    }

    private func togglePlayback() {
        preparePlayer()
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        if player.currentItem?.currentTime() == player.currentItem?.duration {
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
    }
}

private struct FullscreenPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    var image: UIImage
    var title: String
    @State private var scale = 1.0
    @State private var lastScale = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoomGesture)
                    .simultaneousGesture(dragGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy(duration: 0.24)) {
                            if scale > 1 {
                                resetZoom()
                            } else {
                                scale = 2
                                lastScale = 2
                            }
                        }
                    }
            }
            .ignoresSafeArea()

            VStack {
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")

                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.90))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)

                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        .statusBarHidden()
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 4)
            }
            .onEnded { _ in
                if scale <= 1.02 {
                    withAnimation(.snappy(duration: 0.22)) {
                        resetZoom()
                    }
                } else {
                    lastScale = scale
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

private struct ChatInfoView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    var conversation: Conversation

    var body: some View {
        NavigationStack {
            List {
                Section(copy.t("members")) {
                    ForEach(activeConversation.members) { member in
                        memberLabel(member)
                    }
                }

                if activeConversation.isGroup {
                    Section(copy.t("invitePeople")) {
                        let invitees = store.availableGroupInviteContacts(for: activeConversation.id)
                        if invitees.isEmpty {
                            Text(copy.t("allContactsInGroup"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(invitees) { contact in
                                Button {
                                    store.inviteContacts([contact], toGroup: activeConversation.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        AvatarView(title: contact.displayName, id: contact.id, imageURL: contact.avatarURL, size: 34)
                                        VStack(alignment: .leading) {
                                            Text(contact.displayName)
                                                .foregroundStyle(.primary)
                                            Text("@\(contact.username)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(Color.knotBlue)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(copy.t("linksAndDocs")) {
                    let links = activeConversation.sharedLinks()
                    if links.isEmpty {
                        Text(copy.t("noSharedLinksYet"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(links, id: \.self) { url in
                            Link(url.absoluteString, destination: url)
                        }
                    }
                }
            }
            .navigationTitle(activeConversation.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var activeConversation: Conversation {
        store.conversations.first { $0.id == conversation.id } ?? conversation
    }

    private func memberLabel(_ member: User) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(member.displayName)
                Text("@\(member.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            AvatarView(title: member.displayName, id: member.id, imageURL: member.avatarURL, size: 34)
        }
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}
