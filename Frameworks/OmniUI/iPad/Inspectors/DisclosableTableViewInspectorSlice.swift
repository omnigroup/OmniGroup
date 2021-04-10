// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

open class DisclosableTableViewInspectorSlice: OUIAbstractTableViewInspectorSlice, UITableViewDataSource, UITableViewDelegate {

    // MARK: For Subclasses
    @objc /**REVIEW**/ open func numberOfStaticRows() -> Int {
        return 3
    }

    @objc /**REVIEW**/ open func disclosableStatePreferenceIdentifier() -> String? {
        return nil
    }

    @objc /**REVIEW**/ open func numberOfRowsInSection(_ tableView: UITableView, section: Int) -> Int {
        return 1
    }

    @objc /**REVIEW**/ open func cellForRowAt(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        return UITableViewCell()
    }

    @objc /**REVIEW**/ open func didSelectRowAt(_ tableView: UITableView, indexPath: IndexPath) {

    }

    @objc /**REVIEW**/ open func titleForHeader(_ tableView: UITableView, section: Int) -> String? {
        return nil
    }

    @objc /**REVIEW**/ open func titleForHideMoreButton() -> String {
        return NSLocalizedString("Hide More Rows", tableName: "OUIInspectors", bundle: Bundle.main, value: "Hide More Rows", comment: "hide more rows button title")
    }

    @objc /**REVIEW**/ open func titleForShowMoreButton() -> String {
        return NSLocalizedString("Show More Rows", tableName: "OUIInspectors", bundle: Bundle.main, value: "Show More Rows", comment: "show more rows button title")
    }

    // MARK: API

    /// Backing preference for persistent disclosed slices. Callers should not access this directly; instead, use one of the conveniences later.
    private static var disclosedSlicesPreference = OFPreference(forKey: "OUIInspectorDisclosedTableSlicesPreference", defaultValue: [:])

    @objc /**REVIEW**/ public func isSectionDisclosed(_ section: Int) -> Bool {
        guard let dict = DisclosableTableViewInspectorSlice.disclosedSlicesPreference.dictionaryValue as? [String:Bool] else {
            return false
        }
        guard let baseIdentifier = self.disclosableStatePreferenceIdentifier() else {
            return false
        }

        let identifier = "\(baseIdentifier)-\(section)"
        return dict[identifier] ?? false
    }

    fileprivate func toggleSectionDisclosed(_ section: Int, disclosed: Bool) {
        var dict: [String:Bool]
        if let stored = DisclosableTableViewInspectorSlice.disclosedSlicesPreference.dictionaryValue as? [String:Bool] {
            dict = stored
        }
        else {
            dict = DisclosableTableViewInspectorSlice.disclosedSlicesPreference.defaultObjectValue as! [String:Bool]
        }

        guard let baseIdentifier = self.disclosableStatePreferenceIdentifier() else {
            return
        }

        let identifier = "\(baseIdentifier)-\(section)"
        dict[identifier] = disclosed
        DisclosableTableViewInspectorSlice.disclosedSlicesPreference.dictionaryValue = dict
    }

    // MARK: UITableViewDataSource, UITableViewDelegate
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let totalNumberOfRows = self.numberOfRowsInSection(tableView, section: section)
        guard self.disclosableStatePreferenceIdentifier() != nil else {
            return totalNumberOfRows
        }
        if (totalNumberOfRows <= self.numberOfStaticRows()) {
            return totalNumberOfRows
        }
        if (self.isSectionDisclosed(section)) {
            return self.numberOfStaticRows() + 1
        } else {
            return totalNumberOfRows + 1
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard self.disclosableStatePreferenceIdentifier() != nil else {
            return self.cellForRowAt(tableView, indexPath: indexPath)
        }
        let numberOfStaticRows = self.numberOfStaticRows()
        if (indexPath.row == numberOfStaticRows) {
//            let button = UIButton(type: .system)
            // return disclosure button row
            let cell = OUIThemedTableViewCell.init(style: .default, reuseIdentifier: "disclose")
            if (self.isSectionDisclosed(indexPath.section)) {
                cell.textLabel?.text = self.titleForShowMoreButton()
            } else {
                cell.textLabel?.text = self.titleForHideMoreButton()
            }
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.textColor = tableView.tintColor
            cell.textLabel?.font = OUIInspector.labelFont()
            cell.selectionStyle = .none
            cell.backgroundColor = self.sliceBackgroundColor()
            cell.showsReorderControl = false
            return cell
        } else if (indexPath.row < self.numberOfStaticRows()) {
            return self.cellForRowAt(tableView, indexPath: indexPath)
        } else {
            // use row - 1 for indexPath to ignore the disclosure button
            let newIndexPath = IndexPath(row: indexPath.row - 1, section: indexPath.section)
            return self.cellForRowAt(tableView, indexPath: newIndexPath)
        }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard self.disclosableStatePreferenceIdentifier() != nil else {
            self.didSelectRowAt(tableView, indexPath: indexPath)
            return
        }
        let numberOfStaticRows = self.numberOfStaticRows()
        if (indexPath.row == numberOfStaticRows) {
            self.toggleSectionDisclosed(indexPath.section, disclosed: !self.isSectionDisclosed(indexPath.section))
            self.reloadTableAndResize()
        } else if (indexPath.row < self.numberOfStaticRows()) {
            return self.didSelectRowAt(tableView, indexPath: indexPath)
        } else {
            // use row - 1 for indexPath
            let newIndexPath = IndexPath(row: indexPath.row - 1, section: indexPath.section)
            self.didSelectRowAt(tableView, indexPath: newIndexPath)
        }
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if let title = self.titleForHeader(tableView, section: section) {
            let headerView = OUIAbstractTableViewInspectorSlice.sectionHeaderView(withLabelText: title, for: tableView)
            return headerView;
        }
        return nil
    }

    open func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 44.0
    }

}
