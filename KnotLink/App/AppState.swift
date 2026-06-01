import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case chats
    case contacts
    case settings
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: return "Chats"
        case .contacts: return "Contacts"
        case .settings: return "Settings"
        case .profile: return "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .contacts: return "person.2.fill"
        case .settings: return "gearshape.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

enum AuthProvider: String, CaseIterable, Identifiable {
    case google
    case mailRu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: return "Continue with Google"
        case .mailRu: return "Continue with Mail.ru"
        }
    }

    var symbol: String {
        switch self {
        case .google: return "g.circle.fill"
        case .mailRu: return "envelope.circle.fill"
        }
    }
}
