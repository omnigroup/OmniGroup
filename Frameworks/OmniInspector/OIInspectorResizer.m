// Copyright 2002-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorResizer.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>

RCS_ID("$Id$")

@implementation OIInspectorResizer

static NSImage *resizerImage = nil;

+ (void)initialize;
{
    OBINITIALIZE;

    resizerImage = [NSImage imageNamed:@"OIWindowResize" inBundle:[OIInspectorResizer bundle]];
    OBASSERT(resizerImage);
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
{
    return YES;
}

- (void)drawRect:(NSRect)rect;
{
    [resizerImage drawAtPoint:self.bounds.origin fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
}

- (void)mouseDown:(NSEvent *)event;
{
    NSWindow *window = [self window];
    NSRect windowFrame = [window frame];
    NSPoint topLeft = NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame));
    NSSize startingSize = windowFrame.size;
    NSPoint startingMouse = [window convertPointToScreen:[event locationInWindow]];

    if ([window respondsToSelector:@selector(resizerWillBeginResizing:)]) {
        [window resizerWillBeginResizing:self];
    }
    while (1) {
        NSPoint point, change;
        
        event = [[NSApplication sharedApplication] nextEventMatchingMask:NSLeftMouseDraggedMask|NSLeftMouseUpMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:NO];

        if ([event type] == NSLeftMouseUp)
            break;
           
        [[NSApplication sharedApplication] nextEventMatchingMask:NSLeftMouseDraggedMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
        point = [window convertPointToScreen:[event locationInWindow]];
        change.x = startingMouse.x - point.x;
        change.y = startingMouse.y - point.y;
        windowFrame.size.height = startingSize.height + change.y;
        windowFrame.size.width = startingSize.width - change.x;
        windowFrame.origin.y = topLeft.y - windowFrame.size.height;
        // Note that the views will not think they are inLiveResize because we are managing the resizing, not the window
        [window setFrame:windowFrame display:YES animate:NO];
    }
    if ([window respondsToSelector:@selector(resizerDidFinishResizing:)]) {
        [window resizerDidFinishResizing:self];
    }
}

@end
