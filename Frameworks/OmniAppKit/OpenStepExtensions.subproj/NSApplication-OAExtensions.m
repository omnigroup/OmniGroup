// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSApplication-OAExtensions.h>
#import <OmniBase/OmniBase.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$")

@implementation NSApplication (OAExtensions)

- (BOOL)useColor;
{
    return NSNumberOfColorComponents (
	    NSColorSpaceFromDepth([NSWindow defaultDepthLimit])) > 1;
}

- (NSEvent *)peekEvent;
{
    NSString *mode;
    
    if (!(mode = [[NSRunLoop currentRunLoop] currentMode]))
        // NSApplication crashes on nil modes in DP4
        mode = NSDefaultRunLoopMode;

    // We get system-defined events quite frequently, so ignore them.
    return [self nextEventMatchingMask:(~NSEventTypeSystemDefined) untilDate:[NSDate distantPast] inMode:mode dequeue:NO];
}

- (void)wakeEventLoop;
{
    // Post a user defined event to wake up the event loop (which then will automatically close the top level undo groups if necessary, etc.)
    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:[NSDate timeIntervalSinceReferenceDate] windowNumber:0 context:NULL subtype:-1 data1:0 data2:0];
    [[NSApplication sharedApplication] postEvent:event atStart:NO];
}

- (void)flushTopLevelAutoreleasePool;
{
    // In some cases, the top-level pool doesn't get flushed as soon as we'd like (for example if the app is in the background and responding to AppleEvents, reloading documents for coordinated writes to documents, etc.
    [self wakeEventLoop];
}

@end
