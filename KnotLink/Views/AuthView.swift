import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var phoneNumber = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                AppMark()
                VStack(spacing: 8) {
                    Text("KnotLink")
                        .font(.largeTitle.weight(.bold))
                    Text(store.authModeIsSignup ? copy.t("authSignupSubtitle") : copy.t("authLoginSubtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    OAuthButton(provider: .google, title: copy.t("continueWithGoogle")) {
                        Task { await store.authenticate(with: .google) }
                    }
                    OAuthButton(provider: .mailRu, title: copy.t("continueWithMailRu")) {
                        Task { await store.authenticate(with: .mailRu) }
                    }
                }

                HStack(spacing: 12) {
                    Rectangle()
                        .fill(.white.opacity(0.22))
                        .frame(height: 1)
                    Text(copy.t("or"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(.white.opacity(0.22))
                        .frame(height: 1)
                }

                VStack(spacing: 12) {
                    Picker(copy.t("authenticationMode"), selection: $store.authModeIsSignup) {
                        Text(copy.t("login")).tag(false)
                        Text(copy.t("register")).tag(true)
                    }
                    .pickerStyle(.segmented)

                    if store.authModeIsSignup {
                        AuthInput(systemImage: "person.text.rectangle.fill", placeholder: copy.t("displayName"), text: $displayName)
                        AuthInput(systemImage: "at", placeholder: copy.t("username"), text: $username, autocapitalization: .never)
                    }

                    AuthInput(systemImage: "envelope.fill", placeholder: copy.t("email"), text: $email, keyboardType: .emailAddress, autocapitalization: .never)
                    if store.authModeIsSignup {
                        AuthInput(systemImage: "phone.fill", placeholder: copy.t("phone"), text: $phoneNumber, keyboardType: .phonePad, autocapitalization: .never)
                    }
                    AuthInput(systemImage: "lock.fill", placeholder: copy.t("password"), text: $password, isSecure: true)

                    if store.authModeIsSignup {
                        AuthInput(systemImage: "checkmark.shield.fill", placeholder: copy.t("confirmPassword"), text: $confirmPassword, isSecure: true)
                    }

                    Button {
                        submitManualAuth()
                    } label: {
                        Label(store.authModeIsSignup ? copy.t("createAccount") : copy.t("login"), systemImage: store.authModeIsSignup ? "envelope.badge.fill" : "arrow.right.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.knotBlue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(24)
            .frame(maxWidth: 430)
            .glassCard(tint: .white.opacity(0.18), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .padding()
        .scrollIndicators(.hidden)
        .overlay {
            if store.isLoading {
                ProgressView()
                    .padding(20)
                    .glassCard(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func submitManualAuth() {
        Task {
            if store.authModeIsSignup {
                await store.registerWithEmail(
                    displayName: displayName,
                    username: username,
                    email: email,
                    phoneNumber: phoneNumber,
                    password: password,
                    confirmPassword: confirmPassword
                )
            } else {
                await store.loginWithEmail(email: email, password: password)
            }
        }
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}

private struct OAuthButton: View {
    var provider: AuthProvider
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: provider.symbol)
                    .frame(width: 24)
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .glassCard(tint: .white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
    }
}

private struct AppMark: View {
    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .padding(6)
        .frame(width: 96, height: 96)
        .shadow(color: Color.knotBlue.opacity(0.28), radius: 24, y: 12)
        .liquidGlass(tint: Color.knotSky.opacity(0.18), shape: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
    }
}

private struct AuthInput: View {
    var systemImage: String
    var placeholder: String
    @Binding var text: String
    var isSecure = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(autocapitalization)
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .glassCard(tint: .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
    }
}
