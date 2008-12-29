// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWSGMLAttribute.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@implementation OWSGMLAttribute

- initWithOffset:(unsigned int)anOffset;
{
    if (![super init])
        return nil;

    offset = anOffset;

    return self;
}

- (unsigned int)offset;
{
    return offset;
}

@end
