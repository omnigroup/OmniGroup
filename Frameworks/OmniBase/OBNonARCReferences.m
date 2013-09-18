// Copyright 1997-2010, 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

void OBStrongRetain(id object)
{
    [object retain];
}

void OBStrongRelease(id object)
{
    [object release];
}

void OBRetainAutorelease(id object)
{
    [[object retain] autorelease];
}

void OBAutorelease(id object)
{
    [object autorelease];
}
