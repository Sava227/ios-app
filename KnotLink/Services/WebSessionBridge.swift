import Foundation

struct WebSessionBridge {
    var baseURL: URL

    init(baseURL: URL = URL(string: "http://localhost:5001")!) {
        self.baseURL = baseURL
    }

    func url(for path: String) -> URL? {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appending(path: cleanPath)
    }
}
