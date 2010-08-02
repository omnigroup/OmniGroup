// Copyright 2006-2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "CIColor-OQExtensions.h"

RCS_ID("$Id$");

@implementation CIColor (OQExtensions)

+ (CIColor *)clearColor;
{
    static CIColor *clear = nil;
    if (!clear)
	clear = [[CIColor colorWithRed:0 green:0 blue:0 alpha:0] retain];
    return clear;
}

@end
