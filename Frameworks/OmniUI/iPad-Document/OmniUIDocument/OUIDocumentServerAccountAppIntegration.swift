// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import OmniFileExchange
import SwiftUI

@objc public protocol SyncActivityObserver {
    var agentActivity: OFXAgentActivity { get }
    func accountActivityForServerAccount(_ serverAccount: OFXServerAccount) -> OFXAccountActivity?
    var accountsUpdated: ((_ updatedAccounts: [OFXServerAccount], _ addedAccounts: [OFXServerAccount], _ removedAccounts: [OFXServerAccount]) -> Void)? { get set }
    var accountChanged: ((_ account: OFXServerAccount) -> Void)? { get set }
}

@objc(OUIDocumentServerAccountSyncAccountStatus) public protocol SyncAccountStatus {
    var statusText: String? { get }
    var hasErrorStatus: Bool { get }
}

@objc(OUIDocumentServerAccountFileListViewFactory)
public class OUIDocumentServerAccountFileListViewFactory: NSObject {
    @objc public static func fileListViewController(serverAccount: OFXServerAccount, observer: SyncActivityObserver) -> UIViewController {
        DownloadIcon.bundle = OmniUIDocumentBundle
        let account = OmniPresenceAccount(account: serverAccount, observer: observer)
        let userData = ServerAccountFileListEnvironment(serverAccount: account)
        userData.localizedAccountStatusItemsAndSizeFormat = NSLocalizedString("%@ items, %@", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence file list: status: items and size format")
        userData.localizedAccountStatusItemsAndSizeWithDownloadsFormat = NSLocalizedString("%@ items, %@ (%@ downloaded, %@)", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence file list: status: items and size with downloads format")
        userData.localizedSortOrderFolderAndName = NSLocalizedString("folder and name", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence file list: sort order option")
        userData.localizedSortOrderSize = NSLocalizedString("size", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence file list: sort order option")
        userData.localizedSortOrderModificationDate = NSLocalizedString("modification date", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence file list: sort order option")
        userData.localizedSortOrderName = NSLocalizedString("name", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence file list: sort order option")
        userData.localizedSortLabel = NSLocalizedString("Sort by:", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence file list: sort order label")

        let rootView = FileList().environmentObject(userData)
        let viewController = UIHostingController(rootView: rootView)

        userData.openFileBlock = { file in
            guard let sceneDelegate = viewController.sceneDelegate else { return }
            viewController.dismiss(animated: true) {
                sceneDelegate.openDocument(inPlace: file.fileURL)
            }
        }

        userData.humanReadableStringForSizeBlock = { fileSize in
            return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }

        observer.accountsUpdated = { [weak account] (_updatedAccounts, _addedAccounts, removedAccounts) in
            account?.updateFiles()
            if removedAccounts.contains(serverAccount) {
                viewController.navigationController?.popViewController(animated: true)
            }
        }

        return viewController
    }

    @objc public static func syncAccountStatus(serverAccount: OFXServerAccount, observer: SyncActivityObserver) -> SyncAccountStatus {
        return OmniPresenceAccount(account: serverAccount, observer: observer)
    }
}

fileprivate class OmniPresenceAccount: ServerAccount, SyncAccountStatus {
    var account: OFXServerAccount
    var observer: SyncActivityObserver
    var filesDidChangeBlock: (() -> Void)?
    var files: [File] = [] {
        didSet {
            guard let filesDidChangeBlock = self.filesDidChangeBlock else { return }
            filesDidChangeBlock()
        }
    }

    var statusText: String? {
        if let errorString = self.errorString {
            return errorString;
        }

        guard let activity = observer.accountActivityForServerAccount(account) else { return nil }
        guard activity.isActive else {
            // If we're not actively syncing, show the last sync time
            let date = activity.lastSyncDate
            guard let timeString = lastSyncTimeFormatter.string(for: date) else { return nil }
            let lastSyncPrefix = NSLocalizedString("Last sync", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence sync status: prefix for the 'last sync' status")
            return "\(lastSyncPrefix): \(timeString)"
        }

        // Show the upload and download counts
        let uploadCount = activity.uploadingFileCount;
        let downloadCount = activity.downloadingFileCount;

        if uploadCount != 0 && downloadCount != 0 {
            return NSLocalizedString("Uploading and downloading files", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence sync status")
        } else if uploadCount != 0 {
            return NSLocalizedString("Uploading files", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence sync status")
        } else {
            return NSLocalizedString("Downloading files", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "OmniPresence sync status")
        }
    }

    var hasErrorStatus: Bool {
        return account.lastError != nil
    }

    func requestSync() {
        self.observer.agentActivity.agent.sync({ [weak self] in
            self?.updateFiles()
        })
    }

    func requestHelp() {
        let url = URL(string: "https://www.omnigroup.com/forward/manage-omnipresence-downloads")!
        UIApplication.shared.open(url)
    }

    init(account: OFXServerAccount, observer: SyncActivityObserver) {
        self.account = account
        self.observer = observer
        updateFiles()

        observer.accountChanged = { [weak self] account in
            guard let self = self, self.account == account else { return }
            self.updateFiles()
        }
    }

    var accountName: String {
        return account.displayName
    }

    private var cache = [URL:File]()
    private func _file(baseURL: URL, fileURL: URL) -> File {
        if let file = cache[fileURL] {
            return file
        }
        let file = File(baseURL: baseURL, fileURL: fileURL)
        cache[fileURL] = file
        return file
    }

    func updateFiles() {
        guard let activity = observer.accountActivityForServerAccount(account),
            let metadataItems = activity.registrationTable?.values as? Set<OFXFileMetadata>
            else {
                self.files = []
                return
        }

        let baseURL = account.localDocumentsURL
        let files = metadataItems.compactMap { (metadataItem) -> File? in
            guard let fileURL = metadataItem.fileURL else { return nil }
            let file = _file(baseURL: baseURL, fileURL: fileURL)
            file.modificationDate = metadataItem.modificationDate
            file.size = Int64(metadataItem.fileSize)
            let isDownloaded = metadataItem.isDownloaded
            file.isDownloaded = isDownloaded
            if isDownloaded {
                file.isDownloading = false
            } else if metadataItem.hasDownloadQueued || metadataItem.isDownloading {
                file.isDownloading = true
            } else {
                // Otherwise, we leave file.isDownloading however it was set before
            }
            file.requestDownloadBlock = { [weak self] file in
                guard let agent = self?.observer.agentActivity.agent else { return }
                agent.requestDownloadOfItem(at: file.fileURL) { (error) in
                    guard error == nil else {
                        file.isDownloading = false
                        print("Unable to download \(file.fileURL.absoluteString): \(error!)")
                        return
                    }
                }
            }
            return file
        }
        self.files = files
    }

    fileprivate var errorString: String? {
        guard let error = OBFirstUnchainedError(account.lastError) else { return nil }
        let nsError = error as NSError
        guard let recoverySuggestion = nsError.localizedRecoverySuggestion else {
            return error.localizedDescription
        }
        return "\(error.localizedDescription) \(recoverySuggestion)"
    }
}

fileprivate let lastSyncTimeFormatter: DateFormatter = {
    let formatter = OFRelativeDateFormatter()!
    formatter.useRelativeDayNames = true
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
}()
