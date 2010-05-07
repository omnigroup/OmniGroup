// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#if OUI_GESTURE_RECOGNIZER_DEBUG
@implementation UIGestureRecognizer (OUIExtensions)

static void (*original_setState)(UIGestureRecognizer *self, SEL _cmd, UIGestureRecognizerState state);

static NSString * const stateNames[] = {
    [UIGestureRecognizerStatePossible]  = @"    POSSIBLE",
    [UIGestureRecognizerStateBegan]     = @"       BEGAN",
    [UIGestureRecognizerStateChanged]   = @"     CHANGED",
    [UIGestureRecognizerStateEnded]     = @"       ENDED",
    [UIGestureRecognizerStateCancelled] = @"   CANCELLED",
    [UIGestureRecognizerStateFailed]    = @"      FAILED",
};

static void _replacement_setState(UIGestureRecognizer *self, SEL _cmd, UIGestureRecognizerState state)
{
    NSUInteger nameCount = sizeof(stateNames)/sizeof(stateNames[0]);    
    NSString *name = @"????";
    if (state < nameCount)
        name = stateNames[state];
    
    NSLog(@"%@ recognizer %@", name, [self shortDescription]);
    original_setState(self, _cmd, state);
}

static void (*original_setEnabled)(UIGestureRecognizer *self, SEL _cmd, BOOL enabled);

static void _replacement_setEnabled(UIGestureRecognizer *self, SEL _cmd, BOOL enabled)
{
    NSString *name;
    if (enabled)
        name = @" ++ENABLED++";
    else
        name = @"--DISABLED--";
        
    
    NSLog(@"%@ recognizer %@", name, [self shortDescription]);
    original_setEnabled(self, _cmd, enabled);
}

+ (void)enableStateChangeLogging;
{
    if (original_setState)
        return;
    original_setState = (typeof(original_setState))OBReplaceMethodImplementation([UIGestureRecognizer class], @selector(setState:), (IMP)_replacement_setState);
    original_setEnabled = (typeof(original_setEnabled))OBReplaceMethodImplementation([UIGestureRecognizer class], @selector(setEnabled:), (IMP)_replacement_setEnabled);
}

@end
#endif
