// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

/// Decribes a way to apply a decoration to a view
protocol PaneDecoration {
    func apply(toView view: UIView)
}

// MARK: -

struct ShowDivider: PaneDecoration {
    func apply(toView view: UIView) {
        view.isHidden = false
    }
}

// MARK: -

struct HideDivider: PaneDecoration {
    func apply(toView view: UIView) {
        view.isHidden = true
    }
}

// MARK: -

struct AddShadow: PaneDecoration {
    func apply(toView view: UIView) {
        let shadowOpacity: Float
        let shadowColor: UIColor
        
        switch view.traitCollection.userInterfaceStyle {
        case .dark:
            shadowOpacity = 0
            shadowColor = UIColor.clear
            
        case .light, .unspecified:
            fallthrough
            
        @unknown default:
            shadowOpacity = 0.4
            shadowColor = UIColor.black
        }

        let layer = view.layer
        layer.shadowColor = shadowColor.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = 2.5
        layer.shadowOpacity = shadowOpacity

        view.clipsToBounds = false
    }
}

// MARK: -

struct RemoveShadow: PaneDecoration {
   func apply(toView view: UIView) {
        view.clipsToBounds = true
        view.layer.shadowOpacity = 0.0
    }
}
