// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import UIKit

// MARK: - DisclosableSliceGroup
open class DisclosableSliceGroup: NSObject {
    /// Identifier to use when saving to preferences
    let identifier: String

    /// Header title to display if defined
    let headerSlice: DiscloseGroupHeaderSlice?

    /// Slices that should always be shown.
    let staticSlices: [OUIInspectorSlice]


    /// Slices that will be hidden/shown when the buttonSlice's button is tapped.
    let disclosableSlices: [OUIInspectorSlice]


    /// Computed property that returns groupSeparatorSlice, staticSlices, buttonSlice, and disclosableSlices.
    public var allSlices: [OUIInspectorSlice] {
        var all = [OUIInspectorSlice]()
        all.append(groupSeparatorSlice)
        if (headerSlice != nil) {
            all.append(headerSlice!)
        }
        all.append(contentsOf: staticSlices)
        all.append(buttonSlice)
        all.append(contentsOf: disclosableSlices)
        return all
    }

    let groupSeparatorSlice: DiscloseGroupSeparatorSlice
    /// Slice that vends a button whos action will alert the DisclosableSliceGroup.delegate via the didTapSliceGroupButton(_:) method.
    let buttonSlice: DiscloseButtonSlice
    public weak var delegate: DisclosableSliceGroupDelegate?

    /// Title to show while in the undisclosed state. (Ex: "Show ...")
    public var undisclosedTitle: String?

    /// Title to show while in the disclosed state. (Ex: "Hide ...")
    public var disclosedTitle: String?

    public init(identifier: String, headerTitle: String?, staticSlices: [OUIInspectorSlice], disclosableSlices: [OUIInspectorSlice]) {
        self.identifier = identifier
        groupSeparatorSlice = DiscloseGroupSeparatorSlice(nibName: nil, bundle: nil)

        if (headerTitle != nil) {
            headerSlice = DiscloseGroupHeaderSlice(headerTitle: headerTitle!)
            groupSeparatorSlice.separatorHeight = 12.0
        } else {
            headerSlice = nil
        }
        self.staticSlices = staticSlices
        self.disclosableSlices = disclosableSlices
        buttonSlice = DiscloseButtonSlice(nibName: nil, bundle: nil)

        super.init()

        groupSeparatorSlice.delegate = self
        headerSlice?.delegate = self
        buttonSlice.delegate = self
        buttonSlice.button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
    }

    public convenience init(identifier: String, staticSlices: [OUIInspectorSlice], disclosableSlices: [OUIInspectorSlice]) {
        self.init(identifier: identifier, headerTitle: nil, staticSlices: staticSlices, disclosableSlices: disclosableSlices)
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        if let delegate = self.delegate {
            delegate.didTapSliceGroupButton(self)
            // We don't need to update the button title after being tapped because all slices are removed when the slices property on the pane is set, even if the slices property contains slices that will be added. Because of this we know that viewWillAppear will get called on the buttonSlice which will call updateInterface(fromInspectedObjects:) on itself.
        }
    }

    fileprivate func updateButton(isUndisclosed: Bool) {
        let title = isUndisclosed ? undisclosedTitle : disclosedTitle
        buttonSlice.button.setTitle(title, for: .normal)
    }
}

extension DisclosableSliceGroup : DiscloseButtonSliceDelegate {
    func isButtonSliceAppropriate(buttonSlice: DiscloseButtonSlice, inspectedObject: Any!) -> Bool {
        guard disclosableSlices.count > 0 else { return false }

        var shouldBeEnabled = false
        for disclosableSlice in disclosableSlices {
            let oldContainingPane = disclosableSlice.containingPane
            disclosableSlice.containingPane = buttonSlice.containingPane
            if disclosableSlice.isAppropriate(forInspectedObject: inspectedObject) {
                shouldBeEnabled = true
                break
            }
            disclosableSlice.containingPane = oldContainingPane
        }
        buttonSlice.button.isEnabled = shouldBeEnabled

        return shouldBeEnabled
    }

    func updateInterface(of slice: DiscloseButtonSlice, fromInspectedObjects reason: OUIInspectorUpdateReason) {
        if let delegate = delegate {
            let isUndisclosed = delegate.sliceGroupIsUndisclosed(self)
            updateButton(isUndisclosed: isUndisclosed)
        }
    }
}

extension DisclosableSliceGroup : DiscloseHeaderSliceDelegate {
    func isAppropriate(_ slice: DiscloseGroupHeaderSlice, inspectedObjects: [Any]!) -> Bool {
        guard staticSlices.count > 0 || disclosableSlices.count > 0 else { return false }

        var shouldBeEnabled = false
        for disclosableSlice in disclosableSlices {
            let oldContainingPane = disclosableSlice.containingPane
            disclosableSlice.containingPane = buttonSlice.containingPane
            if disclosableSlice.isAppropriate(forInspectedObjects: inspectedObjects) {
                shouldBeEnabled = true
                break
            }
            disclosableSlice.containingPane = oldContainingPane
        }

        var isAppropriate = false
        for staticSlice in staticSlices {
            if staticSlice.isAppropriate(forInspectedObjects: inspectedObjects) {
                isAppropriate = true
                break
            }
        }
        return isAppropriate || shouldBeEnabled
    }
}

extension DisclosableSliceGroup : DiscloseGroupSeparatorSliceDelegate {
    func isSliceAppropriate(_ slice: OUIInspectorSlice, inspectedObject: Any!) -> Bool {
        var isAppropriate = false
        for staticSlice in staticSlices {
            if staticSlice.isAppropriate(forInspectedObject: inspectedObject) {
                isAppropriate = true
                break
            }
        }

        return isAppropriate
    }
}

@objc public protocol DisclosableSliceGroupDelegate {
    func didTapSliceGroupButton(_ disclosableSliceGroup: DisclosableSliceGroup)
    func sliceGroupIsUndisclosed(_ disclosableSliceGroup: DisclosableSliceGroup) -> Bool
}

// MARK: - DiscloseButtonSlice

/// This was designed and created to work with DisclosableSliceGroup. It has only been tested in that context. If you need a generic button in a slice, this may or may not work for you. It's certainly an odd pattern compared to how the other slices work.
class DiscloseButtonSlice: OUIInspectorSlice {
    let button = UIButton(type: .system)
    weak var delegate: DiscloseButtonSliceDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        view.heightAnchor.constraint(equalToConstant: 44).isActive = true

        button.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        button.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateInterface(fromInspectedObjects: .default)
    }

    override func isAppropriate(forInspectedObject object: Any!) -> Bool {
        guard let delegate = delegate else { return true }

        return delegate.isButtonSliceAppropriate(buttonSlice: self, inspectedObject: object)
    }

    override func updateInterface(fromInspectedObjects reason: OUIInspectorUpdateReason) {
        super.updateInterface(fromInspectedObjects: reason)

        if let delegate = delegate {
            delegate.updateInterface(of: self, fromInspectedObjects: reason)
        }
    }
}

@objc protocol DiscloseButtonSliceDelegate {
    func isButtonSliceAppropriate(buttonSlice: DiscloseButtonSlice, inspectedObject: Any!) -> Bool
    func updateInterface(of slice: DiscloseButtonSlice, fromInspectedObjects reason: OUIInspectorUpdateReason)
}

// MARK: - DiscloseGroupHeaderSlice
class DiscloseGroupHeaderSlice: OUIInspectorSlice {
    let headerTitle: String
    weak var delegate: DiscloseHeaderSliceDelegate?

    public init(headerTitle: String) {
        self.headerTitle = headerTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        self.headerTitle = ""
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let titleLabel = OUIAbstractTableViewInspectorSlice.headerLabelWiithText(self.headerTitle) else {
            return
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let wrapperView = UIView()
        wrapperView.translatesAutoresizingMaskIntoConstraints = false
        wrapperView.backgroundColor = UIColor.groupTableViewBackground

        view.addSubview(wrapperView)
        wrapperView.addSubview(titleLabel)

        view.heightAnchor.constraint(equalToConstant: 32).isActive = true

        wrapperView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        wrapperView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        wrapperView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        wrapperView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        titleLabel.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor, constant: 15).isActive = true
        titleLabel.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor).isActive = true
        titleLabel.topAnchor.constraint(equalTo: wrapperView.topAnchor).isActive = true
        titleLabel.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor).isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateInterface(fromInspectedObjects: .default)
    }

    override func isAppropriate(forInspectedObjects objects: [Any]!) -> Bool {
        guard let delegate = delegate else { return true }

        return delegate.isAppropriate(self, inspectedObjects: objects)
    }

}

@objc protocol DiscloseHeaderSliceDelegate {
    func isAppropriate(_ slice: DiscloseGroupHeaderSlice, inspectedObjects: [Any]!) -> Bool
}


// MARK: - DiscloseGroupSeparatorSlice

class DiscloseGroupSeparatorSlice: OUIInspectorSlice {
    weak var delegate: DiscloseGroupSeparatorSliceDelegate?
    public var separatorHeight: CGFloat = 16.0

    override func viewDidLoad() {
        super.viewDidLoad()

        view.heightAnchor.constraint(equalToConstant: separatorHeight).isActive = true
    }

    override func isAppropriate(forInspectedObject object: Any!) -> Bool {
        guard let delegate = delegate else { return true }

        return delegate.isSliceAppropriate(self, inspectedObject: object)
    }

    override func sliceBackgroundColor() -> UIColor! {
        return UIColor.clear
    }

}

protocol DiscloseGroupSeparatorSliceDelegate : class {
    func isSliceAppropriate(_ slice: OUIInspectorSlice, inspectedObject: Any!) -> Bool
}
