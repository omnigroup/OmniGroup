// Copyright 2020-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

struct cachedFolder {
    let url: URL
    let displayPath: String
}

@objc(OUILinkedFolderPreferenceViewController) public class LinkedFolderPreferenceViewController: UITableViewController, UIDocumentPickerDelegate {
    var linkedFolderCache: [cachedFolder] = []
    private let resourceType = "folders"
    private var headerText: String?

    @IBOutlet weak var headerLabel: UILabel!
    
    @objc public static func makeViewController(headerText: String) -> LinkedFolderPreferenceViewController {
        let storyboard = UIStoryboard(name: "OUILinkedFolderPreferenceView", bundle: OmniUIDocumentBundle)
        let vc = storyboard.instantiateViewController(withIdentifier: "linkedFolders") as! LinkedFolderPreferenceViewController
        vc.headerText = headerText
        return vc
    }

    public override func viewDidLoad() {
        headerLabel.text = headerText!
        let linkedFolderBookmarks = ApplicationResourceBookmarks.shared()
        linkedFolderBookmarks.addUpdateHandler {
            self.updateLinkedFolderCache()
            self.tableView.reloadData()
        }
        self.updateLinkedFolderCache()
        tableView.isEditing = true
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonTapped(_:)))
    }

    // MARK: - API
    func updateLinkedFolderCache() {
        var allTheFolders: [cachedFolder] = []
        for location in ApplicationResourceBookmarks.shared().bookmarkedResourceLocations {
            let item = cachedFolder(url: location.folderURL, displayPath: self.generateDisplayName(fromURL: location.folderURL))
            allTheFolders.append(item)
        }
        linkedFolderCache = allTheFolders
        // sort alphabetically. Sorting by the entire path groups folders together by their source (all the icloud files end up together, etc) and then in display ABC order by containing folder. 
        linkedFolderCache.sort { (cachedFolder1, cachedFolder2) -> Bool in
            return cachedFolder1.url.path < cachedFolder2.url.path
        }
    }

    @IBAction func addLinkedFolder(_ sender: Any) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = true // Without this, we don't get a "Open" option
        picker.delegate = self

        picker.modalPresentationStyle = .overCurrentContext

        self.present(picker, animated: true)
    }

    @objc func doneButtonTapped(_ sender:Any) {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK:- UIDocumentPickerDelegate

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {

        for url in urls {
            // avoid dupes
            let alreadyLinked = linkedFolderCache.contains { element in
                return element.url == url
            }
            if (alreadyLinked == false) {
                do {
                    try ApplicationResourceBookmarks.shared().addResourceFolderURL(url)
                } catch let err {
                    print("Error adding template folder: \(err)")
                }
            }
        }
        updateLinkedFolderCache()
        tableView.reloadData()
    }

    // MARK:- UITableViewDataSource
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier: String = "linkedFolderCell"
        let cell: UITableViewCell
        if let dequeuedCell = tableView.dequeueReusableCell(withIdentifier: identifier) {
            cell = dequeuedCell
        } else {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        }

        let urlCacheItem = linkedFolderCache[indexPath.row]
        let linkedURL = urlCacheItem.url
        cell.textLabel?.text = linkedURL.lastPathComponent
        cell.detailTextLabel?.lineBreakMode = .byTruncatingMiddle
        cell.detailTextLabel?.text = urlCacheItem.displayPath

        return cell
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return linkedFolderCache.count
    }

    public override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        ApplicationResourceBookmarks.shared().removeResourceFolderURL(linkedFolderCache[indexPath.row].url)
        updateLinkedFolderCache()
        self.tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    //MARK: private
    func generateDisplayName(fromURL linkedURL: URL) -> String {
        var displayPath = linkedURL.path
        let components = linkedURL.pathComponents
        let separatorChar = " ▸ "
        var optionalPrefix = ""
        var concatPoint = 0
        var resourceKeys:Set<URLResourceKey> = Set()
        resourceKeys.insert(URLResourceKey.ubiquitousItemContainerDisplayNameKey)
        do {
            let urlResources = try linkedURL.resourceValues(forKeys: resourceKeys).allValues
            if let name = urlResources[URLResourceKey.ubiquitousItemContainerDisplayNameKey] {
                optionalPrefix = name as! String
            }
        } catch {
            print("\(error)")
        }

        if let fileProviderLocation = components.firstIndex(of: "File Provider Storage") {
            concatPoint = fileProviderLocation
        } else if let mobileDocsLocation = components.firstIndex(of:"Mobile Documents") {
            concatPoint = mobileDocsLocation + 1 // this is because the directory after Mobile Docs is the app ID (usually "com~apple~CloudDocs") which is also not relevant for the most part
            if optionalPrefix.isEmpty == true {
                optionalPrefix = components[concatPoint].replacingOccurrences(of: "~", with: ".")
            }
        }

        if concatPoint > 0 {
            // the +1 math here removes file provider as well as all the stuff before it.
            displayPath = components.dropFirst(concatPoint + 1).dropLast().reduce("", { (path: String, nextComponent: String) -> String in
                var newPath = path
                if newPath.isEmpty == false {
                    newPath.append(separatorChar)
                }
                newPath.append(nextComponent)
                return newPath
            })
        } else {
            // replace the separator char
            displayPath = displayPath.replacingOccurrences(of: "/", with: separatorChar)
        }
        
        if optionalPrefix.isEmpty == false {
            if displayPath.isEmpty {
                displayPath = optionalPrefix
            } else {
                displayPath = optionalPrefix + separatorChar + displayPath
            }
        }
        return displayPath
    }
}
