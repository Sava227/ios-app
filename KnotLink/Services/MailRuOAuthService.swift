import CryptoKit
import Foundation
import UIKit
import WebKit

struct MailRuOAuthProfile {
    var subject: String
    var email: String?
    var firstName: String?
    var lastName: String?
    var name: String
    var pictureURL: URL?
}

enum MailRuOAuthError: LocalizedError {
    case notConfigured
    case missingAccessToken
    case invalidCallback
    case stateMismatch
    case profileFetchFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Mail.ru OAuth is not configured. Add MAILRU_OAUTH_CLIENT_ID to the KnotLink target build settings. Add MAILRU_OAUTH_PRIVATE_KEY if you want profile details."
        case .missingAccessToken:
            return "Mail.ru did not return an access token."
        case .invalidCallback:
            return "Mail.ru returned an invalid OAuth callback."
        case .stateMismatch:
            return "Mail.ru sign-in state check failed. Please try again."
        case .profileFetchFailed:
            return "Mail.ru profile fetch failed."
        }
    }
}

final class MailRuOAuthService: NSObject {
    private let authorizationEndpoint = URL(string: "https://connect.mail.ru/oauth/authorize")!
    private let restEndpoint = URL(string: "https://www.appsmail.ru/platform/api")!
    private var currentWebAuthController: MailRuOAuthViewController?

    func authenticate() async throws -> MailRuOAuthProfile {
        let config = try MailRuOAuthRuntimeConfig.load()
        let state = Self.makeState()
        let callbackURL = try await authorize(config: config, state: state)
        let token = try Self.token(from: callbackURL, expectedState: state)

        if let userID = token.userID, !config.privateKey.isEmpty {
            return try await fetchProfile(userID: userID, accessToken: token.accessToken, config: config)
        }

        let fallbackSubject = token.userID ?? token.accessToken.sha256Hex
        return MailRuOAuthProfile(
            subject: fallbackSubject,
            email: nil,
            firstName: nil,
            lastName: nil,
            name: "Mail.ru User",
            pictureURL: nil
        )
    }

    @MainActor
    private func authorize(config: MailRuOAuthRuntimeConfig, state: String) async throws -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "display", value: "mobile"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else { throw MailRuOAuthError.invalidCallback }

        return try await withCheckedThrowingContinuation { continuation in
            let controller = MailRuOAuthViewController(
                authURL: authURL,
                redirectURI: config.redirectURI
            ) { [weak self] result in
                self?.currentWebAuthController = nil
                continuation.resume(with: result)
            }

            guard let presenter = UIApplication.shared.topMostViewController else {
                continuation.resume(throwing: MailRuOAuthError.invalidCallback)
                return
            }

            currentWebAuthController = controller
            presenter.present(controller, animated: true)
        }
    }

    private func fetchProfile(
        userID: String,
        accessToken: String,
        config: MailRuOAuthRuntimeConfig
    ) async throws -> MailRuOAuthProfile {
        let params = [
            "app_id": config.clientID,
            "method": "users.getInfo",
            "secure": "0",
            "session_key": accessToken,
            "uids": userID
        ]
        var signedParams = params
        signedParams["sig"] = Self.signature(userID: userID, params: params, privateKey: config.privateKey)

        var components = URLComponents(url: restEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = signedParams
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else { throw MailRuOAuthError.profileFetchFailed }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MailRuOAuthError.profileFetchFailed
        }

        do {
            let users = try JSONDecoder().decode([MailRuUserInfoResponse].self, from: data)
            guard let user = users.first else { throw MailRuOAuthError.profileFetchFailed }
            let firstName = user.firstName?.nilIfBlank
            let lastName = user.lastName?.nilIfBlank
            let name = [firstName, lastName]
                .compactMap { $0 }
                .joined(separator: " ")
                .nilIfBlank ?? user.email ?? "Mail.ru User"
            return MailRuOAuthProfile(
                subject: user.uid.nilIfBlank ?? userID,
                email: user.email?.nilIfBlank,
                firstName: firstName,
                lastName: lastName,
                name: name,
                pictureURL: user.picBig.flatMap(URL.init(string:)) ?? user.pic.flatMap(URL.init(string:))
            )
        } catch {
            throw MailRuOAuthError.profileFetchFailed
        }
    }

    private static func token(from callbackURL: URL, expectedState: String) throws -> MailRuToken {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw MailRuOAuthError.invalidCallback
        }

        let items = callbackItems(from: components)
        if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            throw MailRuOAuthError.invalidCallback
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw MailRuOAuthError.stateMismatch
        }
        guard let accessToken = items.first(where: { $0.name == "access_token" })?.value, !accessToken.isEmpty else {
            throw MailRuOAuthError.missingAccessToken
        }

        let userID = items.first { item in
            ["x_mailru_vid", "uid", "user_id"].contains(item.name)
        }?.value

        return MailRuToken(accessToken: accessToken, userID: userID)
    }

    private static func callbackItems(from components: URLComponents) -> [URLQueryItem] {
        var items = components.queryItems ?? []
        if
            let fragment = components.fragment,
            let fragmentComponents = URLComponents(string: "knotlink://callback?\(fragment)")
        {
            items.append(contentsOf: fragmentComponents.queryItems ?? [])
        }
        return items
    }

    private static func signature(userID: String, params: [String: String], privateKey: String) -> String {
        let body = params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined()
        return "\(userID)\(body)\(privateKey)".md5Hex
    }

    private static func makeState(length: Int = 24) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }
}

private struct MailRuOAuthRuntimeConfig {
    var clientID: String
    var privateKey: String
    var redirectURI: URL

    var callbackScheme: String {
        redirectURI.scheme ?? "http"
    }

    static func load(bundle: Bundle = .main) throws -> MailRuOAuthRuntimeConfig {
        let clientID = bundle.oauthString("MailRuOAuthClientID")
        let privateKey = bundle.oauthString("MailRuOAuthPrivateKey")
        let redirectURIString = bundle.oauthString("MailRuOAuthRedirectURI")
        let redirectURI = URL(string: redirectURIString.isEmpty ? "http://connect.mail.ru/oauth/success.html" : redirectURIString)

        guard
            !clientID.isEmpty,
            !clientID.contains("REPLACE_WITH"),
            !clientID.contains("$("),
            redirectURI != nil
        else {
            throw MailRuOAuthError.notConfigured
        }

        return MailRuOAuthRuntimeConfig(
            clientID: clientID,
            privateKey: privateKey.contains("REPLACE_WITH") || privateKey.contains("$(") ? "" : privateKey,
            redirectURI: redirectURI!
        )
    }
}

private struct MailRuToken {
    var accessToken: String
    var userID: String?
}

private final class MailRuOAuthViewController: UIViewController, WKNavigationDelegate {
    private let authURL: URL
    private let redirectURI: URL
    private let completion: (Result<URL, Error>) -> Void
    private var hasCompleted = false
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        return webView
    }()

    init(authURL: URL, redirectURI: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        self.authURL = authURL
        self.redirectURI = redirectURI
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        installWebView()
        installCloseButton()
        webView.load(URLRequest(url: authURL))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
        if isRedirectCallback(url) {
            complete(.success(url))
            return .cancel
        }
        return .allow
    }

    private func installWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func installCloseButton() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .systemBackground.withAlphaComponent(0.92)
        button.layer.cornerRadius = 22
        button.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func cancel() {
        complete(.failure(MailRuOAuthError.invalidCallback))
    }

    private func complete(_ result: Result<URL, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        dismiss(animated: true) { [completion] in
            completion(result)
        }
    }

    private func isRedirectCallback(_ url: URL) -> Bool {
        guard
            url.scheme == redirectURI.scheme,
            url.host == redirectURI.host
        else {
            return false
        }
        return url.path == redirectURI.path
    }
}

private struct MailRuUserInfoResponse: Decodable {
    var uid: String
    var email: String?
    var firstName: String?
    var lastName: String?
    var pic: String?
    var picBig: String?

    enum CodingKeys: String, CodingKey {
        case uid
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case pic
        case picBig = "pic_big"
    }
}

private extension Bundle {
    func oauthString(_ key: String) -> String {
        (object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private extension UIApplication {
    var topMostViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController

        var topController = root
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        return topController
    }
}

private extension String {
    var md5Hex: String {
        Insecure.MD5.hash(data: Data(utf8)).map { String(format: "%02hhx", $0) }.joined()
    }

    var sha256Hex: String {
        SHA256.hash(data: Data(utf8)).map { String(format: "%02hhx", $0) }.joined()
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
