// Copyright 2006-2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "CIColor-OQExtensions.h"

RCS_ID("$Id$");

@implementation CIColor (OQExtensions)

#ifdef DEBUG

static id (*original_initWithColor)(id self, SEL _cmd, NSColor *color) = NULL;

+ (void)didLoad;
{
    original_initWithColor = (void *)OBReplaceMethodImplementationWithSelectorOnClass(self, @selector(initWithColor:), self, @selector(replacement_initWithColor:));
}

// <bug://28581> If you pass NSCalibratedWhiteColorSpace, you get funky colors (Radar 4561496).
- replacement_initWithColor:(NSColor *)color;
{
    // In the past, -initWithColor: didn't call -colorUsingColorSpaceName:NSCalibratedRGBColorSpace when converting to a CIColor, but now it does.  Just make sure this will work.
    OBPRECONDITION([color colorUsingColorSpaceName:NSCalibratedRGBColorSpace] != nil);

    return original_initWithColor(self, _cmd, color);
}

#endif

+ (CIColor *)clearColor;
{
    static CIColor *clear = nil;
    if (!clear)
	clear = [[CIColor colorWithRed:0 green:0 blue:0 alpha:0] retain];
    return clear;
}

@end
