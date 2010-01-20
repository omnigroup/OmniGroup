// Copyright 2000-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniFoundation/OFExtent.h>

RCS_ID("$Id$");

BOOL OFExtentsEqual(OFExtent a, OFExtent b)
{
    return a.location == b.location && a.length == b.length;
}

NSString *OFExtentToString(OFExtent r)
{
    return [NSString stringWithFormat:@"(%g, %g)", r.location, r.length];
}
