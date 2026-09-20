import Foundation
import DakaCore

/// 升级检测结果（跨线程传递后由主线程消费）。
struct UpdateCheckResult: Equatable {
    let currentVersion: AppVersion
    let latestVersion: AppVersion
    let isUpdateAvailable: Bool
    let latestTag: String
    /// GitHub 该 Release 页面；无则回退到 releases 列表页。
    let htmlURL: URL?
}

enum UpdateCheckError: Error {
    case noRelease        // 仓库尚无已发布 Release（API 404）
    case invalidResponse  // 响应异常 / 状态码非 2xx
    case parse            // 响应无法解析为版本
    case network(Error)   // 网络层错误（多为离线 / 被拦截）
}

/// 检查 GitHub Releases 是否有新版本，并指向下载页。
/// 仅查询公开 API 做版本号比较，不上传任何用户数据。
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// 引导下载的总入口（用户要求地址）。
    static let releasesURL = URL(string: "https://github.com/iamxz/PunchClock/releases")!
    private static let apiURL = URL(string: "https://api.github.com/repos/iamxz/PunchClock/releases/latest")!

    /// 从 Info.plist 读取当前应用版本（打包后的 .app 才有，dev 运行可能为空）。
    var currentVersion: AppVersion? {
        guard let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let parsed = AppVersion.parse(raw) else { return nil }
        return parsed
    }

    /// 异步检查最新 Release。completion 在后台线程回调，调用方需切回主线程。
    func check(_ completion: @escaping (Result<UpdateCheckResult, UpdateCheckError>) -> Void) {
        var request = URLRequest(url: Self.apiURL)
        request.setValue("Daka/\(currentVersion?.description ?? "unknown")", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            if http.statusCode == 404 {
                completion(.failure(.noRelease))
                return
            }
            guard (200...299).contains(http.statusCode), let data else {
                completion(.failure(.invalidResponse))
                return
            }

            struct LatestRelease: Decodable {
                let tag_name: String
                let html_url: String?
            }
            guard let json = try? JSONDecoder().decode(LatestRelease.self, from: data),
                  let latest = AppVersion.parse(json.tag_name) else {
                completion(.failure(.parse))
                return
            }

            let current = self.currentVersion ?? AppVersion(major: 0, minor: 0, patch: 0)
            let result = UpdateCheckResult(
                currentVersion: current,
                latestVersion: latest,
                isUpdateAvailable: latest > current,
                latestTag: json.tag_name,
                htmlURL: json.html_url.flatMap { URL(string: $0) } ?? Self.releasesURL
            )
            completion(.success(result))
        }
        task.resume()
    }
}
