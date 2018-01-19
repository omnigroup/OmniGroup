// Copyright 2017 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


class OUITemplatePickerCell: UICollectionViewCell {

    @IBOutlet weak var preview: UIImageView!
    @IBOutlet weak var displayName: UILabel!
    @IBOutlet weak var imageHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var imageWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var displayNameHeightConstraint: NSLayoutConstraint!
    @objc var url: URL?

}
