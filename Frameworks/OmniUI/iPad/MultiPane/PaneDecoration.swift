// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

/// decribes a way to apply a decoration to a view
protocol PaneDecoration {
    func apply(toView view: UIView)
}

struct ShowDivider: PaneDecoration {
    func apply(toView view: UIView) {
        view.isHidden = false
    }
}

struct HideDivider: PaneDecoration {
    func apply(toView view: UIView) {
        view.isHidden = true
    }
}

struct AddShadow: PaneDecoration {
   func apply(toView view: UIView) {
        let layer = view.layer
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 1.0, height: 0.0)
        layer.shadowRadius = 6.0
        layer.shadowOpacity = 0.5
        view.clipsToBounds = false
    }
}

struct RemoveShadow: PaneDecoration {
   func apply(toView view: UIView) {
        view.clipsToBounds = true
        view.layer.shadowOpacity = 0.0
    }
}
