// Copyright 2017-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@objc public protocol OUIInternalTemplateDelegate: class {
    func shouldUseTemplatePicker() -> Bool
    
    func wantsLanguageButton() -> Bool
    func wantsLinkedFolderButton() -> Bool
    func placeholderImage(for url: URL) -> UIImage
    func numberOfInternalSections(in templatePicker: OUITemplatePicker) -> Int
    func internalSupportedLanguages(in templatePicker: OUITemplatePicker) -> [String]
    var templatePickerCustomTemplateFileTypes: [String]? { get }
    // total number of sections will be numberOfInternalSections + 1 (Custom templates, the user created templates) if supported.
    // The delegate is only responsible for the internal sections
    func templatePicker(_ templatePicker: OUITemplatePicker, numberOfRowsInSection section: Int, for language: String) -> Int
    func templatePicker(_ templatePicker: OUITemplatePicker, templateItemRowAt indexPath: IndexPath, for language: String) -> OUITemplateItem
    func templatePicker(_ templatePicker: OUITemplatePicker, titleForHeaderInSection section: Int, for language: String) -> String

}

public final class OUITemplateItem: NSObject {

    @objc public let fileURL: URL
    @objc public let fileType: String

    @objc public let displayName: String

    @objc public init(fileURL: URL, displayName: String, fileType: String? = nil) {
        self.fileURL = fileURL
        self.displayName = displayName
        self.fileType = fileType ?? UTI.fileTypePreferringNative(fileURL.pathExtension) ?? ""
    }
}


public enum TemplateLabelHeight {
    private static var regular: [String: CGFloat] = [String: CGFloat]()
    private static var compact: [String: CGFloat] = [String: CGFloat]()

    static let customKey = "CustomTemplates"
    static let compactWidth: CGFloat = 90
    static let regularWidth: CGFloat = 170

    fileprivate static func templateLabelFont(compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        let isCompact = traitCollection?.horizontalSizeClass == .compact || traitCollection?.verticalSizeClass == .compact
        let textStyle: UIFont.TextStyle = isCompact ? .caption1 : .title3
        return UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traitCollection)
    }
    
    private static func height(_ templateItem: OUITemplateItem, compatibleWith traitCollection: UITraitCollection?) -> CGFloat {
        let isCompact = traitCollection?.horizontalSizeClass == .compact || traitCollection?.verticalSizeClass == .compact
        let width = isCompact ? compactWidth : regularWidth

        let label = UILabel()
        label.numberOfLines = 0
        label.text = templateItem.displayName
        label.font = templateLabelFont(compatibleWith: traitCollection)
        let displaySize = label.sizeThatFits(CGSize(width: width, height: 0.25 * width))

        return displaySize.height
    }

    public static func regular(_ language: String) -> CGFloat {
        if let height = regular[language] {
            return max(height, regular[customKey] ?? 0)
        } else {
            return 20
        }
    }

    public static func compact(_ language: String) -> CGFloat {
        if let height = compact[language] {
            return height
        } else {
            return 20
        }
    }

    public static func update(with templateItem: OUITemplateItem, language: String, compatibleWith traitCollection: UITraitCollection?) {
        regular[language] = max(regular[language] ?? 0, height(templateItem, compatibleWith: traitCollection))
        compact[language] = max(compact[language] ?? 0, height(templateItem, compatibleWith: traitCollection))
    }
}

public class OUITemplatePicker: UIViewController, UIDocumentPickerDelegate {

    @objc public static func newTemplatePicker() -> OUITemplatePicker {
        let storyboard = UIStoryboard(name: "OUITemplatePicker", bundle: OUITemplatePicker.bundle())
        let viewController = storyboard.instantiateViewController(withIdentifier: "templatePicker") as! OUITemplatePicker
        return viewController
    }

    fileprivate static let showLanguagePickerIdentifier = "showLanguagePicker"
    fileprivate static let cellIdentifier = "templateCell"
    fileprivate static let headerIdentifier = "sectionHeader"
    fileprivate static let currentLanguagePreferenceKey = "OUITemplatePickerCurrentLanguage"
    fileprivate static let knownLanguagesPreferenceKey = "OUITemplatePickerKnownLanguages"

    @IBOutlet weak var collectionView: UICollectionView!
    @objc public weak var internalTemplateDelegate: OUIInternalTemplateDelegate?
    @objc public weak var templateDelegate: OUITemplatePickerDelegate?
    {
        didSet {
            var templateFileTypes: [UTI] = []
            if let templateDelegate = templateDelegate, let templateUTIs = templateDelegate.templateUTIs?() {
                templateFileTypes = templateUTIs.map { UTI($0) }
            }
            let templateUTIPredicate = UTIResourceTypePredicate(fileTypes: templateFileTypes)

            linkedTemplateFolders = TemplateResourceBookmarks(preferenceKey: "linkedTemplateFolderBookmarks", resourceTypes: [templateBookmarkType : templateUTIPredicate]) {
                self.linkedFolderCache = self.updateLinkedFileItemCache()
                self.collectionView.reloadData()
            }
        }
    }

    @objc public var navigationTitle: String?
    @objc public var wantsCancelButton = true
    @objc public var wantsLanguageButton = true
    @objc public var wantsLinkedFolderButton = true
    @objc public var supportedFileTypes = [String]()

    fileprivate var linkFolderButton: UIBarButtonItem?

    fileprivate var currentLanguage: String = Locale.current.languageCode! {
        didSet {
            collectionView.reloadData()
        }
    }
    fileprivate var languages = [String]()
    fileprivate var languageButton: UIBarButtonItem?
    fileprivate weak var languagePicker: OUILanguagePicker?
    fileprivate lazy var customTemplates: [OUITemplateItem] = scanForCustomTemplates()

    fileprivate var linkedTemplateFolders: TemplateResourceBookmarks?
    private var linkedFolderQuerySourceObservation: NSObjectProtocol?
    private let templateBookmarkType = "template"
    private var linkedFolderCache: [OUITemplateItem] = []

    // MARK: - Actions
    @objc public static func knownLanguages() -> [String]? {
        return UserDefaults.standard.array(forKey: knownLanguagesPreferenceKey) as? [String]
    }

    fileprivate static func register(currentLanguage: String, newLanguage: String) {
        UserDefaults.standard.set(newLanguage, forKey: OUITemplatePicker.currentLanguagePreferenceKey)
        var knownLanguages = Set<String>()
        if let klanguages = OUITemplatePicker.knownLanguages() {
            for klang in klanguages {
                knownLanguages.insert(klang)
            }
        }
        knownLanguages.insert(currentLanguage)
        knownLanguages.insert(newLanguage)
        UserDefaults.standard.setValue(Array(knownLanguages), forKey: OUITemplatePicker.knownLanguagesPreferenceKey)
    }

    @objc fileprivate func cancel() {
        templateDelegate?.templatePickerDidCancel(self)
    }

    fileprivate func dismissLanguagePicker() {
        languagePicker?.dismiss(animated: true, completion: nil)
        languagePicker = nil
    }

    @objc fileprivate func showLanguagePicker() {
        if languagePicker == nil {
            performSegue(withIdentifier: OUITemplatePicker.showLanguagePickerIdentifier, sender: languageButton)
        } else {
            dismissLanguagePicker()
        }
    }

    @objc fileprivate func chooseLinkedFolder() {
        let picker = UIDocumentPickerViewController(documentTypes: [kUTTypeFolder as String], in: .open)
        picker.allowsMultipleSelection = true // Without this, we don't get a "Open" option
        picker.delegate = self

        picker.modalPresentationStyle = .overCurrentContext

        self.present(picker, animated: true)
    }

    // MARK:- UIDocumentPickerDelegate

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let linkedTemplateFolders = linkedTemplateFolders  else { return }

        for url in urls {
            do {
                try linkedTemplateFolders.addResourceFolderURL(url)
            } catch let err {
                print("Error adding template folder: \(err)")
            }
        }
    }

    override public func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == OUITemplatePicker.showLanguagePickerIdentifier {
            if let viewController = segue.destination as? OUILanguagePicker {
                languagePicker = viewController
                viewController.popoverPresentationController?.barButtonItem = languageButton
                viewController.languageDelegate = self
            }
        }
    }

    fileprivate func scanForCustomTemplates() -> [OUITemplateItem] {
        guard let fileTypesArray = internalTemplateDelegate?.templatePickerCustomTemplateFileTypes else {
            return []
        }
        let fileTypes = Set(fileTypesArray)

        var templates = [OUITemplateItem]()
        func scanFile(url: URL) {
            let fileType = UTI.fileTypePreferringNative(url.pathExtension) ?? ""
            if fileTypes.contains(fileType) {
                let pathComponent = url.lastPathComponent as NSString
                let displayName = pathComponent.deletingPathExtension
                let item = OUITemplateItem(fileURL: url, displayName: displayName, fileType: fileType)
                templates.append(item)
            }
        }

        let fileManager = FileManager.default
        func scanFolder(url: URL) {
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
            guard let directoryEnumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsPackageDescendants]) else { return }
            for case let fileURL as URL in directoryEnumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                    let isDirectory = resourceValues.isDirectory,
                    let isHidden = resourceValues.isHidden
                    else {
                        continue
                }

                if isDirectory && isHidden {
                    directoryEnumerator.skipDescendants() // In particular, we want to skip .Trash
                } else {
                    scanFile(url: fileURL)
                }
            }
        }

        let appController = OUIDocumentAppController.shared()
        scanFolder(url: appController.localDocumentsURL)
        if let icloudStencilsURL = appController.iCloudDocumentsURL {
            scanFolder(url: icloudStencilsURL)
        }
        return templates.sorted { (item1, item2) -> Bool in
            let displayName1 = item1.displayName
            let displayName2 = item2.displayName
            if displayName1 == displayName2 {
                return item1.fileURL.path < item2.fileURL.path
            } else {
                return displayName1 < displayName2
            }
        }
    }
}


// MARK: - UIViewController subclass
extension OUITemplatePicker {

    open override func viewDidLoad() {
        super.viewDidLoad()

        if let scrollView = self.collectionView.enclosingView(of: UIScrollView.self) {
            var inset = scrollView.contentInset
            let adjustment: CGFloat = traitCollection.horizontalSizeClass != .regular ? 10 : 40

            inset.left += adjustment
            inset.right += adjustment
            scrollView.contentInset = inset
        }

        if let delegate = internalTemplateDelegate {
            if let _ = delegate.templatePickerCustomTemplateFileTypes {
                for template in customTemplates {
                    TemplateLabelHeight.update(with: template, language: TemplateLabelHeight.customKey, compatibleWith: traitCollection)
                }
            }

            languages = delegate.internalSupportedLanguages(in: self)
            if let language = UserDefaults.standard.string(forKey: OUITemplatePicker.currentLanguagePreferenceKey), languages.contains(language) {
                currentLanguage = language
            } else if let language = Bundle.main.preferredLocalizations.first, languages.contains(language) {
                currentLanguage = language
            }
            if !languages.contains(currentLanguage) {
                currentLanguage = "en"
            }
        }
        updateNavigationBar()
    }

}


//MARK: - UITraitEnvironment
extension OUITemplatePicker {

    fileprivate func localizedLanguage(for languageCode: String) -> String {
        if let language = Locale.current.localizedString(forLanguageCode: languageCode) {
            return language
        } else {
            return languageCode
        }
    }

    fileprivate func updateNavigationBar() {
        let navigationItem = self.navigationItem
        var rightButtonItems: [UIBarButtonItem] = []
        let languageTitle = localizedLanguage(for: currentLanguage)
        if wantsLanguageButton {
            if languageButton == nil {
                languageButton = UIBarButtonItem(title: languageTitle, style: .plain, target: self, action: #selector(showLanguagePicker))
            } else {
                languageButton?.title = languageTitle
            }
            if let langButton = languageButton {
                rightButtonItems.append(langButton)
            }
        }

        if wantsCancelButton {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
            navigationItem.setLeftBarButton(cancelButton, animated: true)
        }

        if wantsLinkedFolderButton {
            if linkFolderButton == nil {
                linkFolderButton = UIBarButtonItem(title: "Link Folder", style: .plain, target: self, action: #selector(chooseLinkedFolder))
            }
            if let linkButton = linkFolderButton {
                rightButtonItems.append(linkButton)
            }
        }
        navigationItem.title = navigationTitle
        navigationItem.setRightBarButtonItems(rightButtonItems, animated: true)
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateNavigationBar()
    }

}


// MARK: - OUILanguagePickerDelegate
extension OUITemplatePicker: OUILanguagePickerDelegate {

    @nonobjc public func didPick(language: String) {
        if languages.contains(language) {
            OUITemplatePicker.register(currentLanguage: currentLanguage, newLanguage: language)

            currentLanguage = language
            languageButton?.title = localizedLanguage(for: language)
        }
        dismissLanguagePicker()
    }

    @nonobjc public func currentSelectedLanguage() -> String {
        return currentLanguage
    }

    @nonobjc public func pickerLanguages() -> [String] {
        return languages
    }

}


// MARK: - UICollectionViewDataSource
extension OUITemplatePicker: UICollectionViewDataSource {

    fileprivate func wantsCompactSize() -> Bool {
        return traitCollection.horizontalSizeClass == .compact || traitCollection.verticalSizeClass == .compact
    }

    fileprivate func cellSize() -> CGSize {
        let compact = wantsCompactSize()
        let width = compact ? TemplateLabelHeight.compactWidth : TemplateLabelHeight.regularWidth
        let labelHeight = compact ? TemplateLabelHeight.compact(currentLanguage) : TemplateLabelHeight.regular(currentLanguage)
        let height = labelHeight + 4.0 + width

        return CGSize(width: width, height: height)
    }

    fileprivate func wantsCustomTemplateSection() -> Bool {
        guard let delegate = internalTemplateDelegate else { return false }
        return delegate.templatePickerCustomTemplateFileTypes != nil && customTemplates.count > 0
    }

    fileprivate func wantsLinkedFoldersSection() -> Bool {
        return linkedFolderCache.count > 0
    }

    fileprivate func firstInternalSection() -> Int {
        var firstSection = 0

        if wantsLinkedFoldersSection() {
            firstSection += 1
        }
        if wantsCustomTemplateSection() {
            firstSection += 1
        }
        return firstSection
    }

    fileprivate func isInternal(section: Int) -> Bool {
        guard internalTemplateDelegate != nil else { return false }

        return section >= firstInternalSection()
    }

    fileprivate func isCustom(section: Int) -> Bool {
        return section == 0 && wantsCustomTemplateSection() // if we have a custom section, it'll be in the first section
    }

    fileprivate func isLinkedFolders(section: Int) -> Bool {
        return isCustom(section: section) == false && isInternal(section: section) == false
    }

    fileprivate func internalSection(for section: Int) -> Int {
        return section - firstInternalSection()
    }

    private func updateLinkedFileItemCache() -> [OUITemplateItem] {
        var allTheFileItems: [OUITemplateItem] = []
        guard let linkedTemplateFolders = linkedTemplateFolders else { return allTheFileItems }
        for location in linkedTemplateFolders.bookmarkedResourceLocations {

            guard let contents = location.resourceContents(type: templateBookmarkType) else {
                break
            }

            for fileEdit in contents.fileEdits {
                let templateURL = fileEdit.originalFileURL

                // checking for (and skipping) hidden files
                if let isHidden = try? templateURL.resourceValues(forKeys: [URLResourceKey.isHiddenKey]).isHidden, isHidden == true {
                    continue
                }

                let templateURLFolder = templateURL.deletingLastPathComponent()
                // checking for (and skipping) hidden folders (ex .Trash)
                if let isHidden = try? templateURLFolder.resourceValues(forKeys: [URLResourceKey.isHiddenKey]).isHidden, isHidden == true {
                    continue
                }
                let pathComponent = templateURL.lastPathComponent as NSString
                let displayName = pathComponent.deletingPathExtension
                let templateItem = OUITemplateItem(fileURL: templateURL, displayName: displayName)
                allTheFileItems.append(templateItem)
            }
        }
        return allTheFileItems
    }

    // here's the brains
    fileprivate func templateItem(for indexPath: IndexPath) -> OUITemplateItem? {
        guard let delegate = internalTemplateDelegate else { return nil }

        var templateItem: OUITemplateItem?
        if isInternal(section: indexPath.section) {
            var internalIndexPath = indexPath
            internalIndexPath.section = internalSection(for: indexPath.section)
            templateItem = delegate.templatePicker(self, templateItemRowAt: internalIndexPath, for: currentLanguage)
        } else if isCustom(section: indexPath.section) {
            let index = indexPath.row
            guard index < customTemplates.count else { return nil }
            templateItem = customTemplates[index]
        } else { // linked folders
            let index = indexPath.row
            guard index < linkedFolderCache.count else { return nil }
            templateItem = linkedFolderCache[index]
        }
        return templateItem
    }

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard self.isViewLoaded, let delegate = internalTemplateDelegate else { return 0 }

        var numberOfSections = delegate.numberOfInternalSections(in: self)
        if wantsCustomTemplateSection() {
            numberOfSections += 1
        }
        if wantsLinkedFoldersSection() {
            numberOfSections += 1
        }

        return numberOfSections
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let delegate = internalTemplateDelegate else { return 0 }

        if isInternal(section: section) {
            return delegate.templatePicker(self, numberOfRowsInSection: internalSection(for: section), for: currentLanguage)
        } else if isCustom(section: section) {
            return customTemplates.count
        } else {
            return self.linkedFolderCache.count
        }
        return 0
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OUITemplatePicker.cellIdentifier, for: indexPath) as! OUITemplatePickerCell

        guard let templateItem = self.templateItem(for: indexPath) else {
            assertionFailure()
            return cell
        }

        if let displayName = cell.displayName {
            displayName.text = templateItem.displayName
            displayName.font = TemplateLabelHeight.templateLabelFont(compatibleWith: traitCollection)
        }

        cell.templateItem = templateItem
        
        return cell
    }
}


// MARK: - UICollectionViewDelegate
extension OUITemplatePicker: UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: OUITemplatePicker.headerIdentifier, for: indexPath) as! OUITemplatePickerHeader

        guard let delegate = internalTemplateDelegate, kind == UICollectionView.elementKindSectionHeader else {
            view.isHidden = true
            return view
        }

        var headerTitle: String?
        if isInternal(section: indexPath.section) {
            if !wantsCustomTemplateSection() && delegate.numberOfInternalSections(in: self) == 1 {
                // There is only one section do not provide a header.
                view.isHidden = true
                return view
            }
            headerTitle = delegate.templatePicker(self, titleForHeaderInSection: internalSection(for: indexPath.section), for: currentLanguage)
        } else if isCustom(section: indexPath.section) {
            headerTitle = NSLocalizedString("ouiTemplatePicker.customTemplatesHeader", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, value: "Custom", comment: "Custom templates header title")
        } else if isLinkedFolders(section: indexPath.section) {
            headerTitle = NSLocalizedString("ouiTemplatePicker.LinkedFolderHeader", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, value: "Linked Folders", comment: "linked folders header title")
        }
        view.label.text = headerTitle?.localizedUppercase

        return view
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let templateItem = self.templateItem(for: indexPath) {
            let view = self.collectionView(collectionView, cellForItemAt: indexPath) as! OUITemplatePickerCell
            templateDelegate?.templatePicker(self, didSelectTemplateURL: templateItem.fileURL, animateFrom: view.preview)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? OUITemplatePickerCell {
            cell.willDisplay()
        }
    }
}


// MARK: - UICollectionViewDelegateFlowLayout
extension OUITemplatePicker: UICollectionViewDelegateFlowLayout {

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        if traitCollection.horizontalSizeClass != .regular {
            return 10
        } else {
            return 20
        }
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        if traitCollection.horizontalSizeClass != .regular {
            return 10
        } else {
            return 20
        }
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return cellSize()
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        var insetAdjustment: CGFloat = 0
        if let scrollView = self.collectionView.enclosingView(of: UIScrollView.self) {
            let contentInset = scrollView.contentInset
            insetAdjustment += contentInset.right + contentInset.left
        }
        let width = collectionView.contentSize.width - insetAdjustment

        if let delegate = internalTemplateDelegate, isInternal(section: section) && !wantsCustomTemplateSection() && delegate.numberOfInternalSections(in: self) == 1 {
            return CGSize(width: width, height: 10)
        }

        if wantsCompactSize() {
            return CGSize(width: width, height: 40)
        } else {
            return CGSize(width: width, height: 50)
        }
    }
    
}
