// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSRange-OFExtensions.h>

RCS_ID("$Id$")

NSRange OFRangeByRemovingRange(NSRange range, NSRange removedRange)
{
    OBPRECONDITION(range.location != NSNotFound);
    OBPRECONDITION(removedRange.location != NSNotFound);
    
    if (NSMaxRange(range) <= removedRange.location)
        return range; // entirely after us
    
    if (NSMaxRange(removedRange) <= range.location) {
        // Entirely before us
        range.location -= removedRange.length;
        return range;
    }

    // Overlap of some sort. The two interesting bits of the removed range are the amount before us (which will adjust our location) and the amount inside us, which will adjust our length.
    NSUInteger amountBefore;
    if (removedRange.location < range.location)
        amountBefore = range.location - removedRange.location;
    else
        amountBefore = 0;
    
    NSUInteger amountInside = MIN(NSMaxRange(range), NSMaxRange(removedRange)) - MAX(range.location, removedRange.location);
    
    range.location -= amountBefore;
    range.length -= amountInside;
    
    return range;
}

