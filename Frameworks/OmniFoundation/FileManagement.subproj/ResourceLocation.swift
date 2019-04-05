// Copyright 2016-2019 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

@objc(OFResourceLocationDelegate) public protocol ResourceLocationDelegate {
    func resourceLocationDidUpdateResourceURLs(_ location: ResourceLocation)
    func resourceLocationDidMove(_ location: ResourceLocation)
}

// A KVO observable object for the URLs for a given type in a location.
@objc(OFResourceLocationContents) public class ResourceLocationContents : NSObject {
    @objc dynamic public var fileURLs = Set<URL>()
}

#if os(iOS)
private let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
private let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
#else
private let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
private let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#endif

@objc(OFResourceLocation) public class ResourceLocation : NSObject, NSFilePresenter {

    @objc /**REVIEW**/ static let WillStartScanning = Notification.Name("OFResourceLocationWillStartScanning")
    @objc static let DidFinishScanning = Notification.Name("OFResourceLocationDidFinishScanning")
    
    // folderURL can possibly be read on the background queue by presentedItemURL() and our scanning, so we have a lock for it.
    private let lock: NSLock
    private var _bookmark: Data? // nil for folders inside the app container
    private var _folderURL: URL

    @objc public var folderURL: URL {
        return lock.protect {
            return _folderURL
        }
    }
    @objc public var bookmark: Data? {
        return lock.protect {
            return _bookmark
        }
    }

    // resourceTypes is accessed on the background scanning queue too, but it is immutable (through the `contents` elements are not and must be mutated on the main queue).
    private struct ResourceType {
        let predicate: ResourceTypePredicate
        let contents: ResourceLocationContents
    }
    private let resourceTypes: [String:ResourceType]

    // The rest of the state should only be accessed on the main queue
    private var rescanForPresentedItemDidChangeRunning: Bool = false
    private var presentedItemDidChangeCalledWhileRescanning: Bool = false

    private weak var delegate: ResourceLocationDelegate?
    private var invalidated: Bool = false

    // A shared queue for file presenter notifications -- maybe not a good idea since move operations block?
    private static let FilePresenterQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.omnigroup.OmniUIResourceBrowser.ResourceLocation presenter queue"
        return queue
    }()

    // A shared queue for doing filesystem scans. If there are multiple location instances on different devices, it would be good to have multiple queues (mostly during the initial scan).
    private static let FileScanQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.omnigroup.OmniUIResourceBrowser.ResourceLocation file scan queue"
        return queue
    }()

    private init(folderURL: URL, bookmark: Data?, resourceTypes: [String:ResourceTypePredicate], delegate: ResourceLocationDelegate, synchronousInitialScan: Bool) {
        assert(resourceTypes.isEmpty == false)

        self.lock = NSLock()
        self._bookmark = bookmark
        self._folderURL = folderURL
        self.delegate = delegate

        self.resourceTypes = resourceTypes.mapValues({ predicate -> ResourceType in
            return ResourceType(predicate: predicate, contents: ResourceLocationContents())
        })

        super.init()

        NSFileCoordinator.addFilePresenter(self)

        if synchronousInitialScan {
            let scannedURLs = peformScan(folderURL: folderURL, synchronousInitialScan: true)
            finishScan(scannedFolderURL: folderURL, scannedURLs: scannedURLs)
        } else {
            handleScanRequest()
        }
    }

    @objc public convenience init(bookmark: Data, resourceTypes: [String:ResourceTypePredicate], delegate: ResourceLocationDelegate, synchronousInitialScan: Bool = false) throws {
        var isStale = false

        let url = try URL(resolvingBookmarkData: bookmark, options: bookmarkResolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale)

        // Have to do this before possibly regenerating the data when `isStale` is set.
        if !url.startAccessingSecurityScopedResource() {
            NSLog("Error: Unable to access security scoped URL at %@", url as NSURL)
            throw CocoaError(.userCancelled)
        }

        var updatedBookmark: Data?
        if isStale {
            if let data = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
                updatedBookmark = data
            } else {
                assertionFailure("Cannot refresh bookmark?")
            }
        }

        self.init(folderURL: url, bookmark: updatedBookmark ?? bookmark, resourceTypes: resourceTypes, delegate: delegate, synchronousInitialScan: synchronousInitialScan)
    }

    // For resource locations that are inside the app container and don't need security scoped bookmarks.
    @objc public convenience init(builtInFolderURL folderURL: URL, resourceTypes: [String:ResourceTypePredicate], delegate: ResourceLocationDelegate, synchronousInitialScan: Bool = false) throws {
        self.init(folderURL: folderURL, bookmark: nil, resourceTypes: resourceTypes, delegate: delegate, synchronousInitialScan: synchronousInitialScan)
    }

    @objc public convenience init(folderURL: URL, resourceTypes: [String:ResourceTypePredicate], delegate: ResourceLocationDelegate, synchronousInitialScan: Bool = false) throws {
        if !folderURL.startAccessingSecurityScopedResource() {
            NSLog("Error: Unable to access security scoped URL at %@", folderURL as NSURL)
            throw CocoaError(.userCancelled)
        }

        let bookmark = try folderURL.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)

        self.init(folderURL: folderURL, bookmark: bookmark, resourceTypes: resourceTypes, delegate: delegate, synchronousInitialScan: synchronousInitialScan)
    }

    #if DEBUG
    deinit {
        assert(invalidated == true)
    }
    #endif
    
    @objc public func updateNowThatObservedLocationExists() {
        assert(FileManager.default.fileExists(atPath: _folderURL.path), "Adding self as a presenter for a URL that doesn't exist yet. Most likely will result in not receiving expected file presenter messages.")
        NSFileCoordinator.removeFilePresenter(self)
        NSFileCoordinator.addFilePresenter(self)
    }

    // NSFileCoordinator retains us, so we need an invalidate method.
    @objc public func invalidate() {
        assert(OperationQueue.current == OperationQueue.main)

        if invalidated {
            return
        }
        invalidated = true
        NSFileCoordinator.removeFilePresenter(self)
        delegate = nil

        lock.protect {
            if _bookmark == nil {
                // This is a folder inside the app container
            } else {
                _folderURL.stopAccessingSecurityScopedResource()
            }
        }
    }

    public func resourceContents(type: String) -> ResourceLocationContents? {
        return resourceTypes[type]?.contents
    }

    // Returns true if the argument URL is the same as the folderURL or somewhere under it. This does not do a membership test on resourceURLs.
    public func containsURL(_ url: URL) -> Bool {
        return lock.protect {
            return OFURLEqualsURL(_folderURL, url) || OFURLContainsURL(_folderURL, url)
        }
    }

    // MARK:- NSFilePresenter

    public var presentedItemURL: URL? {
        return lock.protect {
            return _folderURL
        }
    }

    public var presentedItemOperationQueue: OperationQueue {
        return ResourceLocation.FilePresenterQueue
    }

    public func presentedItemDidChange() {
        self.requestScan()
    }

    public func presentedItemDidMove(to newURL: URL) {
        assert(OperationQueue.current == ResourceLocation.FilePresenterQueue)

        assert(_bookmark != nil, "Handle moving a built-in resource folder?")

        // We don't need to startAccessingSecurityScopedResource() on the new URL since this is a move and this is the same file for that purpose (in fact, calling 'start' will return false).
        guard let bookmark = try? newURL.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            assertionFailure("Resource folder moved from \(_folderURL) to \(newURL), but can't archive a bookmark")
            return
        }

        OperationQueue.main.addOperation { [weak self] in
            self?.update(folderURL: newURL, bookmark: bookmark)
        }
    }

    // In the case that our URL doesn't yet exist, we'll get this when other code is about to write into it. We won't get any sub-item notification in that case (we could maybe get rid of the sub-item methods below, but file presenter notifications are not terribly well defined).
    // For example, on first launch of an app that is populating application suppport resource folders inside its container.
    public func relinquishPresentedItem(toWriter writer: @escaping ((() -> Void)?) -> Void) {
        writer {
            self.requestScan()
        }
    }

    public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        assert(OperationQueue.current == ResourceLocation.FilePresenterQueue)

        assertionFailure("Finish")
    }
    

    public func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        self.requestScan()
    }

    public func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Swift.Void) {
        completionHandler(nil)
        self.requestScan()
    }

    public func presentedSubitemDidAppear(at url: URL) {
        self.requestScan()
    }

    public func presentedSubitemDidChange(at url: URL) {
        self.requestScan()
    }

    // MARK:- Private

    private func requestScan() {
        OperationQueue.main.addOperation { [weak self] in
            self?.handleScanRequest()
        }
    }

    private func handleScanRequest() {
        assert(OperationQueue.current == OperationQueue.main)

        // We can get called a ton when moving multiple files in or out of a resource location's folder. Don't start another scan until our first has finished.
        if rescanForPresentedItemDidChangeRunning {
            // Note that there was a rescan request while the first was running. We don't want to queue up an arbitrary number of rescans, but if some operations happened while the first scan was running, we could miss them. So, we need to remember and do one more scan.
            presentedItemDidChangeCalledWhileRescanning = true;
            return;
        }

        rescanForPresentedItemDidChangeRunning = true;

        startScan {
            assert(OperationQueue.current == OperationQueue.main)

            self.rescanForPresentedItemDidChangeRunning = false;

            // If there were more scans requested while the first was running, do *one* more now to catch any remaining changes (no matter how many requests there were).
            if self.presentedItemDidChangeCalledWhileRescanning {
                self.presentedItemDidChangeCalledWhileRescanning = false
                self.requestScan()
            }
        }
    }

    private func startScan(_ completionHandler: @escaping () -> Void) {
        assert(OperationQueue.current == OperationQueue.main)

        // In case we are moved while scanning...
        let folderURL = lock.protect {
            return self._folderURL
        }

        NotificationCenter.default.post(name: ResourceLocation.WillStartScanning, object: self)

        ResourceLocation.FileScanQueue.addOperation {
            // TODO: Add cancellation so that if the user adds a large folder they can cancel while the scan is going on (by removing the link to said folder).

            let scannedURLs = self.peformScan(folderURL: folderURL)

            OperationQueue.main.addOperation {
                self.finishScan(scannedFolderURL: folderURL, scannedURLs: scannedURLs)
                completionHandler()
            }
        }
    }

    private func finishScan(scannedFolderURL: URL, scannedURLs: [String:ScannedURLs]) {
        assert(OperationQueue.current == OperationQueue.main)

        var didChange = false
        scannedURLs.forEach { pair in
            guard let type = resourceTypes[pair.key] else {
                assertionFailure("Should have a resource type entry")
                return
            }
            if type.contents.fileURLs != pair.value.urls {
                type.contents.fileURLs = pair.value.urls
                didChange = true
            }
        }
        if didChange {
            delegate?.resourceLocationDidUpdateResourceURLs(self)
        }
        NotificationCenter.default.post(name: ResourceLocation.DidFinishScanning, object: self)
    }

    private class ScannedURLs {
        var urls: Set<URL>

        init() {
            urls = []
        }
    }

    private func peformScan(folderURL: URL, synchronousInitialScan: Bool = false) -> [String:ScannedURLs] {
        assert(synchronousInitialScan || OperationQueue.current == ResourceLocation.FileScanQueue)

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]

        // Having a non-nil error handler crashes in Xcode 8.0 and 8.1b1 (at least if the folder doesn't exist) <https://bugs.swift.org/browse/SR-2872>
        let searchOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants ]
        guard let topLevelEnumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: Array(keys), options: searchOptions, errorHandler: nil) else {
            return [:]
        }

        let scannedURLs = resourceTypes.mapValues { _ in return ScannedURLs() }

        // DirectoryEnumerator is a NSEnumerator, which isn't generic and can't declare that it yields NSURLs.
        for item in topLevelEnumerator {
            let fileURL = (item as! NSURL) as URL
            guard let values = try? fileURL.resourceValues(forKeys: keys) else {
                continue
            }

            // Using this instead of URLResourceKey.typeIdentifierKey since that doesn't consult exported types in our unit test bundles.
            var fileTypeError: NSError?
            guard let fileTypeIdentifier = OFUTIForFileURLPreferringNative(fileURL, &fileTypeError) else {
                //print("  unable to determine file type identifier for \(fileURL): \(fileTypeError)")
                continue
            }

            // special case because bbedit/textedit declare type tag specifications of vss and vs for com.barebones.bbedit.vectorscript-source. Thus, UTTypeCopyPreferredTagWithClass sometimes returns vs extension which does not have a filter
            let fileType: UTI
            if fileTypeIdentifier == "com.barebones.bbedit.vectorscript-source" {
                fileType = UTI("com.omnigroup.foreign-types.ms-visio.stencil")
            } else {
                fileType = UTI(fileTypeIdentifier)
            }

            if let resourceType = resourceTypes.first(where: { pair -> Bool in
                return pair.value.predicate.matchesFileType(fileType.rawFileType)
            }) {
                scannedURLs[resourceType.0]!.urls.insert(fileURL)

                // Is this a resource that is a directory too (*hopefully* would be registered as a bundle too, but not always).
                if (values.isDirectory ?? false) {
                    topLevelEnumerator.skipDescendants()
                }
                continue
            }

            if values.isPackage ?? false {
                // Some intermediate package -- ignore it.
                topLevelEnumerator.skipDescendants()
                continue
            }

        }

        return scannedURLs
    }

    private func update(folderURL: URL, bookmark: Data) {
        assert(OperationQueue.current == OperationQueue.main)

        guard !invalidated else {
            return
        }
        
        lock.protect {
            self._folderURL = folderURL
            self._bookmark = bookmark
        }

        delegate?.resourceLocationDidMove(self)
    }

}

// Allow being a pointer-based dictionary key
extension ResourceLocation : NSCopying {
    public func copy(with zone: NSZone?) -> Any {
        return self
    }
}
