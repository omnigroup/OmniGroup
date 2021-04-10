// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import UIKit
import OmniFileExchange
import OmniAppKit

private struct MigrationError : LocalizedError {
    let reason: String
    
    var errorDescription: String? {
        return NSLocalizedString("Error Migrating", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Account migration error description")
    }

    var failureReason: String? {
        return reason
    }
}

private enum Section : CaseIterable {
    case moveToFiles
    case moveToLocalDocuments
    case delete
    
    var rows: [Row] {
        let header: Row
        let steps = [Row]() // TODO: Showing these as a section footer view right now, with no progress info.
        
        switch self {
        case .moveToFiles:
            header = .header(title: NSLocalizedString("Move to Files", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Account migration option"),
                                                  description: NSLocalizedString("Copy Documents in OmniPresence to a different syncing file provider in Files, such as iCloud Drive.", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Account migration option"))
        case .moveToLocalDocuments:
            header = .header(title: NSLocalizedString("Move to Local Documents", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Account migration option"),
                                                           description: NSLocalizedString("Keep using OmniPresence temporarily, with documents available in a folder inside this application's Documents.", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Account migration option"))
            
        case .delete:
            header = .header(title: NSLocalizedString("Remove Account", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Account migration option"), description: NSLocalizedString("Stop syncing with OmniPresence on this device.", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Account migration option"))
            
        }
        
        return [header] + steps
    }    
}

private enum Row {
    case header(title: String, description: String)
    case step(String)
}

private enum CellIdentifier : String {
    case option
}

class OUIMigrationOptionTableViewCell : UITableViewCell {
    
    @IBOutlet var migrationTitleLabel: UILabel!
    @IBOutlet var migrationDescriptionLabel: UILabel!

}

class OUIMigrateAccountViewController: UITableViewController, UIDocumentPickerDelegate {
        
    private let agentActivity: OFXAgentActivity
    private let account: OFXServerAccount
    private let sections: [Section]
    
    private var startMigrationBarButtonItem: UIBarButtonItem!
    private var deleteBarButtonItem: UIBarButtonItem!

    init(agentActivity: OFXAgentActivity, account: OFXServerAccount) {
        self.agentActivity = agentActivity
        self.account = account
        
        if account.requiresMigration {
            // Offer to migrate to the local documents
            self.sections = [.moveToFiles, .moveToLocalDocuments, .delete]
        } else {
            // If we've already moved to the local documents, still allow moving to Files
            self.sections = [.moveToFiles, .delete]
        }
        
        super.init(style: .grouped)
        
        self.title = String(format: NSLocalizedString("Migrate \"%@\"", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Migration bar button item"), account.displayName)

        startMigrationBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Migrate", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Migration bar button item"), style: .plain, target: self, action: #selector(startMigration(_:)))
        deleteBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Remove", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Migration bar button item"), style: .plain, target: self, action: #selector(startMigration(_:)))
        deleteBarButtonItem.tintColor = UIColor.systemRed
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    // MARK:- UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UINib(nibName: "AccountMigrationOption", bundle: OmniUIDocumentBundle), forCellReuseIdentifier: CellIdentifier.option.rawValue)
        updateRightBarButtonItem()
    }
    
    // MARK:- UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section]
        let row = section.rows[indexPath.row]
        
        switch row {
        case .header(title: let title, description: let description):
            let identifier = CellIdentifier.option.rawValue
            guard let cell = tableView.dequeueReusableCell(withIdentifier: identifier) as? OUIMigrationOptionTableViewCell else {
                assertionFailure("Couldn't find cell")
                return UITableViewCell()
            }

            cell.migrationTitleLabel?.text = title
            cell.migrationDescriptionLabel?.text = description
            return cell
            
        case .step(let description):
            let identifier = "step"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
            cell.textLabel?.text = description
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        let section = sections[indexPath.section]
        let row = section.rows[indexPath.row]
        
        switch row {
        case .header:
            return true
        default:
            return false
        }
    }
    
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let section = sections[section]

        switch section {
        case .moveToLocalDocuments:
            return infoText(["Sync with OmniPresence to upload any local changes and find remote changes.",
                             "Download all remote files.",
                             "Show the Documents for this account in the application's Documents",
                             "Continue syncing changes from that folder to your account"
            ])
        case .moveToFiles:
            return infoText(["Sync with OmniPresence to upload any local changes and find remote changes.",
                             "Download all remote files.",
                             "Select a folder in another syncing file provider in Files.",
                             "Copy OmniPresence documents to Files.",
                             "Remove this OmniPresence account on this device.",
                             "Note that copies of your documents will remain on server for this account for safe-keeping."
            ])
        case .delete:
            return infoText(["Sync with OmniPresence to upload any local changes.",
                             "Remove this OmniPresence account on this device.",
                             "Note that copies of your documents will remain on server for this account for safe-keeping."
            ])
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        updateRightBarButtonItem()
    }
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        updateRightBarButtonItem()
    }
    
    // MARK:- UIDocumentPickerDelegate
    
    private func reportChosenDestinationURL(_ url: URL?, _ errorOrNil: Error?) {
        assert((url == nil) != (errorOrNil == nil))
        guard let chosenDestinationURL = chosenDestinationURL else { assertionFailure(); return }

        self.chosenDestinationURL = nil
        chosenDestinationURL(url, errorOrNil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard urls.count == 1, let url = urls.first else {
            reportChosenDestinationURL(nil, MigrationError(reason: NSLocalizedString("Must select a single destination folder.", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Account migration error reason")))
            return
        }
        reportChosenDestinationURL(url, nil)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        reportChosenDestinationURL(nil, CocoaError(.userCancelled))
    }
    
    // MARK:- Private
    
    private func updateRightBarButtonItem() {
        guard let indexPath = tableView.indexPathForSelectedRow else {
            navigationItem.rightBarButtonItem = startMigrationBarButtonItem
            startMigrationBarButtonItem.isEnabled = false
            return
        }
        
        let section = sections[indexPath.section]
        assert(indexPath.row == 0)
        
        switch section {
        case .moveToLocalDocuments, .moveToFiles:
            navigationItem.rightBarButtonItem = startMigrationBarButtonItem
        case .delete:
            navigationItem.rightBarButtonItem = deleteBarButtonItem
        }

        navigationItem.rightBarButtonItem?.isEnabled = (currentMigration == nil)
    }
    
    // This is the moveToLocalDocuments case.
    private var currentMigration: OFXAccountMigration? = nil {
        didSet {
            updateRightBarButtonItem()
            
            // When in a migration, replace the back button with a cancel button and disable dismissal via swipe down.
            if currentMigration == nil {
                navigationItem.leftBarButtonItem = nil
                isModalInPresentation = false
            } else {
                navigationItem.leftBarButtonItem = UIBarButtonItem(title: OACancel(), style: .plain, target: self, action: #selector(cancel(_:)))
                isModalInPresentation = true
            }
        }
    }
    
    @IBAction func cancel(_ sender: AnyObject?) {
        print("cancel")
    }
    
    @IBAction private func startMigration(_ sender: AnyObject?) {
        precondition(currentMigration == nil)
        
        guard let indexPath = tableView.indexPathForSelectedRow else { assertionFailure(); return }
        let section = sections[indexPath.section]
        
        switch section {
        case .moveToLocalDocuments:
            do {
                currentMigration = try agentActivity.agent.startMigratingAccountToLocalDocuments(account, activity: agentActivity, completionHandler: { errorOrNil in
                    self.migrationFinished(errorOrNil)
                })
            } catch let err {
                self.migrationFinished(err)
                return
            }
            
        case .moveToFiles:
            do {
                currentMigration = try agentActivity.agent.startMigratingAccountToFiles(account, activity: agentActivity, chooseDestination: {
                    self.chooseDestinationURL(completionHandler: $0)
                }, completionHandler: { errorOrNil in
                    self.migrationFinished(errorOrNil)
                })
            } catch let err {
                self.migrationFinished(err)
                return
            }

        default:
            let controller = OUIDocumentAppController.shared()
            let account = self.account
            controller.warnAboutDiscardingUnsyncedEdits(in: account, from: self, withCancelAction: {
                self.migrationFinished(CocoaError(.userCancelled))
            }, discardAction: {
                account.prepareForRemoval()
                self.migrationFinished(nil)
            })
        }
        
    }

    private var chosenDestinationURL: ((URL?, Error?) -> Void)? = nil
    
    private func chooseDestinationURL(completionHandler: @escaping (URL?, Error?) -> Void) {
        assert(chosenDestinationURL == nil)
        chosenDestinationURL = completionHandler
        
        let picker = UIDocumentPickerViewController(documentTypes: [kUTTypeFolder as String], in: .open)
        picker.delegate = self
        self.navigationController?.present(picker, animated: true)
    }
    
    private func migrationFinished(_ errorOrNil: Error?) {
        currentMigration = nil
        
        if let error = errorOrNil {
            OUIDocumentAppController.presentError(error, from: self)
            return
        }
        
        guard let navigation = navigationController else { assertionFailure(); return }
        assert(navigation.viewControllers.first is OUIServerAccountsViewController)
        navigation.popToRootViewController(animated: true)
    }
    
    private func infoText(_ lines: [String]) -> UILabel {
        let label = UILabel()
        
        label.textAlignment = .left
        label.font = UIFont.systemFont(ofSize: 14)
        label.backgroundColor = UIColor.clear
        label.isOpaque = false
        label.textColor = OAAppearanceDefaultColors.shared().omniNeutralDeemphasizedColor
        label.numberOfLines = 0 /* no limit */
        
        let text = (lines.map { "  • " + $0 }).joined(separator: "\n")

        label.text = text

        label.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)
        
        return label
    }
}
