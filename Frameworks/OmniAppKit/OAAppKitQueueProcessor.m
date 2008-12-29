// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAAppKitQueueProcessor.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSView-OAExtensions.h"

RCS_ID("$Id$")


@implementation OAAppKitQueueProcessor

// Give UI events priority over queued messages

#define CARBON_EVENTS_BUG_FIXED // This bug was in 10.0.x, let's see if it's fixed

- (BOOL)shouldProcessQueueEnd;
{
#ifdef CARBON_EVENTS_BUG_FIXED
    NSEvent *event;
#endif

    [NSView performDeferredScrolling];
    [[NSThread currentThread] yieldMainThreadLock];
#ifdef CARBON_EVENTS_BUG_FIXED
    // See Omni bug #1410:  This code apparently triggers a bug in Carbon events, causing a hang at:
    //
    // #0  0x737dacac in RetainEvent ()
    // #1  0x737dcb00 in _NotifyEventLoopObservers ()
    // #2  0x737e1178 in SendEventToEventTargetInternal ()
    // #3  0x737e10e8 in SendEventToEventTarget ()
    // #4  0x737e0f04 in ToolboxEventDispatcher ()
    // #5  0x737e0eac in HLTBEventDispatcher ()
    // #6  0x70d75c48 in _DPSNextEvent ()
    // #7  0x70d756e8 in -[NSApplication nextEventMatchingMask:untilDate:inMode:dequeue:] ()
    // #8  0x03264ea0 in -[OAAppKitQueueProcessor shouldProcessQueueEnd] (self=0x40b7b50, _cmd=0x1) at OAAppKitQueueProcessor.m:30

    event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:NO];
    if (event) {
        if (OFQueueProcessorDebug)
            NSLog(@"%@: breaking for event: %@", OBShortObjectDescription(self), event);
        return YES;
    }
#endif
    return NO;
}

@end

//
// Override key methods in OFRunLoopQueueProcessor to get the correct AppKit
// behaviour.
//
@implementation OFRunLoopQueueProcessor (OFAppkitQueueProcessor)

+ (NSArray *) mainThreadRunLoopModes;
{
    return [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode, nil];
}

+ (Class) mainThreadRunLoopProcessorClass;
{
    return [OAAppKitQueueProcessor class];
}

@end
