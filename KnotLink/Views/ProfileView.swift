import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    @State private var displayName = ""
    @State private var username = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var showAvatarOptions = false
    @State private var showAvatarPicker = false
    @State private var showAvatarViewer = false
    @State private var selectedAvatarItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: copy.t("profile"), subtitle: copy.t("profileSubtitle"))

                if let user = store.currentUser {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            Button {
                                showAvatarOptions = true
                            } label: {
                                AvatarView(title: user.displayName, id: user.id, imageURL: user.avatarURL, size: 76)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "camera.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 26, height: 26)
                                            .background(Color.accentColor, in: Circle())
                                            .overlay(Circle().stroke(.white, lineWidth: 2))
                                            .offset(x: 2, y: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName).font(.title2.weight(.bold))
                                Text("@\(user.username)").foregroundStyle(.secondary)
                            }
                        }

                        formField(copy.t("displayName"), text: $displayName)
                        formField(copy.t("username"), text: $username, prefix: "@")
                        formField(copy.t("firstName"), text: $firstName)
                        formField(copy.t("lastName"), text: $lastName)

                        Button(copy.t("saveProfile")) {
                            store.updateProfile(displayName: displayName, username: username, firstName: firstName, lastName: lastName)
                        }
                        .prominentGlassButton()
                    }
                    .padding(18)
                    .glassCard(in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    ProfileMetaGrid(user: user)
                }
            }
            .padding()
            .padding(.bottom, 88)
        }
        .navigationTitle(copy.t("profile"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: syncFields)
        .onChange(of: store.currentUser) { syncFields() }
        .confirmationDialog(copy.t("profilePhoto"), isPresented: $showAvatarOptions, titleVisibility: .visible) {
            Button(copy.t("changeProfilePhoto")) {
                showAvatarPicker = true
            }
            Button(copy.t("viewProfilePhoto")) {
                showAvatarViewer = true
            }
            Button(copy.t("cancel"), role: .cancel) {}
        }
        .photosPicker(isPresented: $showAvatarPicker, selection: $selectedAvatarItem, matching: .images)
        .onChange(of: selectedAvatarItem) { _, item in
            handleAvatarSelection(item)
        }
        .fullScreenCover(isPresented: $showAvatarViewer) {
            if let user = store.currentUser {
                ProfileAvatarViewer(user: user)
            }
        }
    }

    private func syncFields() {
        guard let user = store.currentUser else { return }
        displayName = user.displayName
        username = user.username
        firstName = user.firstName ?? ""
        lastName = user.lastName ?? ""
    }

    private func formField(_ title: String, text: Binding<String>, prefix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            HStack {
                if let prefix { Text(prefix).foregroundStyle(.secondary) }
                TextField(title, text: text)
                    .textInputAutocapitalization(.never)
            }
            .padding(12)
            .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }

    private func handleAvatarSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            await MainActor.run {
                store.updateAvatar(data: data)
                selectedAvatarItem = nil
            }
        }
    }
}

private struct ProfileAvatarViewer: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    var user: User

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AvatarView(title: user.displayName, id: user.id, imageURL: user.avatarURL, size: 280)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .accessibilityLabel(copy.t("close"))
            .padding()
        }
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}

private struct ProfileMetaGrid: View {
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    var user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                meta(copy.t("email"), user.email ?? copy.t("notSet"))
                meta(copy.t("phone"), user.phoneNumber ?? copy.t("notSet"))
            }
            meta(copy.t("memberSince"), user.createdAt.formatted(date: .abbreviated, time: .omitted))
        }
        .padding(16)
        .glassCard(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func meta(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}
