import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

struct GoogleOAuthProfile {
    var subject: String
    var email: String?
    var givenName: String?
    var familyName: String?
    var name: String
    var pictureURL: URL?
}

enum GoogleOAuthError: LocalizedError {
    case notConfigured
    case missingAuthorizationCode
    case stateMismatch
    case invalidCallback
    case tokenExchangeFailed
    case profileFetchFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google OAuth is not configured. Add your iOS OAuth client ID to the KnotLink target build setting GOOGLE_OAUTH_CLIENT_ID."
        case .missingAuthorizationCode:
            return "Google did not return an authorization code."
        case .stateMismatch:
            return "Google sign-in state check failed. Please try again."
        case .invalidCallback:
            return "Google returned an invalid OAuth callback."
        case .tokenExchangeFailed:
            return "Google token exchange failed."
        case .profileFetchFailed:
            return "Google profile fetch failed."
        }
    }
}

final class GoogleOAuthService: NSObject {
    private let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
    private var currentSession: ASWebAuthenticationSession?

    func authenticate() async throws -> GoogleOAuthProfile {
        let config = try GoogleOAuthRuntimeConfig.load()
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.makeCodeVerifier(length: 24)
        let callbackURL = try await authorize(config: config, codeChallenge: challenge, state: state)
        let code = try Self.authorizationCode(from: callbackURL, expectedState: state)
        let token = try await exchangeCode(code, verifier: verifier, config: config)
        return try await fetchProfile(accessToken: token.accessToken)
    }

    private func authorize(
        config: GoogleOAuthRuntimeConfig,
        codeChallenge: String,
        state: String
    ) async throws -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]

        guard let authURL = components.url else { throw GoogleOAuthError.invalidCallback }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: config.redirectScheme
            ) { [weak self] callbackURL, error in
                self?.currentSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: GoogleOAuthError.invalidCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            if !session.start() {
                currentSession = nil
                continuation.resume(throwing: GoogleOAuthError.invalidCallback)
            }
        }
    }

    private func exchangeCode(
        _ code: String,
        verifier: String,
        config: GoogleOAuthRuntimeConfig
    ) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI.absoluteString,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        request.httpBody = Self.formURLEncoded(body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GoogleOAuthError.tokenExchangeFailed
        }

        do {
            return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        } catch {
            throw GoogleOAuthError.tokenExchangeFailed
        }
    }

    private func fetchProfile(accessToken: String) async throws -> GoogleOAuthProfile {
        var request = URLRequest(url: userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GoogleOAuthError.profileFetchFailed
        }

        do {
            let response = try JSONDecoder().decode(GoogleUserInfoResponse.self, from: data)
            return GoogleOAuthProfile(
                subject: response.sub,
                email: response.email,
                givenName: response.givenName,
                familyName: response.familyName,
                name: response.name.flatMap(\.nilIfBlank) ?? response.email ?? "Google User",
                pictureURL: response.picture.flatMap(URL.init(string:))
            )
        } catch {
            throw GoogleOAuthError.profileFetchFailed
        }
    }

    private static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw GoogleOAuthError.invalidCallback
        }

        let items = Self.callbackItems(from: components)
        if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            throw GoogleOAuthError.invalidCallback
        }

        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw GoogleOAuthError.stateMismatch
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw GoogleOAuthError.missingAuthorizationCode
        }

        return code
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

    private static func makeCodeVerifier(length: Int = 64) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func formURLEncoded(_ values: [String: String]) -> String {
        values
            .map { key, value in
                "\(key.urlFormEscaped)=\(value.urlFormEscaped)"
            }
            .sorted()
            .joined(separator: "&")
    }
}

extension GoogleOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private struct GoogleOAuthRuntimeConfig {
    var clientID: String
    var redirectScheme: String
    var redirectPath: String

    var redirectURI: URL {
        var components = URLComponents()
        components.scheme = redirectScheme
        components.path = redirectPath
        return components.url!
    }

    static func load(bundle: Bundle = .main) throws -> GoogleOAuthRuntimeConfig {
        let clientID = bundle.oauthString("GoogleOAuthClientID")
        let redirectScheme = bundle.oauthString("GoogleOAuthRedirectScheme")
        let redirectPath = bundle.oauthString("GoogleOAuthRedirectPath")

        guard
            !clientID.isEmpty,
            !clientID.contains("REPLACE_WITH"),
            !clientID.contains("$("),
            !redirectScheme.isEmpty
        else {
            throw GoogleOAuthError.notConfigured
        }

        return GoogleOAuthRuntimeConfig(
            clientID: clientID,
            redirectScheme: redirectScheme,
            redirectPath: redirectPath.isEmpty ? "/oauth2redirect" : redirectPath
        )
    }
}

private struct GoogleTokenResponse: Decodable {
    var accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct GoogleUserInfoResponse: Decodable {
    var sub: String
    var email: String?
    var name: String?
    var givenName: String?
    var familyName: String?
    var picture: String?

    enum CodingKeys: String, CodingKey {
        case sub
        case email
        case name
        case givenName = "given_name"
        case familyName = "family_name"
        case picture
    }
}

private extension Bundle {
    func oauthString(_ key: String) -> String {
        (object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlFormEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?")
        return set
    }()
}
