// Copyright 2016-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

#if os(iOS)
import UIKit
#endif

import os
private let Log = OBLogCreate(subsystem: "com.omnigroup.framework.OmniFoundation", category: "ResourceLocation")
private func x(_ object: AnyObject) -> UInt {
    return UInt(bitPattern: ObjectIdentifier(object))
}

@objc(OFResourceLocationDelegate) public protocol ResourceLocationDelegate {
    func resourceLocationDidUpdateResourceURLs(_ location: ResourceLocation)
    func resourceLocationDidMove(_ location: ResourceLocation)
}

// A KVO observable object for a set of OFFileEdits representing the current versions of resources for a given type in a location.
@objc(OFResourceLocationContents) public class ResourceLocationContents : NSObject {
    @objc dynamic public var fileEdits = Set<OFFileEdit>()
}

#if os(iOS)
private let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
private let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
#else
private let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
private let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#endif

private func CallOrNil<T, R>(_ value: T?, in function: (T) -> R) -> R? {
    if let value = value {
        return function(value)
    }
    return nil
}

private func getFolderURLContainerDisplayName(_ folderURL: URL) -> String? {
    if let values = try? folderURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemContainerDisplayNameKey]) {
        if let isUbiquitousItem = values.isUbiquitousItem, isUbiquitousItem {
            return values.ubiquitousItemContainerDisplayName
        }

    }
    return nil
}

@objc(OFResourceLocation) public class ResourceLocation : NSObject, NSFilePresenter {

    @objc /**REVIEW**/ static let WillStartScanning = Notification.Name("OFResourceLocationWillStartScanning")
    @objc static let DidFinishScanning = Notification.Name("OFResourceLocationDidFinishScanning")
    
    // folderURL can possibly be read on the background queue by presentedItemURL() and our scanning, so we have a lock for it.
    private let lock: NSLock
    private var _bookmark: Data? // nil for folders inside the app container
    private var _folderURL: URL
    private var _folderContainerDisplayName: String?

    @objc public var folderURL: URL {
        return lock.protect {
            return _folderURL
        }
    }
    @objc public var folderURLContainerDisplayName: String? {
        return lock.protect {
            return _folderContainerDisplayName
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
    private var resourceTypes: [String:ResourceType]

    // The rest of the state should only be accessed on the main queue
    private var rescanForPresentedItemDidChangeRunning: Bool = false
    private var presentedItemDidChangeCalledWhileRescanning: Bool = false

    private weak var delegate: ResourceLocationDelegate?
    private var invalidated: Bool = false

    private var registeredFilePresenter: Bool

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
     //   assert(resourceTypes.isEmpty == false)

        self.lock = NSLock()
        self._bookmark = bookmark
        self._folderURL = folderURL
        self._folderContainerDisplayName = getFolderURLContainerDisplayName(folderURL)
        self.delegate = delegate

        self.resourceTypes = resourceTypes.mapValues({ predicate -> ResourceType in
            return ResourceType(predicate: predicate, contents: ResourceLocationContents())
        })

        #if os(iOS)
        // Will be nil in unit tests or app extensions, for example.
        let wantsFilePresenter: Bool
        if let app = OFSharedApplication() {
            wantsFilePresenter = true
            registeredFilePresenter = app.applicationState != .background
        } else {
            wantsFilePresenter = false
            registeredFilePresenter = false
        }
        #else
        registeredFilePresenter = true
        #endif

        super.init()

        os_log("%x Initialize for URL \"%{public}@\"", log: Log, type: .debug, x(self), folderURL.absoluteString)

        #if os(iOS)
        // Don't sign up for these notifications in app extensions.
        if wantsFilePresenter {
            os_log("%x Subscribed to app-lifecycle notifications", log: Log, type: .debug, x(self))
            NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(applicationWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        #endif
        if registeredFilePresenter {
            os_log("%x Register as file presenter", log: Log, type: .debug, x(self))
            NSFileCoordinator.addFilePresenter(self)
        }

        if synchronousInitialScan {
            let scannedFileEdits = peformScan(folderURL: folderURL, synchronousInitialScan: true)
            finishScan(scannedFolderURL: folderURL, scannedFileEdits: scannedFileEdits)
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
        if registeredFilePresenter {
            os_log("%x Re-registering as file presenter", log: Log, type: .debug, x(self))
            NSFileCoordinator.removeFilePresenter(self)
            NSFileCoordinator.addFilePresenter(self)
        }
    }

    // NSFileCoordinator retains us, so we need an invalidate method.
    @objc public func invalidate() {
        assert(OperationQueue.current == OperationQueue.main)

        if invalidated {
            return
        }
        invalidated = true
        if registeredFilePresenter {
            os_log("%x Deregister as file presenter", log: Log, type: .debug, x(self))
            NSFileCoordinator.removeFilePresenter(self)
        }
        delegate = nil

        lock.protect {
            if _bookmark == nil {
                // This is a folder inside the app container
            } else {
                _folderURL.stopAccessingSecurityScopedResource()
            }
        }
    }

    @objc public func resourceContents(type: String) -> ResourceLocationContents? {
        return resourceTypes[type]?.contents
    }

    // Returns true if the argument URL is the same as the folderURL or somewhere under it. This does not do a membership test on resourceURLs.
    public func containsURL(_ url: URL) -> Bool {
        return lock.protect {
            return OFURLEqualsURL(_folderURL, url) || OFURLContainsURL(_folderURL, url)
        }
    }

    public func add(resourceType: String, withPredicate predicate: ResourceTypePredicate) {
        let newResource = ResourceType(predicate: predicate, contents: ResourceLocationContents())
        resourceTypes.updateValue(newResource, forKey: resourceType)
        requestScan()
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
        os_log("%x File presenter: %{public}@", log: Log, type: .debug, x(self), #function)
        self.requestScan()
    }

    public func presentedItemDidMove(to newURL: URL) {
        assert(OperationQueue.current == ResourceLocation.FilePresenterQueue)
        assert(_bookmark != nil, "Handle moving a built-in resource folder?")

        os_log("%x File presenter: %{public}@", log: Log, type: .debug, x(self), #function)

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
        os_log("%x File presenter: %{public}@", log: Log, type: .debug, x(self), #function)

        writer {
            self.requestScan()
        }
    }

    public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        os_log("%x File presenter: %{public}@", log: Log, type: .debug, x(self), #function)

        assert(OperationQueue.current == ResourceLocation.FilePresenterQueue)

        assertionFailure("Finish")
    }
    

    public func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        os_log("%x File presenter: %{public}@", log: Log, type: .debug, x(self), #function)
        self.requestScan()
    }

    public func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Swift.Void) {
        os_log("%x File presenter: %{public}@", log: Log, type: .debug, x(self), #function)
        completionHandler(nil)
        self.requestScan()
    }

    public func presentedSubitemDidAppear(at url: URL) {
        os_log("%x File presenter: %{public}@", log: Log, type: .debug, x(self), #function)
        self.requestScan()
    }

    public func presentedSubitemDidChange(at url: URL) {
        os_log("%x File presenter: %{public}@", log: Log, type: .debug, x(self), #function)
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

        guard resourceTypes.count > 0 else { return }
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

            let scannedFileEdits = self.peformScan(folderURL: folderURL)

            OperationQueue.main.addOperation {
                self.finishScan(scannedFolderURL: folderURL, scannedFileEdits: scannedFileEdits)
                completionHandler()
            }
        }
    }

    private func finishScan(scannedFolderURL: URL, scannedFileEdits: [String:ScannedFileEdits]) {
        assert(OperationQueue.current == OperationQueue.main)

        var didChange = false
        scannedFileEdits.forEach { pair in
            guard let type = resourceTypes[pair.key] else {
                assertionFailure("Should have a resource type entry")
                return
            }
            if type.contents.fileEdits != pair.value.fileEdits {
                type.contents.fileEdits = pair.value.fileEdits
                didChange = true
            }
        }
        if didChange {
            delegate?.resourceLocationDidUpdateResourceURLs(self)
        }
        NotificationCenter.default.post(name: ResourceLocation.DidFinishScanning, object: self)
    }

    private class ScannedFileEdits {
        var fileEdits: Set<OFFileEdit>

        init() {
            fileEdits = []
        }
    }

    private func peformScan(folderURL: URL, synchronousInitialScan: Bool = false) -> [String:ScannedFileEdits] {
        assert(synchronousInitialScan || OperationQueue.current == ResourceLocation.FileScanQueue)

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isUbiquitousItemKey, .ubiquitousItemDownloadRequestedKey]

        // Having a non-nil error handler crashes in Xcode 8.0 and 8.1b1 (at least if the folder doesn't exist) <https://bugs.swift.org/browse/SR-2872>
        let searchOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants ]
        guard let topLevelEnumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: Array(keys), options: searchOptions, errorHandler: nil) else {
            return [:]
        }

        let scannedFileEdits = resourceTypes.mapValues { _ in return ScannedFileEdits() }

        os_log("%x File scan start", log: Log, type: .debug, x(self))

        // DirectoryEnumerator is a NSEnumerator, which isn't generic and can't declare that it yields NSURLs.
        for item in topLevelEnumerator {
            let fileURL = (item as! NSURL) as URL
            os_log("%x fileURL %{public}@", log: Log, type: .debug, x(self), fileURL.absoluteString)

            #if os(iOS)
            guard !fileURL.path.contains("/.Trash/") else { continue }

            if OFIsInboxFolder(fileURL) {
                topLevelEnumerator.skipDescendants()
                continue
            }
            #endif

            guard let values = try? fileURL.resourceValues(forKeys: keys) else {
                continue
            }

            let pathExtension: String
            let needsDownloading: Bool

            let isDirectory = CallOrNil(values.isDirectory, in: NSNumber.init(value:))

            // Using this instead of URLResourceKey.typeIdentifierKey since that doesn't consult exported types in our unit test bundles.
            // .typeIdentifierKey is also not helpful when scanning an iCloud folder and we find a non-downloaded placeholder file (with the private type "com.apple.icloud-file-fault")
            // Using URL.promisedItemResourceValues(forKeys:) inside a file coordinator read passed the .immediatelyAvailableMetadataOnly option still doesn't report the metadata for the real item, possibly since we aren't exactly matching the conditions. We are a NSFilePresenter, but the URL we have is not in our container (the whole reason for this class is to be granted access to stuff outside our container!)
            // Logged as FB7631137: URL.promisedItemResourceValues(forKeys:) does not return correct values for iCloud placeholders
            if let isUbiquitousItem = values.isUbiquitousItem, let downloaded = values.ubiquitousItemDownloadRequested, isUbiquitousItem && !downloaded {
                // Because of the above, we'll take a hacky undocumented approach. The xattr "com.apple.icloud.itemName" looks like it also has the actual name.
                assert(fileURL.pathExtension == "icloud")
                pathExtension = fileURL.deletingPathExtension().pathExtension
                needsDownloading = true
            } else {
                pathExtension = fileURL.pathExtension
                needsDownloading = false
            }
            let fileTypeIdentifier = OFUTIForFileExtensionPreferringNative(pathExtension, isDirectory)

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

                if needsDownloading {
                    // The coordinated read might work, but we don't want to unnecessarily block scanning. Instead, just request a download of this file.
                    os_log("%x ... request download", log: Log, type: .debug, x(self))
                    do {
                        try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                    } catch let err {
                        print("Error starting download of \(fileURL): \(err)")
                    }
                } else {
                    let coordinator = NSFileCoordinator(filePresenter: nil)

                    // Don't force saving plug-ins that are being edited elsewhere.
                    do {
                        try coordinator.readItem(at: fileURL, withChanges: false) { (newURL, outError) -> Bool in
                            do {
                                let fileEdit = try OFFileEdit(fileURL: newURL)
                                scannedFileEdits[resourceType.0]!.fileEdits.insert(fileEdit)
                                return true
                            } catch let editError {
                                outError?.pointee = editError as NSError
                                return false
                            }
                        }
                    } catch let err {
                        print("Error reading \(fileURL): \(err)")
                    }
                }

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

        return scannedFileEdits
    }

    private func update(folderURL: URL, bookmark: Data) {
        assert(OperationQueue.current == OperationQueue.main)

        guard !invalidated else {
            return
        }
        
        lock.protect {
            self._folderURL = folderURL
            self._bookmark = bookmark
            self._folderContainerDisplayName = getFolderURLContainerDisplayName(folderURL)
        }

        delegate?.resourceLocationDidMove(self)
    }

    #if os(iOS)
    @objc private func applicationDidEnterBackground(_ notification: Notification) {
        if registeredFilePresenter {
            registeredFilePresenter = false
            os_log("%x Deregister as file presenter", log: Log, type: .debug, x(self))
            NSFileCoordinator.removeFilePresenter(self)
        }
    }
    @objc private func applicationWillEnterForeground(_ notification: Notification) {
        if !registeredFilePresenter {
            registeredFilePresenter = true
            os_log("%x Register as file presenter", log: Log, type: .debug, x(self))
            NSFileCoordinator.addFilePresenter(self)
            requestScan()
        }
    }
    #endif

}

// Allow being a pointer-based dictionary key
@available(iOSApplicationExtension, unavailable)
extension ResourceLocation : NSCopying {
    public func copy(with zone: NSZone?) -> Any {
        return self
    }
}
