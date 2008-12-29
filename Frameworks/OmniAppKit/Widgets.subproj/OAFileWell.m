// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAFileWell.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

#import "OADragController.h"
#import "OAPasteboardHelper.h"

RCS_ID("$Id$")

@implementation OAFileWell

- (NSImage *)imageForFiles;
{
    if (![files count])
        return nil;

    return [[NSWorkspace sharedWorkspace] iconForFiles:files];
}

- (void)drawRect:(NSRect)aRect;
{
    NSImage *image;
    NSSize imageSize;
    NSPoint imagePoint;

//    NSDrawGrayBezel(_bounds, _bounds);

    if (!(image = [self imageForFiles]))
        return;
    imageSize = [image size];

    imagePoint.x = _bounds.origin.x + (_bounds.size.width - imageSize.width) / 2.0;
    imagePoint.y = _bounds.origin.y + (_bounds.size.height - imageSize.height) / 2.0;
    [image compositeToPoint:imagePoint operation:NSCompositeSourceOver];
}

- (BOOL)acceptsIncomingDrags;
{
    return acceptIncomingDrags;
}

- (NSArray *)files;
{
    return files;
}

- (void)setAcceptIncomingDrags:(BOOL)acceptIncoming;
{
    // UNDONE: not implemented to accept incoming yet
}

- (void)setFiles:(NSArray *)someFiles;
{
    [files autorelease];
    files = [someFiles retain];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event;
{
    OAPasteboardHelper *helper;
    NSImage *dragImage;
    NSPoint where, zero;

    if (!(dragImage = [self imageForFiles]))
        return;

    zero = NSMakePoint(0.0, 0.0);
    if ([event clickCount] > 1) {
        NSWorkspace *workspace;
        NSEnumerator *enumerator;
        NSString *path;

        workspace = [NSWorkspace sharedWorkspace];
        enumerator = [files objectEnumerator];
        while((path = [enumerator nextObject]))
            [workspace openFile:path fromImage:dragImage at:zero inView:self];
    }

    where = [self convertPoint:[event locationInWindow] fromView:nil];
    helper = [OAPasteboardHelper helperWithPasteboardNamed:NSDragPboard];
    [helper declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:self];
    [[OADragController sharedDragController] startDragFromView:self image:dragImage atPoint:where offset:zero event:event slideBack:NO pasteboardHelper:helper delegate:nil];
}

- (void)pasteboard:(NSPasteboard *)pasteboard provideDataForType:(NSString *)type;
{
    [pasteboard setPropertyList:files forType:type];
}

@end
