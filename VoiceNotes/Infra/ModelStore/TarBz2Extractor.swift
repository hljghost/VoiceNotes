import Foundation

/// Thin Swift wrapper around `voicenotes_extract_tar_bz2` (libbz2).
enum TarBz2Extractor {
    static func extract(
        archive: URL,
        to destinationDirectory: URL,
        wantedFileNames: [String]
    ) throws {
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        var cStrings: [UnsafeMutablePointer<CChar>] = wantedFileNames.map { strdup($0)! }
        defer {
            for ptr in cStrings {
                free(ptr)
            }
        }

        let count = Int32(wantedFileNames.count)
        let result = withUnsafeTemporaryAllocation(
            of: UnsafePointer<CChar>?.self,
            capacity: wantedFileNames.count
        ) { ptrs -> Int32 in
            for index in wantedFileNames.indices {
                ptrs[index] = UnsafePointer(cStrings[index])
            }
            return archive.path.withCString { archivePath in
                destinationDirectory.path.withCString { destPath in
                    voicenotes_extract_tar_bz2(
                        archivePath,
                        destPath,
                        ptrs.baseAddress,
                        count
                    )
                }
            }
        }

        guard result == 0 else {
            throw ModelStoreError.checksumFailed(
                "归档解压失败（代码 \(result)）。请重试下载；仍失败请用 scripts/download-sensevoice.sh 侧载。"
            )
        }
    }
}
