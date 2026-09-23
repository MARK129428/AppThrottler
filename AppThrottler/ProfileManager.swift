import Foundation

@MainActor
class ProfileManager: ObservableObject {
    @Published var profiles: [SavedProfile] = []

    private let profilesDir: URL

    struct SavedProfile: Identifiable, Codable {
        let id: String
        var name: String
        var config: ThrottleConfig
        var createdAt: Date

        init(name: String, config: ThrottleConfig) {
            self.id = UUID().uuidString
            self.name = name
            self.config = config
            self.createdAt = Date()
        }
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        profilesDir = appSupport.appendingPathComponent("AppThrottler/Profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        loadAll()
    }

    func save(name: String, config: ThrottleConfig) {
        let profile = SavedProfile(name: name, config: config)
        // Generate simpler id for filename
        let filename = "\(name.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).json"
        let url = profilesDir.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        if let data = try? encoder.encode(profile) {
            try? data.write(to: url)
        }
        loadAll()
    }

    func delete(profile: SavedProfile) {
        let files = (try? FileManager.default.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let decoded = try? JSONDecoder().decode(SavedProfile.self, from: data),
               decoded.id == profile.id {
                try? FileManager.default.removeItem(at: file)
                break
            }
        }
        loadAll()
    }

    func loadAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        profiles = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(SavedProfile.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // Export all profiles as a single JSON file
    func export(to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: url)
        }
    }

    // Import profiles from a JSON file
    func importFrom(url: URL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let imported = try? decoder.decode([SavedProfile].self, from: data) else { return }
        for profile in imported {
            save(name: profile.name, config: profile.config)
        }
    }
}
