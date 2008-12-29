// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSImage-OIExtensions.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OWF/OWF.h>

RCS_ID("$Id$");

@implementation NSImage (OIExtensions)

// OWOptionalContent protocol

- (BOOL)shareable;
{
    return YES;
}

@end
