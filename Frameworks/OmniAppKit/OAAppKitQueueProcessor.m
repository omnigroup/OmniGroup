// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAAppKitQueueProcessor.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSView-OAExtensions.h>

RCS_ID("$Id$")


/*
 This class will be used for the main thread queue processor by OFRunLoopQueueProcessor if found.
 */
@implementation OAAppKitQueueProcessor

+ (NSArray *)mainThreadRunLoopModes;
{
    return [NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode, nil];
}

// Give UI events priority over queued messages

- (BOOL)shouldProcessQueueEnd;
{
    [NSView performDeferredScrolling];

    NSEvent *event = [[NSApplication sharedApplication] nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:NO];
    if (event) {
        if (OFQueueProcessorDebug)
            NSLog(@"%@: breaking for event: %@", OBShortObjectDescription(self), event);
        return YES;
    }

    return NO;
}

@end
