import Foundation
import SwiftData

/// Pre-downloads course GPS data for offline use on the course
@Observable
final class OfflineCacheService {
    var cachedCourses: [String] = []  // course IDs
    var isDownloading = false
    var downloadProgress: Double = 0
    var error: String?

    private let courseSearch = CourseSearchService()
    private let cacheDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDir = docs.appendingPathComponent("CourseCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        loadCachedList()
    }

    /// Download full course data for offline use
    func downloadCourse(id: String) async {
        guard courseSearch.isConfigured else {
            error = "Course API not configured"
            return
        }

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
            error = nil
        }

        do {
            let details = try await courseSearch.fetchCourseDetails(id: id)

            await MainActor.run { downloadProgress = 0.5 }

            // Serialize to JSON and save
            let cacheData = CachedCourse(
                id: id,
                name: details.name,
                city: details.city,
                state: details.state,
                location: details.location,
                tees: details.tees,
                downloadedAt: Date()
            )

            let data = try JSONEncoder().encode(cacheData)
            let fileURL = cacheDir.appendingPathComponent("\(id).json")
            try data.write(to: fileURL)

            await MainActor.run {
                downloadProgress = 1.0
                isDownloading = false
                if !cachedCourses.contains(id) {
                    cachedCourses.append(id)
                }
                saveCachedList()
            }
        } catch let downloadError {
            await MainActor.run {
                self.error = "Download failed: \(downloadError.localizedDescription)"
                isDownloading = false
            }
        }
    }

    /// Load cached course data (works offline)
    func loadCachedCourse(id: String) -> CachedCourse? {
        let fileURL = cacheDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedCourse.self, from: data)
    }

    /// Delete cached course
    func deleteCachedCourse(id: String) {
        let fileURL = cacheDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: fileURL)
        cachedCourses.removeAll { $0 == id }
        saveCachedList()
    }

    /// List all cached courses with their metadata
    func listCachedCourses() -> [CachedCourse] {
        cachedCourses.compactMap { loadCachedCourse(id: $0) }
    }

    private func loadCachedList() {
        let listURL = cacheDir.appendingPathComponent("cached_ids.json")
        if let data = try? Data(contentsOf: listURL),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            cachedCourses = ids
        }
    }

    private func saveCachedList() {
        let listURL = cacheDir.appendingPathComponent("cached_ids.json")
        if let data = try? JSONEncoder().encode(cachedCourses) {
            try? data.write(to: listURL)
        }
    }
}

struct CachedCourse: Codable {
    let id: String
    let name: String
    let city: String?
    let state: String?
    let location: GpsPoint?
    let tees: [CourseTee]
    let downloadedAt: Date
}
