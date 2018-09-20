// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@objc public protocol OUIInternalTemplateDelegate: class {
    func placeholderImage(for url: URL) -> UIImage
    func numberOfInteralSections(in templatePicker: OUITemplatePicker) -> Int
    func internalSupportedLanguages(in templatePicker: OUITemplatePicker) -> [String]
    func supportsGeneralTemplates(in templatePicker: OUITemplatePicker) -> Bool
    // total number of sections will be numberOfInteralSections + 1 (General templates, the user created templates) if supported.
    // The delegate is only responsible for the internal sections
    func templatePicker(_ templatePicker: OUITemplatePicker, numberOfRowsInSection section: Int, for language: String) -> Int
    func templatePicker(_ templatePicker: OUITemplatePicker, templateItemRowAt indexPath: IndexPath, for language: String) -> OUITemplateItem
    func templatePicker(_ templatePicker: OUITemplatePicker, titleForHeaderInSection section: Int, for language: String) -> String
}


@objc public protocol OUITemplatePickerDelegate: class {
    func templatePicker(_ templatePicker: OUITemplatePicker, didSelect templateURL: URL, animateFrom: UIView)
    func generalTemplates(in templatePicker: OUITemplatePicker) -> [OUITemplateItem]
}


public final class OUITemplateItem: NSObject, ODSFileItemProtocol {

    @objc public var fileURL: URL
    @objc public var fileEdit: OFFileEdit
    @objc public var fileType: String
    @objc public let isValid = true
    @objc public var isDownloaded = true
    @objc public var fileModificationDate: Date {
        get {
            return fileEdit.fileModificationDate
        }
    }
    @objc public weak var scope: ODSScope? = nil

    @objc public var displayName: String
    @objc public var previewImage: UIImage? {
        get {
            var image: UIImage?
            if let preview = OUIDocumentPreview.make(forDocumentClass: OUIDocumentAppController.shared().documentClass(for: fileURL), fileItem: self, with: .large) {
                preview.incrementDisplayCount()
                if let previewImage = preview.image {
                    image = UIImage(cgImage: previewImage)
                }
                preview.decrementDisplayCount()
            }
            return image
        }
    }

    @objc public init(fileURL: URL, fileEdit: OFFileEdit, displayName: String) {
        self.fileURL = fileURL
        self.fileEdit = fileEdit
        self.displayName = displayName
        self.fileType = UTI.fileTypePreperringNative(fileURL.pathExtension) ?? ""

        super.init()
    }

    @objc public func name() -> String {
        return displayName
    }
}


public enum TemplateLabelHeight {
    private static var regular: [String: CGFloat] = [String: CGFloat]()
    private static var compact: [String: CGFloat] = [String: CGFloat]()

    static let generalKey = "CustomTemplates"
    static let compactWidth: CGFloat = 90
    static let regularWidth: CGFloat = 210

    private static func height(_ templateItem: OUITemplateItem, isCompact: Bool) -> CGFloat {
        let width = isCompact ? compactWidth : regularWidth
        let fontSize: CGFloat = isCompact ? 10 : 18

        let label = UILabel()
        label.numberOfLines = 0
        label.text = templateItem.displayName
        label.font = UIFont.systemFont(ofSize: fontSize)
        let displaySize = label.sizeThatFits(CGSize(width: width, height: 40))

        return displaySize.height
    }

    public static func regular(_ language: String) -> CGFloat {
        if let height = regular[language] {
            return max(height, regular[generalKey] ?? 0)
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

    public static func update(with templateItem: OUITemplateItem, language: String) {
        regular[language] = max(regular[language] ?? 0, height(templateItem, isCompact: false))
        compact[language] = max(compact[language] ?? 0, height(templateItem, isCompact: true))
    }
}

public class OUITemplatePicker: UIViewController {

    fileprivate static let showLanguagePickerIdentifier = "showLanguagePicker"
    fileprivate static let cellIdentifier = "templateCell"
    fileprivate static let headerIdentifier = "sectionHeader"
    fileprivate static let currentLanguagePreferenceKey = "OUITemplatePickerCurrentLanguage"
    fileprivate static let knownLanguagesPreferenceKey = "OUITemplatePickerKnownLanguages"

    @IBOutlet weak var collectionView: UICollectionView!
    @objc public weak var internalTemplateDelegate: OUIInternalTemplateDelegate?
    @objc public weak var templateDelegate: OUITemplatePickerDelegate?

    @objc public var documentPicker: OUIDocumentPicker?
    @objc public var folderItem: ODSFolderItem?
    @objc public var navigationTitle: String?
    @objc public var wantsCancelButton = true
    @objc public var wantsLanguageButton = true
    @objc public var isEmbedded = false

    fileprivate var currentLanguage: String = Locale.current.languageCode!
    fileprivate var languages = [String]()
    fileprivate var languageButton: UIBarButtonItem?
    fileprivate weak var languagePicker: OUILanguagePicker?
    fileprivate var generalTemplates = [OUITemplateItem]()

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

    fileprivate func cancelPicker() {
        navigationController?.popViewController(animated: true)
    }

    @objc fileprivate func cancel() {
        self.navigationController?.popViewController(animated: isEmbedded)
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

    override public func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == OUITemplatePicker.showLanguagePickerIdentifier {
            if let viewController = segue.destination as? OUILanguagePicker {
                languagePicker = viewController
                viewController.popoverPresentationController?.barButtonItem = languageButton
                viewController.languageDelegate = self
            }
        }
    }
}


// MARK: - UIViewController subclass
extension OUITemplatePicker {

    @objc fileprivate func previewGenerationDidFinish(notification: Notification) {
        collectionView.reloadData()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(self.previewGenerationDidFinish(notification:)), name: NSNotification.Name(rawValue: "OUIDocumentPreviewsUpdatedForFileItemNotification"), object: nil)

        if let scrollView = self.collectionView.enclosingView(of: UIScrollView.self) {
            var inset = scrollView.contentInset
            let adjustment: CGFloat = traitCollection.horizontalSizeClass != .regular ? 10 : 40

            inset.left += adjustment
            inset.right += adjustment
            scrollView.contentInset = inset
        }

        if let delegate = internalTemplateDelegate {
            if delegate.supportsGeneralTemplates(in: self) {
                if let templateDelegate = templateDelegate {
                    generalTemplates = templateDelegate.generalTemplates(in: self)
                    for template in generalTemplates {
                        TemplateLabelHeight.update(with: template, language: TemplateLabelHeight.generalKey)
                    }
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
        let languageTitle = localizedLanguage(for: currentLanguage)
        if wantsLanguageButton {
            if languageButton == nil {
                languageButton = UIBarButtonItem(title: languageTitle, style: .plain, target: self, action: #selector(showLanguagePicker))
            } else {
                languageButton?.title = languageTitle
            }
        }

        if wantsCancelButton {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
            navigationItem.setLeftBarButton(cancelButton, animated: true)
        }
        navigationItem.title = navigationTitle
        navigationItem.setRightBarButton(languageButton, animated: true)
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
            collectionView.reloadData()
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
        return isEmbedded || traitCollection.horizontalSizeClass == .compact || traitCollection.verticalSizeClass == .compact
    }

    fileprivate func cellSize() -> CGSize {
        let compact = wantsCompactSize()
        let width = compact ? TemplateLabelHeight.compactWidth : TemplateLabelHeight.regularWidth
        var height = compact ? TemplateLabelHeight.compact(currentLanguage) : TemplateLabelHeight.regular(currentLanguage)
        height += width + 4.0

        return CGSize(width: width, height: height)
    }

    fileprivate func wantsCustomTemplateSection() -> Bool {
        guard let delegate = internalTemplateDelegate else { return false }

        return delegate.supportsGeneralTemplates(in: self) && generalTemplates.count > 0
    }

    fileprivate func firstInternalSection() -> Int {
        return wantsCustomTemplateSection() ? 1 : 0
    }

    fileprivate func isInternal(section: Int) -> Bool {
        guard internalTemplateDelegate != nil else { return false }

        return section >= firstInternalSection()
    }

    fileprivate func internalSection(for section: Int) -> Int {
        return section - firstInternalSection()
    }

    fileprivate func templateItem(for indexPath: IndexPath) -> OUITemplateItem? {
        guard let delegate = internalTemplateDelegate else { return nil }

        var templateItem: OUITemplateItem?
        if isInternal(section: indexPath.section) {
            var internalIndexPath = indexPath
            internalIndexPath.section = internalSection(for: indexPath.section)
            templateItem = delegate.templatePicker(self, templateItemRowAt: internalIndexPath, for: currentLanguage)
        } else {
            let index = indexPath.row
            guard index < generalTemplates.count else { return nil }
            templateItem = generalTemplates[index]
        }
        return templateItem
    }

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard let delegate = internalTemplateDelegate else { return 0 }

        var numberOfSections = delegate.numberOfInteralSections(in: self)
        if wantsCustomTemplateSection() {
            numberOfSections += 1
        }

        return numberOfSections
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let delegate = internalTemplateDelegate else { return 0 }

        if isInternal(section: section) {
            return delegate.templatePicker(self, numberOfRowsInSection: internalSection(for: section), for: currentLanguage)
        } else {
            return generalTemplates.count
        }
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OUITemplatePicker.cellIdentifier, for: indexPath) as! OUITemplatePickerCell

        let templateItem = self.templateItem(for: indexPath)

        let size = cellSize()
        cell.imageWidthConstraint.constant = size.width
        cell.imageHeightConstraint.constant = size.width
        cell.preview.layer.cornerRadius = 5.0
        cell.preview.layer.masksToBounds = true

        if let displayName = cell.displayName {
            let fontSize: CGFloat = wantsCompactSize() ? 10 : 18
            displayName.text = templateItem?.displayName
            displayName.font = UIFont.systemFont(ofSize: fontSize)
            let displaySize = displayName.sizeThatFits(CGSize(width: size.width, height: 40))
            cell.displayNameHeightConstraint.constant = displaySize.height
        }

        cell.preview.image = templateItem?.previewImage
        cell.url = templateItem?.fileURL

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
            if !wantsCustomTemplateSection() && delegate.numberOfInteralSections(in: self) == 1 {
                // There is only one section do not provide a header.
                view.isHidden = true
                return view
            }
            headerTitle = delegate.templatePicker(self, titleForHeaderInSection: internalSection(for: indexPath.section), for: currentLanguage)
        } else {
            headerTitle = NSLocalizedString("ouiTemplatePicker.customTemplatesHeader", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, value: "Custom", comment: "Custom templates header title")
        }
        view.label.text = headerTitle?.localizedUppercase

        return view
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let templateItem = self.templateItem(for: indexPath) {
            let view = self.collectionView(collectionView, cellForItemAt: indexPath) as! OUITemplatePickerCell
            templateDelegate?.templatePicker(self, didSelect: templateItem.fileURL, animateFrom: view.preview)
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

        if let delegate = internalTemplateDelegate, isInternal(section: section) && !wantsCustomTemplateSection() && delegate.numberOfInteralSections(in: self) == 1 {
            return CGSize(width: width, height: 10)
        }

        if wantsCompactSize() {
            return CGSize(width: width, height: 40)
        } else {
            return CGSize(width: width, height: 50)
        }
    }
    
}
