// Copyright 2005-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OITabCell.h>

#import <OmniBase/OmniBase.h>
#import <OmniAppKit/OmniAppKit.h>

RCS_ID("$Id$");

NSString *TabTitleDidChangeNotification = @"TabTitleDidChange";

@interface OITabCell (/*Private*/)
- (void)_drawImageInRect:(NSRect)cellFrame inView:(NSView *)controlView;
@end

@implementation OITabCell

- (NSColor *)highlightColorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    return [NSColor blueColor];
}

- (BOOL)duringMouseDown;
{
    return duringMouseDown;
}

- (void)saveState;
{
    duringMouseDown = YES;
    oldState = [self state];
}

- (void)clearState;
{
    duringMouseDown = NO;
}

- (BOOL)isPinned;
{
    return isPinned;
}

- (void)setIsPinned:(BOOL)newValue;
{
    // If we get pinned, make sure we are turned on
    if (newValue && ([self state] != NSOnState)) {
        [self setState:NSOnState];
    }
    
    isPinned = newValue;    // Set our state to On before turning on pinning, so that we're always in a consistent state (can't be pinned and not on)
}

- (void)setState:(NSInteger)value
{
    // If we're pinned, don't allow ourself to be turned off
    if (isPinned) {
        return;
    }
    
    [super setState:value];
    if (duringMouseDown)
        [[NSNotificationCenter defaultCenter] postNotificationName:TabTitleDidChangeNotification object:self];
}

- (BOOL)drawState
{
    return (duringMouseDown) ? oldState : [self state];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (![self image])
        return;
    
    // The highlight is now drawn by the matrix so that parts can be behind all cells and parts can be in front of all cells, etc.

    NSRect imageRect;
    imageRect.size = NSMakeSize(24,24);
    imageRect.origin.x = (CGFloat)(cellFrame.origin.x + floor((cellFrame.size.width - imageRect.size.width)/2));
    imageRect.origin.y = (CGFloat)(cellFrame.origin.y + floor((cellFrame.size.height - imageRect.size.height)/2));
    
    [self _drawImageInRect:imageRect inView:controlView];

    if (isPinned) {
        NSImage *image = [NSImage imageNamed:@"OITabLock.pdf" inBundle:OMNI_BUNDLE];
        NSSize imageSize = image.size;
        NSPoint point = NSMakePoint(NSMaxX(cellFrame) - imageSize.width - 3.0f, NSMaxY(cellFrame) - imageSize.height - 2.0f);
        [image drawFlippedInRect:(NSRect){point, imageSize} operation:NSCompositeSourceOver];
    }
    
    return;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OITabCell *copy = [super copyWithZone:zone];
    copy->_imageCell = [_imageCell copy];

    return copy;
}

#pragma mark - Private

- (void)_drawImageInRect:(NSRect)cellFrame inView:(NSView *)controlView;
{
    NSImage *image = [self image];
    NSRect imageRect = cellFrame;
    
    if (image) {
        imageRect.size = [image size];
        imageRect.origin.x = cellFrame.origin.x + rint((cellFrame.size.width - [image size].width)/2);
        imageRect.origin.y = cellFrame.origin.y + rint((cellFrame.size.height - [image size].height)/2);
    }
    if ([self state]) {
        [[[self image] imageByTintingWithColor:[NSColor colorWithCalibratedRed:47/255.f green:131/255.f blue:251/255.f alpha:1]] drawFlippedInRect:imageRect fromRect:NSMakeRect(0,0,imageRect.size.width,imageRect.size.height) operation:NSCompositeSourceOver fraction:1];
    } else if ([self isHighlighted]) {
        [[[self image] imageByTintingWithColor:[NSColor colorWithCalibratedRed:25/255.f green:65/255.f blue:149/255.f alpha:1]] drawFlippedInRect:imageRect fromRect:NSMakeRect(0,0,imageRect.size.width,imageRect.size.height) operation:NSCompositeSourceOver fraction:1];
    } else {
        [[self image] drawFlippedInRect:imageRect fromRect:NSMakeRect(0,0,imageRect.size.width,imageRect.size.height) operation:NSCompositeSourceOver fraction:1];
    }
}

@end
