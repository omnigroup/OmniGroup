// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Combine
import QuickLookThumbnailing
import UIKit

internal protocol ServerAccount {
    var files: [File] { get }
    var accountName: String { get }
    var statusText: String? { get }
    var hasErrorStatus: Bool { get }
    var filesDidChangeBlock: (() -> Void)? { get set }
    func requestSync() -> Void
    func requestHelp() -> Void
}

internal enum SortOrder {
    case path, name, modificationDate, size
}

internal final class ServerAccountFileListEnvironment: ObservableObject {
    var serverAccount: ServerAccount
    @Published var accountName: String = ""
    @Published var files: [File] = [] {
        didSet {
            _hasPendingSort = false
        }
    }

    @Published var totalFileCount: Int = 0
    @Published var downloadedFileCount: Int = 0
    @Published var totalFileSize: Int64 = 0
    @Published var downloadedFileSize: Int64 = 0
    @Published var hasUnrequestedDownloadsAvailable = false
    @Published var statusText: String?
    @Published var hasErrorStatus: Bool = false
    @Published var sortOrder: SortOrder = .path {
        // Really, this should use a Combine debounce
        didSet {
            guard !_hasPendingSort else { return }
            let originalFiles = self.files
            self.files = [] // Give immediate feedback to the interface while scheduling our work
            _hasPendingSort = true
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.05) { [ weak self] in
                guard let self = self, self._hasPendingSort else { return }
                OUIWithoutAnimating {
                    self.files = originalFiles.sorted(by: self.currentSortBlock)
                }
            }
        }
    }

    var localizedAccountStatusItemsAndSizeFormat = "%@ items, %@"
    var localizedAccountStatusItemsAndSizeWithDownloadsFormat = "%@ items, %@ (%@ downloaded, %@)"
    var localizedSortOrderFolderAndName = "folder and name"
    var localizedSortOrderSize = "size"
    var localizedSortOrderModificationDate = "modification date"
    var localizedSortOrderName = "name"
    var localizedSortLabel = "Sort by:"

    fileprivate var _hasPendingSort = false
    var thumbnailImageProviderCache = ThumbnailImageProviderCache()
    var openFileBlock: ((File) -> Void)?
    var humanReadableStringForSizeBlock: ((Int64) -> String)?
    var humanReadableStringForDateBlock: ((Date) -> String)?

    init(serverAccount: ServerAccount) {
        self.serverAccount = serverAccount
        self.serverAccount.filesDidChangeBlock = { [weak self] in
            guard let self = self else { return }
            self.accountName = serverAccount.accountName
            self.updateFiles()
        }
        self.accountName = serverAccount.accountName
        updateFiles()
    }

    func downloadAllFiles() {
        files.forEach { file in
            file.requestDownload()
        }
    }

    func open(file: File) {
        guard file.isDownloaded else {
            file.requestDownload()
            return
        }

        guard let openFileBlock = openFileBlock else { return }
        openFileBlock(file)
    }

    var currentSortBlock: ((_ file1: File, _ file2: File) -> Bool) {
        switch sortOrder {
            case .path:
                return { (file1, file2) -> Bool in
                    return file1.fileURL.absoluteString < file2.fileURL.absoluteString
                }
            case .name:
                return { (file1, file2) -> Bool in
                    let name1 = file1.fileURL.lastPathComponent
                    let name2 = file2.fileURL.lastPathComponent
                    if name1 == name2 {
                        return file1.fileURL.absoluteString < file2.fileURL.absoluteString
                    }
                    return name1 < name2
                }
            case .modificationDate:
                return { (file1, file2) -> Bool in
                    guard let date1 = file1.modificationDate, let date2 = file2.modificationDate, date1 != date2 else {
                        return file1.fileURL.absoluteString < file2.fileURL.absoluteString
                    }
                    return date1 > date2
                }
            case .size:
                return { (file1, file2) -> Bool in
                    let size1 = file1.size
                    let size2 = file2.size
                    guard size1 != size2 else {
                        return file1.fileURL.absoluteString < file2.fileURL.absoluteString
                    }
                    return size1 > size2
                }
        }
    }

    fileprivate func updateFiles() {
        self.files = serverAccount.files.sorted(by: currentSortBlock)
        updateFileStats()
    }

    fileprivate func updateFileStats() {
        var totalFileCount = 0
        var downloadedFileCount = 0
        var totalFileSize: Int64 = 0
        var downloadedFileSize: Int64 = 0
        var hasUnrequestedDownloadsAvailable = false
        files.forEach { (file) in
            let fileSize = file.size
            totalFileCount += 1
            totalFileSize += fileSize
            if file.isDownloaded {
                downloadedFileCount += 1
                downloadedFileSize += fileSize
            } else if !hasUnrequestedDownloadsAvailable && !file.isDownloading {
                hasUnrequestedDownloadsAvailable = true
            }
        }
        self.totalFileCount = totalFileCount
        self.downloadedFileCount = downloadedFileCount
        self.totalFileSize = totalFileSize
        self.downloadedFileSize = downloadedFileSize
        self.hasUnrequestedDownloadsAvailable = hasUnrequestedDownloadsAvailable
        self.statusText = serverAccount.statusText
        self.hasErrorStatus = serverAccount.hasErrorStatus
    }

    func humanReadableString(for size: Int64?) -> String {
        guard let size = size else { return "" }
        if let humanReadableStringForSizeBlock = humanReadableStringForSizeBlock {
            return humanReadableStringForSizeBlock(size)
        }
        return "\(size) bytes"
    }

    func humanReadableString(for date: Date?) -> String {
        guard let date = date else { return "" }
        if let humanReadableStringForDateBlock = humanReadableStringForDateBlock {
            return humanReadableStringForDateBlock(date)
        }
        return fallbackDateFormatter.string(for: date) ?? ""
    }

    internal func sizeAndDate(for file: File) -> String {
        return "\(humanReadableString(for: file.size)) • \(humanReadableString(for: file.modificationDate))"
    }
}

fileprivate let fallbackDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

internal final class File: ObservableObject, Hashable {
    var baseURL: URL
    var fileURL: URL

    // var didChange = PassthroughSubject<Void, Never>()

    @Published public var isDownloading = false
    @Published public var isDownloaded = false
    @Published public var modificationDate: Date?
    @Published public var size: Int64 = 0

    public var requestDownloadBlock: ((File) -> Void)?

    init(baseURL: URL, fileURL: URL) {
        self.baseURL = baseURL
        self.fileURL = fileURL
    }

    var filename: String {
        return fileURL.lastPathComponent
    }

    var folder: String {
        let pathComponents = fileURL.deletingLastPathComponent().pathComponents
        let basePathComponents = baseURL.pathComponents
        let relativePathComponents = pathComponents.suffix(from: basePathComponents.count)
        let folder = relativePathComponents.joined(separator: "/")
        return folder
    }

    func requestDownload() {
        guard !isDownloaded && !isDownloading, let requestDownloadBlock = requestDownloadBlock else { return }
        isDownloading = true
        requestDownloadBlock(self)
    }

    static func == (lhs: File, rhs: File) -> Bool {
        return lhs.fileURL == rhs.fileURL && lhs.baseURL == rhs.baseURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fileURL)
        hasher.combine(baseURL)
    }
}

internal final class ThumbnailImageProviderCache: NSObject {
    public var cachedResults = [URL: DynamicImageProvider]()
    func thumbnailImage(for fileURL: URL) -> DynamicImageProvider {
        if let result = cachedResults[fileURL] {
            return result
        }
        let fileType = "" // ignored at the moment
        let result = ThumbnailImageProvider(fileURL: fileURL, fileType: fileType)
        cachedResults[fileURL] = result
        return result
    }
}

internal class DynamicImageProvider: ObservableObject {
    @Published public var dynamicImage: UIImage? = nil
}

#if DEBUG
internal final class TestImageProvider: DynamicImageProvider {
    override init() {
        super.init()
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAGAAAACACAYAAAD03Gy6AAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAYKADAAQAAAABAAAAgAAAAACiL7qrAAAAHGlET1QAAAACAAAAAAAAAEAAAAAoAAAAQAAAAEAAAAIzbcyKOwAAAf9JREFUeAHsmNFtwzAMRLNpVuhO/c4q3aFrOEBd6EOFI8gyBVI513ofhmGZYc53OlLSbVmWlUvHwQ3ydeQn7hFAXAEQAAG0JUBdgnEADsABLEOFLqAECclnGSomHwEQYO4GjANwAA5gFSR2AQIgwNxlCAfgABzAWZDQBZQgIflsxMTkIwACzN2AcQAOwAGsgsQuQAAEmLsM4QAcgAM4CxK6gBIkJJ+NmJh8BLiaAM/vr/Xn8bGun/fqld6lmKR8uo7i9/Koxkv8+Ts899Ae0CI/k5ZiMmBLfP7dWe5b/Pk7PPdQAawkZcDW+LPFZfwRdwTYKZct0SOIzzkQAAHqDbs1A9Xv8uyNuOMAHIAD/paFXktZlpXbZZwlXl1uyv/f4vfylX4fWoKONlYJPBux19PfUAEiZsRsORBAfB4UKkBvCeqd7Uf5y3od/VyW0F78tfhQASxN1dPELPmjSS/zefAPF6AEu/dcA2IZ28v37nELVmtMqAOsRFjBlXHW/KPjSlyeZwSYeSfcO3NGz2xr/l7crXgcgANed4at2WKdoaPjWhh734U6wLJM9CzjLPlHk+/BXxMnVICjjVICvz0LqgFqjR3lfwf5Hvy1bwsVoPYHjLVLLAJc6SzobLM9umR5S2iNn0s7YETTPnUTrimsHBvVlCO/6dIOQABxg/sPAvwCAAD//0TX0wkAAAHxSURBVO2aQW4DIQxFc9NcoXfqOlfpHXqNqdSprIqKsMExxp7CW0STKMYYf/+PIbkdx3Gu+jrf7+eMl2e+bp7OruZrRvLFp+c6AcDAEgBQyub3481dgsQnACgB+Pr8OD1BEF/iEwCUAHgmapavpfeAWUnz9OsKQI/yoxTu+bd2PaNxjQDiCoBGb8XGGrDG/wgI1rhGxrkCoF28NWCtf6udNa6RcQBQnQNGEmkdCwAAoL+LskqLdpy1ikfGwQAYAAPMbWFLPU2bSBv6XHCuEtQ7KEnyR+5Sev61Wt/ajcbVFuIrn10BeGVibH+ZAADJF3uuAPQkoqV6z76Vilmf27gi2ekKgCyklySxKQvU2Pf8eX1fx1Xii3i6AqBNRlmY1j7KrsQV+QSAnQ9iUZWtnSey8stcMAAGzPnzlLbqa7tSlZFPGLASAzRtZd3uaezrCp35vo7r3zKgd7CSRYpNWWDPfmbCa99tXCW+iKerBEUEvNocALDSXdBq1RmxHhgAA55/IYqouivNAQNgAAz468uvRM1dYkGCkCAkCAlKZAESlJh82ecAAADYA9gDElmABCUmnz0gOfkAAAB7b8AwAAbAALqgZBYAAADsLUMwAAbAAO6CElmABCUmn4NYcvIBAAD23oBhAAyAAXRBySwAgGQAfgCYOUuc4EVCuAAAAABJRU5ErkJggg==")!
        self.dynamicImage = nil
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2.0) {
            self.dynamicImage = UIImage(data: pngData)!
        }
    }
}
#endif

internal final class ThumbnailImageProvider: DynamicImageProvider {

    let fileURL: URL
    let fileType: String

    // var didChange = PassthroughSubject<Void, Never>()

    private var thumbnailRequest: QLThumbnailGenerator.Request?

    internal init(fileURL: URL, fileType: String) {
        self.fileURL = fileURL
        self.fileType = fileType

        let request = QLThumbnailGenerator.Request(fileAt: fileURL, size: CGSize(width: 100, height: 100), scale: 1.0, representationTypes: [.icon, .thumbnail])
        request.iconMode = true
        self.thumbnailRequest = request

        super.init()

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] (representation, error) in
            guard let self = self else { return }
            if let error = error {
                print("error making thumbnail for \(fileURL): \(error)")
            } else if let representation = representation {
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    self.dynamicImage = representation.uiImage
                }
            }
            self.thumbnailRequest = nil
        }
    }
}

#if DEBUG

internal class PreviewTestAccount: ServerAccount {
    var filesDidChangeBlock: (() -> Void)?
    internal var accountName = "Preview Test Account"
    var statusText: String? = nil
    var hasErrorStatus: Bool = false

    internal var files: [File] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: resourceKeys, options: [.skipsPackageDescendants]) else { return [] }
        let files = enumerator.compactMap { (fileURL) -> File? in
            guard let fileURL = fileURL as? URL else { return nil }
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
            let file = File(baseURL: baseURL, fileURL: fileURL)
            file.modificationDate = resourceValues.contentModificationDate
            file.size = Int64(resourceValues.fileSize ?? 0)
            file.requestDownloadBlock = { [weak self] (file) in
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2.0) {
                    file.isDownloaded = true
                    file.isDownloading = false
                    guard let filesDidChangeBlock = self?.filesDidChangeBlock else { return }
                    filesDidChangeBlock()
                }
            }
            return file
        }
        return files
    }

    func requestSync() {
        print("Sync requested")
    }

    func requestHelp() {
        print("Help requested")
    }

    var baseURL: URL {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        let folderURL = homeURL.appendingPathComponent("Documents")
        do {
            try Data().write(to: folderURL.appendingPathComponent("test.ooutline"))
            try String(describing: self).data(using: .utf8)?.write(to: folderURL.appendingPathComponent("test.txt"))
        } catch {
        }
        return folderURL
    }
}

extension ServerAccountFileListEnvironment {
    static var previewUserData: ServerAccountFileListEnvironment {
        let previewAccount = PreviewTestAccount()
        previewAccount.statusText = "Last Sync: Today, 10:17 AM"
        return ServerAccountFileListEnvironment(serverAccount: previewAccount)
    }
}

#endif

