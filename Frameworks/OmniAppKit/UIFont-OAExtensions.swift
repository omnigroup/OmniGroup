// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

extension UIFont
{
    /*" Returns the PANOSE 1 information from the receiver as a string containing ten space-separated decimal numbers. Returns nil if it can't find a PANOSE 1 description of the font.

    Some PANOSE specification information can be found at http://www.panose.com/ProductsServices/pan1.aspx "*/

    @objc public func panose1String() -> String?
    {
        let ctFont = self as CTFont

        // The OS/2 table contains the PANOSE classification
        let os2Tab = CTFontCopyTable(ctFont, CTFontTableTag(kCTFontTableOS2), CTFontTableOptions())

        guard let os2Table = os2Tab else { return nil }

        // The PANOSE data is in bytes 32-42 of the table according to the TrueType and OpenType specs.
        if CFDataGetLength(os2Table) < 42 {
            // Truncated table?
            return nil
        }

        let panose = UnsafeMutablePointer<UInt8>.allocate(capacity: 10)
        CFDataGetBytes(os2Table, CFRangeMake(32, 10), panose)

        // Fonts with no PANOSE info but other OS/2 info will usually set this field to all 0s, which is a wildcard specification.
        var allZeros = true
        for i in 0...9 {
            if panose[i] != 0 {
                allZeros = false
                break;
            }
        }

        if allZeros == true {
            return nil
        }

        // Some sanity checks.
        if panose[0] > 20 {
            // Only 0 through 5 are actually defined by the PANOSE 1 specification.
            // It lists a few other categories but doesn't assign numbers to them. This check should allow for the unlikely event of future expansion of PANOSE 1, while still eliminating completely bogus data.
            return nil
        }

        // note the spaces between these.
        return "\(panose[0]) \(panose[1]) \(panose[2]) \(panose[3]) \(panose[4]) \(panose[5]) \(panose[6]) \(panose[7]) \(panose[8]) \(panose[9])"
    }
}
