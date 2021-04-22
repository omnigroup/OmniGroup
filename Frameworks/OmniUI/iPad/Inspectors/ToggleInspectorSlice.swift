// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

open class ToggleInspectorSlice : OUIInspectorSlice {

    @nonobjc public var toggleSwitch : UISwitch?
    @objc public var action : Selector?
    private var toggleLabel : UILabel?
    private static let kWidth : CGFloat = 200
    private static let kLabelToTogglePadding : CGFloat = 8

    // MARK: UIViewController
    open override func loadView() {

        let contentView = UIView()
        self.contentView = contentView
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let view = UIView()

        view.addSubview(contentView)
        contentView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        let insets = OUIInspectorSlice.sliceAlignmentInsets()

        // If a title is set on the view controller before the view is loaded, add a UILabel.
        // Not sure if it is worth allowing this to be set after the view is loaded.
        if let title = self.title {
            let label = UILabel()
            label.text = title
            label.font = OUIInspector.labelFont()
            label.textColor = OUIInspector.labelTextColor()
            label.isOpaque = false
            label.backgroundColor = nil
            label.translatesAutoresizingMaskIntoConstraints = false
            label.sizeToFit()

            contentView.addSubview(label)
            label.topAnchor.constraint(equalToSystemSpacingBelow: contentView.topAnchor, multiplier: 1).isActive = true
            contentView.bottomAnchor.constraint(equalToSystemSpacingBelow: label.bottomAnchor, multiplier: 1).isActive = true
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: insets.left).isActive = true

            self.toggleLabel = label
        }

        let toggle = UISwitch()
        self.toggleSwitch = toggle
        toggle.translatesAutoresizingMaskIntoConstraints = false

        // Accessibility
        toggle.isAccessibilityElement = true
        toggle.accessibilityLabel = self.title

        if let action = self.action {
            toggle.addTarget(self, action: action, for: .valueChanged)
        }

        contentView.addSubview(toggle)
        toggle.topAnchor.constraint(equalToSystemSpacingBelow: contentView.topAnchor, multiplier: 1).isActive = true
        contentView.bottomAnchor.constraint(equalToSystemSpacingBelow: toggle.bottomAnchor, multiplier: 1).isActive = true
        toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: insets.right * -1).isActive = true
        if (toggleLabel != nil) {
            toggle.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: (toggleLabel?.trailingAnchor)!, multiplier: 1).isActive = true
        }

        self.view = view
    }
}
