import Foundation

/// Checks the GitHub Releases API for a newer version. Mirrors the Windows `UpdateService`.
enum Updater {
    static let currentVersion = AppInfo.version
    private static let url = URL(string: "https://api.github.com/repos/cassiarota/win-paste/releases/latest")!

    struct Update { let version: String; let url: String }

    static func check(completion: @escaping (Update?) -> Void) {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("FineClipboard", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let html = (json["html_url"] as? String) ?? "https://github.com/cassiarota/win-paste/releases"
            let result = isNewer(latest, than: currentVersion) ? Update(version: latest, url: html) : nil
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
