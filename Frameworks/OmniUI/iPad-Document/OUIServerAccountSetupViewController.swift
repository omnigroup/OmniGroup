// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import OmniFileExchange
import OmniUIDocument.Internal

private let TableViewIndent: CGFloat = 15

class OUIServerAccountSetupViewControllerSectionLabel : UILabel {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.textAlignment = .left
        self.font = UIFont.systemFont(ofSize: 14)
        self.backgroundColor = UIColor.clear
        self.isOpaque = false
        self.textColor = OAAppearanceDefaultColors.shared().omniNeutralDeemphasizedColor
        self.numberOfLines = 0 /* no limit */
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func drawText(in rect: CGRect) {
        // Would be better to make a containing UIView with a label inset from the edges so that UITableView could set the frame of our view as it wishes w/o this hack.
        var updatedRect = rect
        updatedRect.origin.x += TableViewIndent
        updatedRect.size.width -= TableViewIndent

        super.drawText(in: updatedRect)
    }
}

private let LocalizedLocationLabelString = NSLocalizedString("Location", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Server Account Setup label: location")
private let LocalizedNicknameLabelString = NSLocalizedString("Nickname", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Server Account Setup label: nickname")
private let LocalizedUsernameLabelString = NSLocalizedString("Account Name", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Server Account Setup label: account name")
private let LocalizedPasswordLabelString = NSLocalizedString("Password", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Server Account Setup label: password")

private var LabelMinWidth: CGFloat = 0.0

private let OUIOmniSyncServerSetupHeaderHeight: CGFloat = 75
private let OUIServerAccountSetupViewControllerHeaderHeight: CGFloat = 40


private enum Section : Hashable {
    case address
    case credentials
    case description
    case deletion

    var rows: [Row] {
        switch self {
        case .credentials:
            return [.username, .password]
        default:
            return [.basic]
        }
    }
    
    func cell(controller: OUIServerAccountSetupViewController, tableView: UITableView, rowIndex: Int) -> UITableViewCell {
        assert(rowIndex < rows.count)
        
        if LabelMinWidth == 0.0 {
            let attributes: [NSAttributedString.Key : AnyObject] = [.font: OUIEditableLabeledValueCell.labelFont()]

            // Should really use the UITextField's width, not NSStringDrawing
            let locationLabelSize = LocalizedLocationLabelString.size(withAttributes: attributes)
            let usernameLabelSize = LocalizedUsernameLabelString.size(withAttributes: attributes)
            let passwordLabelSize = LocalizedPasswordLabelString.size(withAttributes: attributes)
            let nicknameLabelSize = LocalizedNicknameLabelString.size(withAttributes: attributes)
            
            LabelMinWidth = ceil(4 + max(locationLabelSize.width, max(usernameLabelSize.width, max(passwordLabelSize.width, nicknameLabelSize.width))))
        }

        let cell: OUIEditableLabeledTableViewCell
        let contents: OUIEditableLabeledValueCell
        
        switch self {
        case .deletion:
            let identifier = "deletion"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
            cell.textLabel?.text = NSLocalizedString("Delete Account", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Server Account Setup button label")
            cell.textLabel?.textColor = OAAppearanceDefaultColors.shared().omniDeleteColor
            cell.textLabel?.textAlignment = .center
            return cell
            
        case .address:
            cell = valueCell(controller: controller, tableView: tableView)
            contents = cell.editableValueCell
            contents.label = LocalizedLocationLabelString
            contents.value = controller.location
            contents.valueField.placeholder = OBUnlocalized("https://example.com/account/")
            contents.valueField.keyboardType = .URL
            contents.valueField.isSecureTextEntry = false
            contents.minimumLabelWidth = LabelMinWidth
            contents.labelAlignment = .right
            
        case .credentials:
            cell = valueCell(controller: controller, tableView: tableView)
            contents = cell.editableValueCell
            let row = rows[rowIndex]

            switch row {
            case .basic:
                assertionFailure("Inappropriate row for section")
                return UITableViewCell()
                
            case .username:
                contents.label = LocalizedUsernameLabelString
                contents.value = controller.accountName
                contents.valueField.placeholder = nil
                contents.valueField.keyboardType = .default
                contents.valueField.isSecureTextEntry = false
                contents.minimumLabelWidth = LabelMinWidth
                contents.labelAlignment = .right
                
            case .password:
                contents.label = LocalizedPasswordLabelString
                contents.value = controller.password
                contents.valueField.placeholder = nil
                contents.valueField.isSecureTextEntry = true
                contents.valueField.keyboardType = .default
                contents.minimumLabelWidth = LabelMinWidth
                contents.labelAlignment = .right
            }
            
        case .description:
            cell = valueCell(controller: controller, tableView: tableView)
            contents = cell.editableValueCell
            contents.label = LocalizedNicknameLabelString
            contents.value = controller.nickname
            contents.valueField.placeholder = controller._suggestedNickname
            contents.valueField.keyboardType = .default
            contents.valueField.isSecureTextEntry = false
            contents.minimumLabelWidth = LabelMinWidth
            contents.labelAlignment = .right
            
        }
           
        let key = _RowKey(section: self, row: rows[rowIndex])
        if let cachedValue = controller.cachedTextValues[key] {
            contents.value = cachedValue
        } else if let value = contents.value {
            controller.cachedTextValues[key] = value
        } else {
            controller.cachedTextValues.removeValue(forKey: key)
        }

        return cell
    }
    
    private func valueCell(controller: OUIServerAccountSetupViewController, tableView: UITableView) -> OUIEditableLabeledTableViewCell {
        let identifier = "cell"
    
        let cell = (tableView.dequeueReusableCell(withIdentifier: identifier) as? OUIEditableLabeledTableViewCell) ?? OUIEditableLabeledTableViewCell(style: .subtitle, reuseIdentifier: identifier)
        cell.selectionStyle = .none
        
        let contents = cell.editableValueCell
        contents.valueField.autocorrectionType = .no
        contents.valueField.autocapitalizationType = .none
        contents.delegate = controller
        
        contents.valueField.returnKeyType = .go
        contents.valueField.enablesReturnKeyAutomatically = true

        return cell
    }

    func headerHeight(controller: OUIServerAccountSetupViewController, tableView: UITableView) -> CGFloat {
        switch self {
        case .credentials:
            if controller.accountType.identifier == OFXOmniSyncServerAccountTypeIdentifier {
                return OUIOmniSyncServerSetupHeaderHeight + tableView.sectionHeaderHeight
            }
        case .address:
            return OUIServerAccountSetupViewControllerHeaderHeight
        default:
            break
        }
        return tableView.sectionHeaderHeight
    }
    
    func headerView(controller: OUIServerAccountSetupViewController, tableView: UITableView) -> UIView? {
        switch self {
        case .credentials where controller.accountType.identifier == OFXOmniSyncServerAccountTypeIdentifier:
            let headerView = UIView(frame: CGRect(x: 0,
                                                  y: 0,
                                                  width: 0, // Width will automatically be same as the table view it's put into.
                height: OUIOmniSyncServerSetupHeaderHeight))
            
            // Account Info Buttons
            let accountInfoButton = UIButton(type: .system)
            controller.accountInfoButton = accountInfoButton
            
            accountInfoButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
            accountInfoButton.addTarget(controller, action: #selector(OUIServerAccountSetupViewController.accountInfoButtonTapped(_:)), for: [.touchUpInside])
            accountInfoButton.setTitle(NSLocalizedString("Sign Up For a New Account", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Omni Sync Server sign up button title"),
                                       for: .normal)
            accountInfoButton.sizeToFit()
            
            var frame = accountInfoButton.frame
            frame.origin.x = TableViewIndent
            frame.origin.y = OUIOmniSyncServerSetupHeaderHeight - 44
            accountInfoButton.frame = frame
            
            headerView.addSubview(accountInfoButton)
            
            return headerView
        case .address where controller.accountType.requiresServerURL:
            let header = OUIServerAccountSetupViewControllerSectionLabel(frame: CGRect(x: TableViewIndent, y: 0, width: tableView.bounds.size.width - TableViewIndent, height: OUIServerAccountSetupViewControllerHeaderHeight))
            header.text = NSLocalizedString("Enter the location of your WebDAV space.", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "webdav help")
            return header
        default:
            return nil
        }
    }
    
    func shouldHighlight(rowIndex: Int) -> Bool {
        assert(rowIndex < rows.count)
        
        switch self {
        case .deletion:
            return true
        default:
            return false
        }
    }
}

private enum Row : Hashable {
    case basic
    case username
    case password
}

// Can't make tuples hashable currently
private struct _RowKey : Hashable {
    let section: Section
    let row: Row
}

public class OUIServerAccountSetupViewController : OUIActionViewController, OUIEditableLabeledValueCellDelegate, UITableViewDataSource, UITableViewDelegate {
    
    private var agentActivity: OFXAgentActivity
    fileprivate var accountInfoButton: UIButton?
    fileprivate var cachedTextValues = [_RowKey:String]()
    private let usageModeToCreate: OFXServerAccountUsageMode
    private let showDeletionSection: Bool

    @objc public private(set) var account: OFXServerAccount? // Nil when creating an account
    fileprivate let accountType: OFXServerAccountType
    
    // public/var so that _loadOmniPresenceConfigFileFromURL can configure them. Might be a better pattern to pass them in an initializer
    @objc public var location: String?
    @objc public var accountName: String?
    @objc public var password: String?
    @objc public var nickname: String?
    
    private var tableView: UITableView!

    private var sections: [Section]!
    
    private var saveBarButtonItem: UIBarButtonItem!
    
    private func commonPostInit() {
        let saveButtonTitle = NSLocalizedString("Save", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Account setup toolbar button title to save account settings")
        saveBarButtonItem = UIBarButtonItem(title: saveButtonTitle, style: .done, target: self, action: #selector(saveSettingsAndSync(_:)))
        
        NotificationCenter.default.addObserver(self, selector: #selector(_keyboardHeightWillChange(_:)), name: .OUIKeyboardNotifierKeyboardWillChangeFrame, object: nil)
        
        var sections = [Section]()
        
        if accountType.requiresServerURL {
            sections.append(.address)
        }
        sections.append(.credentials)
        sections.append(.description)
        
        if showDeletionSection {
            sections.append(.deletion)
        }
        
        self.sections = sections
    }
    
    init() {
        preconditionFailure("Not supported")
    }

    @objc public init(agentActivity: OFXAgentActivity, creatingAccountType accountType: OFXServerAccountType, usageMode: OFXServerAccountUsageMode) {
        self.agentActivity = agentActivity
        self.location = nil
        self.accountType = accountType
        self.usageModeToCreate = usageMode // in case we need to destroy and recreate the account due to any edits
        self.showDeletionSection = false
        self.nickname = nil

        super.init(nibName: nil, bundle: nil)

        commonPostInit()
    }

    @objc public init(agentActivity: OFXAgentActivity, account: OFXServerAccount) {
        self.agentActivity = agentActivity
        self.account = account
        self.accountType = account.type
        self.usageModeToCreate = account.usageMode // in case we need to destroy and recreate the account due to any edits
        self.showDeletionSection = true
    
        let credential = OFReadCredentialsForServiceIdentifier(account.credentialServiceIdentifier, nil)

        self.location = account.remoteBaseURL.absoluteString
        self.accountName = credential?.user
        self.password = credential?.password
        self.nickname = account.displayName
        
        super.init(nibName: nil, bundle: nil)

        commonPostInit()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .OUIKeyboardNotifierKeyboardWillChangeFrame, object: nil)
    }

    // MARK:- Actions

    @IBAction func saveSettingsAndSync(_ sender: AnyObject?) {
        let nickname = textAt(section: .description, row: .basic)
    
        let serverURL: URL?
        if accountType.requiresServerURL {
            serverURL = OFXServerAccount.signinURL(fromWebDAVString: textAt(section: .address, row: .basic) ?? "")
        } else {
            serverURL = nil
        }
                     
        let username = textAt(section: .credentials, row: .username) ?? ""
        let password = textAt(section: .credentials, row: .password) ?? ""

        if let account = account {
            // Some combinations of options require a new account
            let newRemoteBaseURL = OFURLWithTrailingSlash(accountType.baseURL(forServerURL: serverURL, username: username)!)
            if newRemoteBaseURL != account.remoteBaseURL {
                // We need to create a new account to enable cloud sync
                let oldAccount = account
                self.account = nil
                
                let oldFinished = finished
                
                finished = { (viewController, errorOrNil) in
                    if let error = errorOrNil {
                        // Pass along the error to our finished call
                        if let oldFinished = oldFinished {
                            oldFinished(viewController, error)
                        }
                    } else {
                        // Success! Remove the old account.
                        let controller = OUIDocumentAppController.shared()
                        controller.warnAboutDiscardingUnsyncedEdits(in: oldAccount, from: self, withCancelAction: {
                            if let oldFinished = oldFinished {
                                oldFinished(viewController, nil)
                            }
                        }, discardAction: {
                            oldAccount.prepareForRemoval()
                            if let oldFinished = oldFinished {
                                oldFinished(viewController, nil) // Go ahead and discard unsynced edits
                            }
                        })
                    }
                }
            }
        }

        // Remember if this is a new account or if we are changing the configuration on an existing one.
        let needValidation: Bool
        if let account = account {
            let credential: URLCredential?
            if let identifier = account.credentialServiceIdentifier {
                credential = OFReadCredentialsForServiceIdentifier(identifier, nil)
            } else {
                credential = nil
            }
            
            if (accountType.requiresServerURL && serverURL != account.remoteBaseURL) {
                needValidation = true
            } else if username != credential?.user {
                needValidation = true
            } else if password != credential?.password {
                needValidation = true
            } else {
                // isCloudSyncEnabled required a whole new account, so we don't need to test it
                needValidation = false
            }
        } else {
            let remoteBaseURL = OFURLWithTrailingSlash(accountType.baseURL(forServerURL: serverURL, username: username)!)
            
            do {
                let accountName: String
                if let nickname = nickname, !nickname.isEmpty {
                    accountName = nickname
                } else {
                    accountName = OFXServerAccount.suggestedDisplayName(for: accountType, url: remoteBaseURL, username: username, excludingAccount: nil)
                }
                
                let documentsURL = try OFXServerAccount.generateLocalDocumentsURLForNewAccount(withName: accountName)
                account = try OFXServerAccount(type: accountType, usageMode: usageModeToCreate, remoteBaseURL: remoteBaseURL, localDocumentsURL: documentsURL) // New account instead of editing one.
            } catch let err {
                self.finishWithError(err)
                OUIAppController.presentError(err, from: self)
                return
            }
                        
            needValidation = true
        }
    
        // We have an account by now.
        let account = self.account!
        
        // Let us rename existing accounts even if their credentials aren't currently valid
        
        //OBFinishPortingLater("Make the display name not editable unless we are creating a fresh account?")
        account.nickname = nickname
        
        guard needValidation else {
            _validateSaveButton()
            return
        }

        // Validate the new account settings

        guard let navigationController = self.navigationController else { return }

        let validationViewController = OUIServerAccountValidationViewController(account: account, username: username, password: password)!

        validationViewController.finished = { (vc, errorOrNil) in
            if let error = errorOrNil {
                self.account = nil // Make a new instance if this one failed and wasn't added to the registry
                navigationController.popToViewController(self, animated: true)
            
                if !(error as NSError).causedByUserCancelling {
                    // Passing a nil account so that this doesn't present an option to edit an account ... since we are already doing that.
                    let controller = OUIDocumentAppController.shared()
                    controller.presentSyncError(errorOrNil, in: navigationController, retry: nil)
                }
            } else {
                self.finishWithError(errorOrNil)
                navigationController.popToRootViewController(animated: true)
            }
        }
        
        navigationController.pushViewController(validationViewController, animated: true)
    }

    // MARK: - UIViewController subclass

    override public func loadView() {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.dataSource = self
        tableView.delegate = self
    
        tableView.isScrollEnabled = true
        tableView.alwaysBounceVertical = false

        self.tableView = tableView
        self.view = tableView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        tableView.reloadData()
    
        if navigationController?.viewControllers[0] == self {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(_cancel(_:)))
        }
        
        var rightBarButtonItems = [saveBarButtonItem!]
        if let account = account, account.usageMode == .cloudSync {
            let shareBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareAccountSettings(_:)))
            rightBarButtonItems.append(shareBarButtonItem)
        }
        self.navigationItem.rightBarButtonItems = rightBarButtonItems
    
        self.navigationItem.title = accountType.setUpAccountTitle
    
        _validateSaveButton()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    
        // OBFinishPortingLater("<bug:///147833> (iOS-OmniOutliner Bug: OUIServerAccountSetupViewController.m:281 - This isn't reliable -- it works in the WebDAV case, but not OSS, for whatever reason (likely because our UITableView isn't in the window yet)")
        tableView.layoutIfNeeded()
    
        _validateSaveButton()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    
        if accountType.requiresServerURL && (location == nil || location == "") {
            cellAt(section: .address, row: .basic)?.editableValueCell.valueField.becomeFirstResponder()
        } else if accountName == nil || accountName == "" {
            cellAt(section: .credentials, row: .username)?.editableValueCell.valueField.becomeFirstResponder()
        } else if password == nil || password == "" {
            cellAt(section: .credentials, row: .password)?.editableValueCell.valueField.becomeFirstResponder()
        }
    }

    public override var shouldAutorotate: Bool {
        return true
    }

    // MARK: - UITableViewDataSource

    public func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].rows.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return sections[indexPath.section].cell(controller: self, tableView: tableView, rowIndex: indexPath.row)
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return sections[section].headerView(controller: self, tableView: tableView)
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return sections[section].headerHeight(controller: self, tableView: tableView)
    }

    public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return sections[indexPath.section].shouldHighlight(rowIndex: indexPath.row)
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = sections[indexPath.section]
        assert(indexPath.row == 0)
    
        guard let account = account else { assertionFailure(); return }

        switch section {
        case .deletion:
            let deleteConfirmation = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            let deleteTitle = String(format: NSLocalizedString("Delete \"%@\"", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Server account setup confirmation action label format"), _accountName)
            deleteConfirmation.addAction(UIAlertAction(title: deleteTitle, style: .destructive, handler: { action in
                self.tableView.deselectRow(at: indexPath, animated: true)
                
                let controller = OUIDocumentAppController.shared()
                controller.warnAboutDiscardingUnsyncedEdits(in: account, from: self, withCancelAction: nil, discardAction: {
                    account.prepareForRemoval()
                    if let finished = self.finished {
                        finished(self, nil)
                    }
                    self.navigationController?.popViewController(animated: true)
                })
            }))
            
            if let presentationController = deleteConfirmation.popoverPresentationController {
                presentationController.sourceView = tableView
                presentationController.sourceRect = tableView.rectForRow(at: indexPath)
                presentationController.permittedArrowDirections = [.up, .down]
            }
            
            present(deleteConfirmation, animated: true)

        default:
            assertionFailure()
        }
    }

    // MARK:- OUIEditableLabeledValueCell

    public func editableLabeledValueCellTextDidChange(_ cell: OUIEditableLabeledValueCell) {
        let tableCell = cell.containingTableViewCell()
        guard let indexPath = tableView.indexPath(for: tableCell) else {
            assertionFailure("changed while off screen?"); return
        }
        
        let section = sections[indexPath.section]
        let row = section.rows[indexPath.row]
        let key = _RowKey(section: section, row: row)
        
        if let value = cell.value {
            cachedTextValues[key] = value
        } else {
            cachedTextValues.removeValue(forKey: key)
        }
        _validateSaveButton()
    }

    public func editableLabeledValueCell(_ cell: OUIEditableLabeledValueCell, textFieldShouldReturn textField: UITextField) -> Bool {
        let trySignIn = saveBarButtonItem.isEnabled
        if trySignIn {
            saveSettingsAndSync(nil)
        }
    
        return trySignIn
    }

    // MARK: - Private

    var _suggestedNickname: String {
        let url: URL?
        if let urlString = textAt(section: .address, row: .basic), urlString != "" {
            url = OFXServerAccount.signinURL(fromWebDAVString: urlString)
        } else {
            url = nil
        }
        
        let username = textAt(section: .credentials, row: .username)
        return OFXServerAccount.suggestedDisplayName(for: accountType, url: url, username: username, excludingAccount: account)
    }

    private func cellAt(section: Section, row: Row) -> OUIEditableLabeledTableViewCell? {
        guard let sectionIndex = sections.firstIndex(of: section) else { return nil }
        guard let rowIndex = section.rows.firstIndex(of: row) else { return nil }
        let path = IndexPath(item: rowIndex, section: sectionIndex)
        return tableView.cellForRow(at: path) as? OUIEditableLabeledTableViewCell
    }

    private func textAt(section: Section, row: Row) -> String? {
        assert(section.rows.contains(row))
        let key = _RowKey(section: section, row: row)
        return cachedTextValues[key]
    }

    @IBAction private func _cancel(_ sender: AnyObject?) {
        cancel()
    }

    private func _validateSaveButton() {
        var requirementsMet = true

        let accountName = textAt(section: .credentials, row: .username) ?? ""
        let hasUsername = accountName != ""

        requirementsMet = requirementsMet && hasUsername

        var locationsEqual = true
        if accountType.requiresServerURL {
            if let address = textAt(section: .address, row: .basic), let location = OFXServerAccount.signinURL(fromWebDAVString: address) {
                let baseURL = OFURLWithTrailingSlash(accountType.baseURL(forServerURL: location, username:accountName)!)
                locationsEqual = baseURL.absoluteString == self.location
            } else {
                requirementsMet = false
            }
        }

        let password = textAt(section: .credentials, row: .password) ?? ""
        requirementsMet = requirementsMet && (password != "")

        let nickname = textAt(section: .description, row: .basic)
        if (requirementsMet && accountName == self.accountName && password == self.password && locationsEqual && nickname == account?.displayName) {
            requirementsMet = false
        }

        saveBarButtonItem.isEnabled = requirementsMet
        cellAt(section: .description, row: .basic)?.editableValueCell.valueField.placeholder = _suggestedNickname

        if accountType.identifier == OFXOmniSyncServerAccountTypeIdentifier, let accountInfoButton = accountInfoButton {
            // Validate Account 'button'
            let title = hasUsername ? NSLocalizedString("Account Info", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Omni Sync Server account info button title") : NSLocalizedString("Sign Up For a New Account", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Omni Sync Server sign up button title")
            accountInfoButton.setTitle(title, for: .normal)
            accountInfoButton.sizeToFit()
        }
    }

    @IBAction fileprivate func accountInfoButtonTapped(_ sender: AnyObject?) {
        let syncSignupURL = URL(string: "http://www.omnigroup.com/sync/")!
        UIApplication.shared.open(syncSignupURL, options: [:])
    }

    private var _accountName: String {
        if let currentNickname = textAt(section: .description, row: .basic), !currentNickname.isEmpty {
            return currentNickname
        }
        return _suggestedNickname
    }

    @IBAction private func shareAccountSettings(_ sender: AnyObject?) {
        guard let barButtonItem = sender as? UIBarButtonItem else { assertionFailure(); return }

        var contents = [String:String]()
        
        contents["accountType"] = accountType.identifier
        if let name = textAt(section: .credentials, row: .username) {
            contents["accountName"] = name
        }
        // Intentionally not sending the password

        if accountType.requiresServerURL, let urlString = textAt(section: .address, row: .basic), !urlString.isEmpty {
            contents["location"] = urlString
        }
        if let nickname = textAt(section: .description, row: .basic), !nickname.isEmpty {
            contents["nickname"] = nickname
        }

        do {
            let configData = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            
            let configFilename = _accountName + ".omnipresence-config"
            let configURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(configFilename)
            
            try configData.write(to: configURL)
            
            let activityViewController = UIActivityViewController(activityItems: [configURL], applicationActivities: nil)
            activityViewController.modalPresentationStyle = .popover
            activityViewController.popoverPresentationController?.barButtonItem = barButtonItem
            
            self.present(activityViewController, animated: true)
        } catch let err {
            OUIAppController.presentError(err, from: self)
            return
        }
    }

    @objc private func _keyboardHeightWillChange(_ keyboardNotification: NSNotification) {
        let notifier = OUIKeyboardNotifier.shared
        var insets = tableView.contentInset
        insets.bottom = notifier.lastKnownKeyboardHeight
        UIView.animate(withDuration: notifier.lastAnimationDuration, delay: 0, options: OUIAnimationOptionFromCurve(notifier.lastAnimationCurve), animations: {
            self.tableView.contentInset = insets
        })
    }
}
