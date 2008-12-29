// Copyright 2002-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorVerticalResizer.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OIInspectorVerticalResizer.m 72316 2006-02-07 18:59:27Z bungi $")

@interface NSCursor (privateMethods)
+ (NSCursor *)_verticalResizeCursor;
@end

@implementation OIInspectorVerticalResizer

- initWithFrame:(NSRect)aFrame;
{
    [super initWithFrame:aFrame];
//    [self setIsPaneSplitter:YES];
    return self;
}

- (void)viewDidMoveToSuperview;
{
    minimumSuperviewHeight = NSHeight([[self superview] frame]);
}

- (void)drawRect:(NSRect)rect 
{
    [super drawDividerInRect:_bounds];
}

- (void)mouseDown:(NSEvent *)event;
{
    NSWindow *window = [self window];
    NSRect windowFrame = [window frame];
    float startingWindowTop = NSMaxY(windowFrame);
    float startingWindowHeight = NSHeight(windowFrame);
    float startingMouseY = [window convertBaseToScreen:[event locationInWindow]].y;
    float verticalSpaceTakenNotBySuperview = startingWindowHeight - NSHeight([[self superview] frame]);
    
    while (1) {
        float change;
        
        event = [NSApp nextEventMatchingMask:NSLeftMouseDraggedMask|NSLeftMouseUpMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:NO];

        if ([event type] == NSLeftMouseUp)
            break;
           
        [NSApp nextEventMatchingMask:NSLeftMouseDraggedMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
        change = startingMouseY - [window convertBaseToScreen:[event locationInWindow]].y;
        windowFrame.size.height = MAX(minimumSuperviewHeight + verticalSpaceTakenNotBySuperview, startingWindowHeight + change);
        windowFrame.origin.y = startingWindowTop - windowFrame.size.height;
        [window setFrame:windowFrame display:YES animate:NO];
    }
}

- (void)resetCursorRects;
{
    [self addCursorRect:_bounds cursor:[NSCursor _verticalResizeCursor]];
}

@end
