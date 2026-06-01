# KnotLink iOS/iPadOS

Native SwiftUI port of the KnotLink Flask messenger.

## Included flows

- Google OAuth 2.0 sign in using `ASWebAuthenticationSession`, authorization-code flow, and PKCE.
- Manual email/password login and registration screens, ready for backend email verification wiring.
- Chat list with search, all/group/bot filters, message previews, and iPad split-view support.
- Direct/group conversation UI with message sending, chat search, shared-link discovery, email bridge status, clear history, and delete chat actions.
- Contacts, incoming invitations, outgoing invitations, invite lookup, and start conversation flow.
- Profile editing with the same username/display-name validation constraints as the Flask app.
- Settings panels for profile, notifications, languages/translation, devices, session logout, and email bridge status.

## Liquid Glass

The UI uses SwiftUI standard controls plus a small compatibility layer in `Design/LiquidGlass.swift`.
It currently uses material-backed translucent surfaces instead of the native iOS 26 glass runtime APIs, because those APIs caused launch crashes on the main tab bar path in current simulator/device builds.

## OAuth setup

Google:

1. In Google Cloud Console, create an OAuth client for iOS.
2. Use this app bundle ID: `com.knotlink.app`.
3. Add this redirect URI to the Google OAuth client: `com.knotlink.app:/oauth2redirect`.
4. In Xcode, open the KnotLink target build settings and set `GOOGLE_OAUTH_CLIENT_ID` to the iOS OAuth client ID, for example `1234567890-abc.apps.googleusercontent.com`.
5. Run the app and tap `Continue with Google`.

The client secret is intentionally not used in the iOS app. Installed apps cannot keep secrets, so the flow uses PKCE instead.

Mail.ru:

1. Register an external/standalone app in Mail.ru Platform.
2. The iOS app uses Mail.ru's standalone OAuth success URL: `http://connect.mail.ru/oauth/success.html`.
3. In Xcode, set `MAILRU_OAUTH_CLIENT_ID` to the Mail.ru app id.
4. Optional: set `MAILRU_OAUTH_PRIVATE_KEY` if you want the app to call `users.getInfo` and fill name/email/avatar details. Without it, sign-in still completes with a fallback Mail.ru user profile from the OAuth token.
5. Run the app and tap `Continue with Mail.ru`.

## Backend integration note

The current Flask app exposes server-rendered routes and form posts, not JSON endpoints. `Services/WebSessionBridge.swift` centralizes the existing server base URL (`http://localhost:5001`) so OAuth/web session handoff can be wired in one place once native API endpoints or callback URL schemes are added.

Manual email login and registration currently validate locally and persist accounts, invitations, conversations, messages, reactions, and message attachments in shared on-device storage. This lets multiple locally registered accounts discover each other and chat on the same simulator/device. Replace the local shared store in `Services/KnotLinkStore.swift` with API calls when server-backed account lookup, contact invitations, and message sync endpoints are ready.
