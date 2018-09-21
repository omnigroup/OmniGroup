// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import UIKit

open class OUIFloatingContentToolbar: UIToolbar {

    @IBOutlet public var contentView: UIView? {
        didSet {
            if let view = contentView {
                addSubview(view)
            }
        }
    }
    
    override open func layoutSubviews() {
        super.layoutSubviews()
        if let view = contentView {
            bringSubviewToFront(view)
        }
    }
}
