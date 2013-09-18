// Copyright 1997-2005, 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Cocoa/Cocoa.h>

#import <OmniAppKit/NSBundle-OAExtensions.h>

RCS_ID("$Id$")

@implementation NSBundle (OAExtensions)

+ (NSBundle *)OmniAppKit;
{
    return [self bundleWithIdentifier:@"com.omnigroup.OmniAppKit"];
}

@end

