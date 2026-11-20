import Foundation

enum AppPaths {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("VoiceNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var audioDirectory: URL {
        let dir = applicationSupport.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var asrModelsDirectory: URL {
        let dir = applicationSupport.appendingPathComponent("Models/ASR", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var llmModelsDirectory: URL {
        let dir = applicationSupport.appendingPathComponent("Models/LLM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func audioURL(relativePath: String) -> URL {
        audioDirectory.appendingPathComponent(relativePath)
    }
}
