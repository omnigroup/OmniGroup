// Copyright 2012 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSScroller.h>
#import <OmniAppKit/OAVersion.h>

RCS_ID("$Id$")

/*
 * Workaround for <bug:///81753> (11467655: Layer-backed view override -resizeWithOldSuperviewSize: breaks NSScrollView) provided by an Apple engineer. Only needed on Lion; fixed on Mountain Lion.
 */

#if defined(MAC_OS_X_VERSION_MIN_REQUIRED) && MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_7

@implementation NSScroller (OAFixes)

static void (*original_drawKnob)(id self, SEL _cmd);

- (void)replacement_drawKnob;
{
    if ([self isEnabled])
        original_drawKnob(self, _cmd);
}

+ (void)performPosing;
{
    if (NSAppKitVersionNumber < OAAppKitVersionNumber10_8)
        original_drawKnob = (void (*)(id, SEL))OBReplaceMethodImplementationWithSelector(self, @selector(drawKnob), @selector(replacement_drawKnob));
}

@end

#endif
