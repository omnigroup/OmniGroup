// Copyright 2017-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


public protocol OUILanguagePickerDelegate: AnyObject {
    func didPick(language: String)
    func currentSelectedLanguage() -> String
    func pickerLanguages() -> [String]
}


public final class OUILanguagePicker: UITableViewController {

    private var token: NSKeyValueObservation?
    public weak var languageDelegate: OUILanguagePickerDelegate?

    public override func viewDidLoad() {
        super.viewDidLoad()

        token = self.tableView.observe(\.contentSize) { [weak self] object, change in
            var size = object.contentSize
            size.width = min(size.width, 320)
            self?.preferredContentSize = size
        }
    }

    // MARK: UITableViewController subclass
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let languageDelegate = languageDelegate {
            let languages = languageDelegate.pickerLanguages()
            languageDelegate.didPick(language: languages[indexPath.row])
        }
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let languageDelegate = languageDelegate {
            return languageDelegate.pickerLanguages().count
        } else {
            return 0
        }
    }

    public override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 44
    }

    public override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "header")
        cell.textLabel?.text = NSLocalizedString("ouiLanguagePicker.language", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, value: "Language", comment: "Language section title")
        cell.textLabel?.textAlignment = .center
        cell.backgroundColor = UIColor.systemGroupedBackground
        return cell
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "language")

        if let languageDelegate = languageDelegate {
            let languages = languageDelegate.pickerLanguages()
            let currentLanguage = languageDelegate.currentSelectedLanguage()
            let languageCode = languages[indexPath.row]
            let selected = languageCode == currentLanguage
            cell.textLabel?.text = Locale.current.localizedString(forLanguageCode: languageCode)
            cell.accessoryType = selected ? .checkmark : .none
        }

        return cell
    }
}
