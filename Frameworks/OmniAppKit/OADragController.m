// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OADragController.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/OAPasteboardHelper.h>

RCS_ID("$Id$")

@interface OADragController (Private)
- (void)controllerWillTerminate:(OFController *)controller;
- (void)flushPasteboard;
@end

@implementation OADragController

static OADragController *sharedDragController;

+ (void)initialize;
{
    OBINITIALIZE;
    sharedDragController = [[self alloc] init];
}

+ (OADragController *)sharedDragController;
{
    return sharedDragController;
}

//

- init;
{
    draggingPasteboard = [[NSPasteboard pasteboardWithName:NSDragPboard] retain];
    [[OFController sharedController] addObserver:self];
    return self;
}

// Starting the drag

- (void)startDragFromView:(NSView *)view image:(NSImage *)image atPoint:(NSPoint)location offset:(NSPoint)offset event:(NSEvent *)event slideBack:(BOOL)slideBack pasteboardHelper:(OAPasteboardHelper *)newPasteboardHelper delegate:newDelegate;
{
    if (draggingFromView != view) {
        [draggingFromView release];
        draggingFromView = [view retain];
    }
    if (pasteboardHelper != newPasteboardHelper) {
        [pasteboardHelper absolvePasteboardResponsibility];
        [pasteboardHelper release];
        pasteboardHelper = [newPasteboardHelper retain];
    }
    if (delegate != newDelegate) {
        [delegate release];
        delegate = [newDelegate retain];
    }

    [draggingFromView dragImage:image at:location offset:NSMakeSize(offset.x, offset.y) event:event pasteboard:draggingPasteboard source:self slideBack:slideBack];
}

- (NSView *)view;
{
    return draggingFromView;
}

// NSDraggingSource informal protocol

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    return NSDragOperationAll;
}

- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint deposited:(BOOL)didDeposit;
{
    if ([delegate respondsToSelector:@selector(draggedImage:endedAt:deposited:)])
	[delegate draggedImage:image endedAt:screenPoint deposited:didDeposit];

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushPasteboard) object:nil];
    [self performSelector:@selector(flushPasteboard) withObject:nil afterDelay:30.0];
}

- (BOOL)ignoreModifierKeysWhileDragging;
{
    return YES;
}

// OFWeakRetain protocol

OFWeakRetainConcreteImplementation_NULL_IMPLEMENTATION

@end

@implementation OADragController (Private)

// Notifications

- (void)controllerWillTerminate:(OFController *)controller;
{
    [self flushPasteboard];
}

// Called 30 seconds after a drag completes

- (void)flushPasteboard;
{
    [pasteboardHelper absolvePasteboardResponsibility];
    [pasteboardHelper autorelease];
    pasteboardHelper = nil;
    [draggingFromView autorelease];
    draggingFromView = nil;
    [delegate autorelease];
    delegate = nil;
}

@end
