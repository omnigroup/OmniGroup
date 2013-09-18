// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIColor-OUIExtensions.h>

#import <OmniQuartz/OQColor-Archiving.h>

RCS_ID("$Id$");

@implementation UIColor (OUIExtensions)

+ (UIColor *)colorFromPropertyListRepresentation:(NSDictionary *)dict;
{
    return [[OQColor colorFromPropertyListRepresentation:dict] toColor];
}

@end
