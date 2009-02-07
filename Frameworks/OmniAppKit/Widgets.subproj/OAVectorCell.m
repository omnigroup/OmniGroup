// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAVectorCell.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

static inline float _scaling(NSRect frame)
{
    return frame.size.width/84;
}

@implementation OAVectorCell

- (void)dealloc;
{
    [_imageCell release];
    [super dealloc];
}

#pragma mark NSCell subclass

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
{
    if (_imageCell == nil) {
        _imageCell = [[NSImageCell alloc] initImageCell:nil];
        [_imageCell setImageFrameStyle:NSImageFrameGrayBezel];
    }
    [_imageCell setEnabled:[self isEnabled]];
    [_imageCell drawWithFrame:cellFrame inView:controlView];
    [super drawWithFrame:cellFrame inView:controlView];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
{
    float inset = 8 * _scaling(cellFrame);

    cellFrame = NSInsetRect(cellFrame, inset, inset);
    //        cursorWidth = (bounds.size.width - 20) * scaling;
    int cursorWidth = inset * 2;

    OFPoint *pointValue = [self objectValue];
    NSPoint point = pointValue ? [pointValue point] : NSZeroPoint;
    
    NSPoint center;
    BOOL enabled = [self isEnabled];
    if (enabled && !_isMultiple) {
        // Draw crosshair
        center.x = NSMidX(cellFrame) + point.x;
        center.y = NSMidY(cellFrame) + point.y;
        NSRect horizontalLine = NSMakeRect(center.x - cursorWidth/2, center.y, cursorWidth, 1);
        NSRect verticalLine = NSMakeRect(center.x, center.y - cursorWidth/2, 1, cursorWidth);

        [[NSColor grayColor] set];
        NSRectFill(NSInsetRect(horizontalLine, -0.5, -0.5)); // draw it fuzzy so it looks like a real shadow
        NSRectFill(NSInsetRect(verticalLine, -0.5, -0.5));

        NSRectFill(horizontalLine);
        NSRectFill(verticalLine);
    }

    // Draw axes
    center.x = NSMidX(cellFrame);
    center.y = NSMidY(cellFrame);
    if (enabled)
        [[NSColor blackColor] set];
    else
        [[NSColor grayColor] set];
    NSRectFill(NSMakeRect(center.x - cursorWidth/2, center.y, cursorWidth, 1));
    NSRectFill(NSMakeRect(center.x, center.y - cursorWidth/2, 1, cursorWidth));
}

- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag;
{
    if (![self isEnabled])
        return NO;

    float   inset     = _scaling(cellFrame) * 8;
    NSRect  bounds    = NSInsetRect(cellFrame, inset , inset);
    NSPoint center    = (NSPoint){NSMidX(bounds), NSMidY(bounds)};

    OFPoint *pointValue = [self objectValue];
    NSPoint  point      = pointValue ? [pointValue point] : NSZeroPoint;

    NSPoint lastPoint = point;
    do {
        [controlView setNeedsDisplay:YES];

        point    = [controlView convertPoint:[theEvent locationInWindow] fromView:nil];
        point.x -= center.x;
        point.y -= center.y;

        // TJW: Looks like this was trying to make it easy to hit the origin, but this looses all fine control... not sure what to do about this.
#if 0
        if (point.y > 0 && fabs(point.x) <= 1)
            point.x = 0;
        else if (point.y > 3 && point.x > 3 && fabs(point.y - point.x) <=2) {
            point.x = point.y;
        }
#endif
        
        // TJW: Looks like this was trying to do some hard coded clipping to the bounds
#if 0
        if (point.x > center.x - 10) {
            point.x = center.x - 10;
        } else if (point.x < (-center.x + 10)) {
            point.x = -center.x + 10;
        }
        if (point.y > center.y - 10) {
            point.y = center.y - 10;
        } else if (point.y < (-center.y + 10)) {
            point.y = -center.y + 10;
        }
#endif
        
        if (!NSEqualPoints(lastPoint, point)) {
            lastPoint  = point;

            // Calling up the the control view (probably a OAVectorView) to allow it to update other UI (X/Y fields).
            OFPoint *pointValue = [[OFPoint alloc] initWithPoint:point];
            [(NSControl *)controlView setObjectValue:pointValue];
            OBASSERT([(OFPoint *)[self objectValue] isEqual:pointValue]); // control better have updated us too
            [pointValue release];

            // We are ignoring -sendActionOn: and -setContinuous: right now.
            [(NSControl *)controlView sendAction:[self action] to:[self target]];
        }
        theEvent = [[controlView window] nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
    } while ([theEvent type] != NSLeftMouseUp);

    // We don't abort the value change if we leave the frame.
    return YES;
}

#pragma mark API

- (void)setIsMultiple:(BOOL)flag;
{
    _isMultiple = flag;
}

- (BOOL)isMultiple;
{
    return _isMultiple;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OAVectorCell *copy = [super copyWithZone:zone];
    copy->_imageCell = [_imageCell copyWithZone:zone];
    return copy;
}

@end
