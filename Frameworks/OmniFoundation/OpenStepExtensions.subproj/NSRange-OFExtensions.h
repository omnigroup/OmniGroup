// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSRange.h>

// Given an original range w/in some larger parent range, return an adjusted range for the removal of removedRange. If the removed range completely encloses the original range, the position of the result range will be correct for the amount of shifting needed and the length will be zero.
extern NSRange OFRangeByRemovingRange(NSRange range, NSRange removedRange);

NS_INLINE BOOL OFRangeContainsRange(NSRange container, NSRange subrange) {
    return ( container.location <= subrange.location ) && ( NSMaxRange(container) >= NSMaxRange(subrange) );
}
