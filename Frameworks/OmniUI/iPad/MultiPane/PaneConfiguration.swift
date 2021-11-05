// Copyright 2016-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

protocol PaneConfiguration {
    var location: MultiPaneLocation { get }
    var widthPriority: UILayoutPriority { get }
    var preferredMinimumWidth: CGFloat { get set }
    var heightPriority: UILayoutPriority { get }
    
    var canBePinned: Bool { get set }
    var isPinned: Bool { get set }
    
    func size(withEnvironment env: PaneEnvironment) -> CGSize
    func configure(withViewController viewController: UIViewController)
    func decorations(forEnvironment environment: PaneEnvironment) -> [PaneDecoration]
    func apply(decoration: PaneDecoration, toViewController viewController: UIViewController)
}

extension PaneConfiguration {
    var canBePinned: Bool {
        return false
    }

    var widthPriority: UILayoutPriority {
        return UILayoutPriority(rawValue: 800.0)
    }
    var heightPriority: UILayoutPriority {
        return UILayoutPriority(rawValue: 800.0)
    }
}

protocol Sidebar: PaneConfiguration {
    var wantsDivider: Bool { get }
    var wantsMoveableDivider: Bool { get set }
    var defaultWidth: CGFloat { get }
    var divider: PaneDividerView? { get set }
}

extension Sidebar {
    var defaultWidth: CGFloat {
        return 320.0
    }
    
    var wantsDivider: Bool {
        return true
    }
    
    func size(withEnvironment env: PaneEnvironment) -> CGSize {
        if env is CompactEnvironment {
            return env.containerSize
        }
        
        let height = env.containerSize.height
        if self.preferredMinimumWidth > 0.0 {
            return CGSize(width: self.preferredMinimumWidth, height: height)
        }
        return CGSize(width: self.defaultWidth, height: height)
    }
    
    func decorations(forEnvironment environment: PaneEnvironment) -> [PaneDecoration] {
        if environment is RegularEnvironment {
            return (environment.presentationMode == .overlaid) ? [AddShadow()] : [ShowDivider(), RemoveShadow()]
        }
        
        // no decorations for sidebars when compact.
        return [RemoveShadow(), HideDivider()]
    }
    
    func apply(decoration: PaneDecoration, toViewController viewController: UIViewController) {
        if decoration is ShowDivider || decoration is HideDivider {
            if let divider = self.divider {
                decoration.apply(toView: divider)
            }
        } else {
            decoration.apply(toView: viewController.view)
        }
    }
}


class Left: Sidebar {
    var location: MultiPaneLocation {
        return .left
    }
    
    var preferredMinimumWidth: CGFloat = 320.0
    
    var isPinned: Bool = false
    var canBePinned: Bool = false
    
    var wantsMoveableDivider: Bool = false
    var divider: PaneDividerView?
    
    func configure(withViewController viewController: UIViewController) {
        guard self.wantsDivider else { return }
        guard let dividerView = self.divider else {
            assertionFailure("failed to configure the divider on the sidebar")
            return
        }
        
        guard let view = viewController.view else {
            assertionFailure("The view controller's view is nil/not loaded, we can't continue")
            return
        }
        
        if dividerView.superview == nil {
            view.addSubview(dividerView)
        }
        
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        dividerView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        dividerView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        self.divider = dividerView
    }
}

class Right: Sidebar {
    var location: MultiPaneLocation {
        return .right
    }
    
    var preferredMinimumWidth: CGFloat = 320.0
    
    var canBePinned: Bool = true
    var isPinned: Bool = false
    
    var wantsMoveableDivider: Bool = false
    var divider: PaneDividerView?
    
    func configure(withViewController viewController: UIViewController) {
        guard self.wantsDivider else { return }
        guard let dividerView = self.divider else {
            assertionFailure("failed to configure the divider on the sidebar")
            return
        }
        
        guard let view = viewController.view else {
            assertionFailure("The view controller's view is nil/not loaded, we can't continue")
            return
        }
        
        if dividerView.superview == nil {
            view.addSubview(dividerView)
        }
        
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        dividerView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        dividerView.centerXAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        self.divider = dividerView
    }
}

class ContentPane: PaneConfiguration {
    var location: MultiPaneLocation {
        return .center
    }
    
    var isPinned: Bool = false
    
    /// This property should stay false. Content panes can't be pinned
    var canBePinned: Bool = false
    
    var widthPriority: UILayoutPriority {
        return UILayoutPriority(rawValue: 751.0)
    }
    
    var preferredMinimumWidth: CGFloat = 520.0
    
    func size(withEnvironment env: PaneEnvironment) -> CGSize {
        return env.containerSize
    }
    
    func configure(withViewController viewController: UIViewController) { /* no-op */ }
    
    func decorations(forEnvironment environment: PaneEnvironment) -> [PaneDecoration] {
        return []
    }
    
    func apply(decoration: PaneDecoration, toViewController viewController: UIViewController) {
        decoration.apply(toView: viewController.view)
    }
}
