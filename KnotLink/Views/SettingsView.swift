import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @State private var selectedTab: SettingsTab = .profile
    @State private var pushNotifications = true
    @State private var messagePreviews = true
    @State private var contactAlerts = true
    @State private var notificationSound = "Default"
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    @AppStorage("knotlink.autoTranslate") private var autoTranslate = false
    @AppStorage("knotlink.translateToCode") private var translateToCode = AppLanguageOption.english.id

    private let supportedLanguages = AppLanguageOption.supported

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case profile
        case notifications
        case languages
        case devices
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: copy.t("settings"), subtitle: copy.t("settingsSubtitle"))

                Picker(copy.t("settings"), selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(copy.settingsTabTitle(tab.rawValue)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedTab {
                case .profile:
                    profilePanel
                case .notifications:
                    notificationsPanel
                case .languages:
                    languagesPanel
                case .devices:
                    devicesPanel
                }
            }
            .padding()
            .padding(.bottom, 88)
        }
        .navigationTitle(copy.t("settings"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var profilePanel: some View {
        VStack(spacing: 14) {
            if let user = store.currentUser {
                SettingsInfoRow(label: copy.t("username"), value: "@\(user.username)")
                SettingsInfoRow(label: copy.t("displayName"), value: user.displayName)
                SettingsInfoRow(label: copy.t("email"), value: user.email ?? copy.t("notSet"))
                SettingsInfoRow(label: copy.t("phone"), value: user.phoneNumber ?? copy.t("notSet"))
            }
            statusCard(title: copy.t("passwordChangesUnavailable"), body: copy.t("oauthPasswordUnavailable"))
            Button(copy.t("logOut"), role: .destructive) { store.logout() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsPanel()
    }

    private var notificationsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(copy.t("enablePushNotifications"), isOn: $pushNotifications)
            Toggle(copy.t("showMessagePreviews"), isOn: $messagePreviews)
            Toggle(copy.t("notifyContactRequests"), isOn: $contactAlerts)
            Picker(copy.t("notificationSound"), selection: $notificationSound) {
                Text(copy.t("soundDefault")).tag("Default")
                Text(copy.t("soundSoftChime")).tag("Soft chime")
                Text(copy.t("soundClassicPing")).tag("Classic ping")
                Text(copy.t("soundSilent")).tag("Silent")
            }
            Button(copy.t("saveNotificationSettings")) {
                store.saveSettingsSummary(copy.t("notificationSettingsSaved"))
            }
            .prominentGlassButton()
        }
        .settingsPanel()
    }

    private var languagesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            languagePickerRow(
                title: copy.t("appLanguageTitle"),
                detail: copy.t("appLanguageDetail"),
                selection: $appLanguageCode
            )
            Divider().opacity(0.35)
            Toggle(copy.t("autoTranslationTitle"), isOn: $autoTranslate)
                .font(.headline)
                .tint(Color.knotBlue)
            languagePickerRow(
                title: copy.t("translateToTitle"),
                detail: copy.t("translateToDetail"),
                selection: $translateToCode
            )
            .disabled(!autoTranslate)
            .opacity(autoTranslate ? 1 : 0.55)
            Button(copy.t("saveLanguageSettings")) {
                store.saveSettingsSummary(
                    copy.languageSavedMessage(
                        appLanguage: appLanguage.nativeName,
                        translationLanguage: translateLanguage.nativeName,
                        autoTranslate: autoTranslate
                    )
                )
            }
            .prominentGlassButton()
        }
        .settingsPanel()
    }

    private func languagePickerRow(title: String, detail: String, selection: Binding<String>) -> some View {
        let selectedLanguage = language(for: selection.wrappedValue)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Picker(title, selection: selection) {
                    ForEach(supportedLanguages) { option in
                        Text(option.nativeName).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.knotBlue)

                Text(selectedLanguage.englishName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var appLanguage: AppLanguageOption {
        language(for: appLanguageCode)
    }

    private var translateLanguage: AppLanguageOption {
        language(for: translateToCode)
    }

    private func language(for id: String) -> AppLanguageOption {
        supportedLanguages.first { $0.id == id } ?? .english
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }

    private var devicesPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "iphone.gen3")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading) {
                    Text(copy.t("thisDevice")).font(.headline)
                    Text(copy.t("activeNow")).font(.subheadline).foregroundStyle(.secondary)
                    Text(copy.t("lastActiveJustNow")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(copy.t("current"))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.16), in: Capsule())
            }
            Button(copy.t("saveDevicePreferences")) {
                store.saveSettingsSummary(copy.t("devicePreferencesSaved"))
            }
            .prominentGlassButton()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsPanel()
    }

    private func statusCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SettingsInfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

private extension View {
    func settingsPanel() -> some View {
        self
            .padding(16)
            .glassCard(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
