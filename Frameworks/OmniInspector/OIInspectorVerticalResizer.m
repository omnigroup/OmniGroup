// Copyright 2002-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorVerticalResizer.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>

RCS_ID("$Id$")

@interface NSCursor (privateMethods)
+ (NSCursor *)_verticalResizeCursor;
@end

@implementation OIInspectorVerticalResizer
{
    CGFloat minimumSuperviewHeight;
}

- (void)viewDidMoveToSuperview;
{
    minimumSuperviewHeight = NSHeight([[self superview] frame]);
}

- (void)drawRect:(NSRect)rect 
{
    [super drawDividerInRect:self.bounds];
}

- (void)mouseDown:(NSEvent *)event;
{
    NSWindow *window = [self window];
    NSRect windowFrame = [window frame];
    CGFloat startingWindowTop = NSMaxY(windowFrame);
    CGFloat startingWindowHeight = NSHeight(windowFrame);
    CGFloat startingMouseY = [window convertPointToScreen:[event locationInWindow]].y;
    CGFloat verticalSpaceTakenNotBySuperview = startingWindowHeight - NSHeight([[self superview] frame]);
    
    while (1) {
        event = [[NSApplication sharedApplication] nextEventMatchingMask:NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:NO];
        if ([event type] == NSEventTypeLeftMouseUp)
            break;
           
        [[NSApplication sharedApplication] nextEventMatchingMask:NSEventMaskLeftMouseDragged untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
        CGFloat change = startingMouseY - [window convertPointToScreen:[event locationInWindow]].y;
        windowFrame.size.height = MAX(minimumSuperviewHeight + verticalSpaceTakenNotBySuperview, startingWindowHeight + change);
        windowFrame.origin.y = startingWindowTop - windowFrame.size.height;
        [window setFrame:windowFrame display:YES animate:NO];
    }
}

- (void)resetCursorRects;
{
    [self addCursorRect:self.bounds cursor:[NSCursor _verticalResizeCursor]];
}

@end
