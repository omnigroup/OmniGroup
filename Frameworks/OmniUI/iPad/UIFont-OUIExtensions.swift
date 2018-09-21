// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

extension UIFont {
    @nonobjc
    open class func preferredItalicFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        return self.__preferredItalicFont(forTextStyle: style.rawValue)
    }

    @nonobjc
    open class func preferredBoldFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        return self.__preferredBoldFont(forTextStyle: style.rawValue)
    }
}
