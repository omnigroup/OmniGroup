// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "UIWindow-OUIExtensions.h"

#import <OmniFoundation/OFBacktrace.h>

RCS_ID("$Id$");

@implementation UIWindow (OUIExtensions)

#if 0 && defined(DEBUG)

static void (*_original_setFirstResponder)(UIWindow *self, SEL _cmd, UIResponder *responder) = NULL;

// NOTE: This doesn't always get called. For example, when an alert is presented, we'll lose our first responder.
static void _replacement_setFirstResponder(UIWindow *self, SEL _cmd, UIResponder *responder)
{
    NSLog(@"Window %@ first responder %@ at:\n%@\n", OBShortObjectDescription(self), OBShortObjectDescription(responder), OFCopySymbolicBacktrace());
    _original_setFirstResponder(self, _cmd, responder);
}

static void OUIWindowPerformPosing(void) __attribute__((constructor));
static void OUIWindowPerformPosing(void)
{
    Class cls = NSClassFromString(@"UIWindow");
    _original_setFirstResponder = (typeof(_original_setFirstResponder))OBReplaceMethodImplementation(cls, @selector(_setFirstResponder:), (IMP)_replacement_setFirstResponder);
}

#endif

@end
