// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import OmniFoundation
import OmniFileExchange.Internal

// Object to perform and maintain information about an in-progress attempt to migrate an old-style iOS sync account from storing its local document contents in ~/Library/... to storing it in the app's Documents folder.

public class OFXAccountMigration: NSObject {

    private let accountAgent: OFXAccountAgent
    private let accountActivity: OFXAccountActivity
    
    @objc public init(accountAgent: OFXAccountAgent, accountActivity: OFXAccountActivity) {
        self.status = NSLocalizedString("Migration starting...", tableName: "OmniFileExchange", bundle: OFXBundle, comment: "Account migration status")
        self.accountAgent = accountAgent
        self.accountActivity = accountActivity
    }
    
    @objc public dynamic var isRunning: Bool = false
    @objc public dynamic var status: String

    private var completionHandler: ((OFXAccountMigration, Error?) -> Void)? = nil
    
    // If this is set, we are doing a 'migrate to Files' and need the user to pick a containing folder, and we'll copy the files there and then remove the account.
    @objc public var chooseDestination: OFXMigrationChooseDestination? = nil
    
    @objc public func start(_ completionHandler: @escaping (OFXAccountMigration, Error?) -> Void) {
        precondition(self.isRunning == false)
        precondition(self.completionHandler == nil)

        // Do a sync to make sure we know about remote edits
        self.completionHandler = completionHandler
        
        status =  NSLocalizedString("Syncing with server...", tableName: "OmniFileExchange", bundle: OFXBundle, comment: "Account migration status")
        startSync()
    }
    
    // MARK:- Private
    
    // 1) Do a sync to make sure we know about remote edits

    private var syncAttempts = 0
    
    private func startSync() {
        isRunning = true
        accountAgent.sync { errorOrNil in
            DispatchQueue.main.async {
                self.syncFinished(errorOrNil)
            }
        }
    }
    
    private func syncFinished(_ error: Error?) {
        if let error = error {
            if (error as NSError).causedByUserCancelling {
                // This can happen in some cases when file provider messages update version numbers in the account agent.
                syncAttempts += 1
                if syncAttempts > 10 {
                    status = "Unable to sync"
                } else {
                    startSync()
                    return
                }
            } else {
                // Some more serious error.
                status = error.localizedDescription
            }
            
            migrationStopped(error)
            return
        }
        
        // Wait for pending metadata updates
        status =  NSLocalizedString("Examining synchronized files...", tableName: "OmniFileExchange", bundle: OFXBundle, comment: "Account migration status")
        accountAgent._afterMetadataUpdate {
            self.initialMetadataUpdated()
        }
    }
    
    // 2) Wait for the initial metadata, which may be queued up.

    private var valuesObservation: NSKeyValueObservation? = nil
    
    private func initialMetadataUpdated() {
        let registrationTable = accountActivity.registrationTable!
        
        valuesObservation = registrationTable.observe(\.values, options: [.initial], changeHandler: { _, _ in
            self.metadataChanged()
        })
    }
    
    // 3) Request downloads for any remote files that haven't been downloaded
    // 4) Ensure all pending transfers are completed
    // 5) Stop the agent
    private func metadataChanged() {
        let metadataItems = accountActivity.registrationTable.values as! Set<OFXFileMetadata>
        
        // TODO: This doesn's show pending deletes and renames, or maybe those are included in the upload count.
        var transfersPending: Bool = accountActivity.downloadingFileCount > 0 || accountActivity.uploadingFileCount > 0
        
        for file in metadataItems {
            if !file.isDownloaded && !file.hasDownloadQueued {
                accountAgent.requestDownloadOfItem(at: file.fileURL, completionHandler: nil)
                transfersPending = true
            }
        }
        
        print("metadata = \(metadataItems.map { $0.debugDictionary })")
        
        if transfersPending {
            // Maybe show individual state here.
            status =  NSLocalizedString("Waiting for transfers to finish...", tableName: "OmniFileExchange", bundle: OFXBundle, comment: "Account migration status")
        } else {
            status =  NSLocalizedString("Pausing sync for account...", tableName: "OmniFileExchange", bundle: OFXBundle, comment: "Account migration status")
            
            // Stop observing metadata changes, so we don't call stop() again.
            valuesObservation = nil
            
            accountAgent.stop {
                DispatchQueue.main.async {
                    self.syncStopped()
                }
            }
        }
    }
    
    // 6) Move the OmniPresence documents folder into the local Documents folder
    //    -- If we fail between these two points, the account will think it's local documents have gone missing and re-download them (and still consider itself not migrated).
    // 7) Update the local documents bookmark data and save the account info
    // 8) Restart the agent

    private func userDocumentsDirectoryURL() throws -> URL {
        return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
    
    private func syncStopped() {
        if let chooseDestination = chooseDestination {
            copyToFiles(chooseDestination: chooseDestination)
        } else {
            moveToLocalDocuments()
        }
    }

    private func makeUpdatedDocumentsURL(parentDirectoryURL: URL) throws -> URL {
        let account = accountAgent.account
        let name = account.displayName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")

        let proposedDocumentsURL = parentDirectoryURL.appendingPathComponent(name)
        print("proposedDocumentsURL \(proposedDocumentsURL)")

        // Handle the case of a directory already being there.
        let updatedDocumentsPath = try FileManager.default.uniqueFilename(fromName: proposedDocumentsURL.absoluteURL.path, allowOriginal: true, create: false)
        let updatedDocumentsURL = URL(fileURLWithPath: updatedDocumentsPath)
        print("updatedDocumentsURL \(updatedDocumentsURL)")

        return updatedDocumentsURL
    }
    
    private func moveToLocalDocuments() {
        do {
            dispatchPrecondition(condition: .onQueue(.main))

            // TODO: Maybe should actually use a file picker to let the user place the documents. Would need to check the selected location afterware though to make sure it is in the Documents directory (instead of inside Dropbox or whatever).
            let updatedDocumentsURL = try makeUpdatedDocumentsURL(parentDirectoryURL: try userDocumentsDirectoryURL())
            let account = accountAgent.account

            
            let moveQueue = OperationQueue()
            moveQueue.name = "com.omnigroup.OmniFileExchange.AccountMigration.Move"

            // Here we are moving out of our ~/Library and there should be vanishingly few file presenters still watching anything in the moving folder since the account is stopped. But, we might have preview generation going on or maybe some stray thing. We want those file presenters to think the folder has gone way, not get updated to point to the new location.
            let coordinator = NSFileCoordinator(filePresenter: nil)
            let sourceIntent = NSFileAccessIntent.writingIntent(with: account.localDocumentsURL, options: [.forDeleting])
            let destinationIntent = NSFileAccessIntent.writingIntent(with: updatedDocumentsURL, options: [])
            
            coordinator.coordinate(with: [sourceIntent, destinationIntent], queue: moveQueue) { errorOrNil in
                dispatchPrecondition(condition: .notOnQueue(.main))
                
                if let error = errorOrNil {
                    DispatchQueue.main.async {
                        self.migrationStopped(error)
                    }
                    return
                }
                do {
                    try FileManager.default.moveItem(at: sourceIntent.url, to: destinationIntent.url)
                    DispatchQueue.main.async {
                        self.moveToLocalDocumentsCompleted(updatedDocumentsURL: updatedDocumentsURL)
                    }
                } catch let err {
                    DispatchQueue.main.async {
                        self.migrationStopped(err)
                    }
                }
            }
        } catch let err {
            migrationStopped(err)
        }
    }
    
    private func moveToLocalDocumentsCompleted(updatedDocumentsURL: URL) {
        dispatchPrecondition(condition: .onQueue(.main))

        do {
            try accountAgent.account.didMigrateToLocalDocumentsURL(updatedDocumentsURL)
            migrationStopped(nil)
        } catch let err {
            migrationStopped(err)
        }
    }
    
    private func copyToFiles(chooseDestination: OFXMigrationChooseDestination) {
        chooseDestination { destinationURL, errorOrNil in
            
            // TODO: start accessing the URL here?
            let isAccessing: Bool
            if let destinationURL = destinationURL {
                isAccessing = destinationURL.startAccessingSecurityScopedResource()
                if !isAccessing {
                    print("Unable to start accessing on \(destinationURL)")
                }
            } else {
                isAccessing = false
            }
            
            DispatchQueue.main.async {
                guard let destinationURL = destinationURL else {
                    self.migrationStopped(errorOrNil!)
                    return
                }
                
                self.copyToFiles(choosenDestinationURL: destinationURL) {
                    if isAccessing {
                        destinationURL.stopAccessingSecurityScopedResource()
                    }
                }
            }
        }
    }
    
    private func copyToFiles(choosenDestinationURL destinationURL: URL, completionHandler: @escaping () -> Void) {
        do {
            // TODO: Ensure this isn't in our Documents folder?
            
            // This is currently treated as the parent of the whole copy operation so that we don't have to unique every file vs the contents of the destination directory.
            let account = self.accountAgent.account
            let updatedDocumentsURL = try makeUpdatedDocumentsURL(parentDirectoryURL: destinationURL)

            assert(accountAgent.started == false)

            let copyQueue = OperationQueue()
            copyQueue.name = "com.omnigroup.OmniFileExchange.AccountMigration.Copy"
            
            copyQueue.addOperation {
                self.performCopyToFiles(account: account, updatedDocumentsURL: updatedDocumentsURL, completionHandler: completionHandler)
            }
        } catch let err {
            completionHandler()
            migrationStopped(err)
        }
    }
    
    // Perform the copy, using file coordination.
    private func performCopyToFiles(account: OFXServerAccount, updatedDocumentsURL: URL, completionHandler: @escaping () -> Void) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        
        do {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            try coordinator.readItem(at: account.localDocumentsURL, withChanges: true, writeItemAt: updatedDocumentsURL, withChanges: true) { (sourceURL, destinationURL, outError) -> Bool in
                do {
                    print("Performing migration copy from \(sourceURL) to \(destinationURL)")
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    print("Performing migration copy finished")
                    return true
                } catch let err {
                    if let outError = outError {
                        outError.pointee = err as NSError
                    }
                    return false
                }
            }
        
            DispatchQueue.main.async {
                // Success!
                completionHandler()
                account.prepareForRemoval() // Do this first so that no new account agent is started when migrationDidFinish is called.
                self.migrationStopped(nil)
            }
        } catch let err {
            DispatchQueue.main.async {
                completionHandler()
                self.migrationStopped(err)
            }
        }
    }
    
    private func migrationStopped(_ errorOrNil: Error?) {
        print("Migration ended with error \(String(describing: errorOrNil))")
        
        // OFXAccountAgent is single use (can't be restarted). The migrationDidFinish() will notify OFXAgent to remove this account agent and make a new one (and start it).
        accountAgent.migrationDidFinish()
        isRunning = false
        
        if let completionHandler = self.completionHandler {
            self.completionHandler = nil
            completionHandler(self, errorOrNil)
        } else {
            assertionFailure()
        }
    }
}
