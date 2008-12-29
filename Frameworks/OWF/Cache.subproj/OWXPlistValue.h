// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniIndex/OXValueType.h>

@interface OWXPlistValue : OXValueType
{
    CFPropertyListFormat writeFormat;
    
    // Cache of the last value passed to -byteSizeOfValue:
    NSObject *recentValue;
    CFDataRef recentData;
}

// API

@end
