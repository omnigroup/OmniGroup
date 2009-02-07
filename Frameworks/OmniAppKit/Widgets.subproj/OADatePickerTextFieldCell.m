// Copyright 2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OADatePickerTextFieldCell.h"
#import <OmniBase/rcsid.h>
#import "OAPopupDatePicker.h"

RCS_ID("$Id$");

@implementation OADatePickerTextFieldCell

#pragma mark -
#pragma mark NSCell subclass

- (NSRect)titleRectForBounds:(NSRect)bounds;
{
    NSRect buttonRect = [OAPopupDatePicker calendarRectForFrame:bounds];
    float horizontalEdgeGap = 2.0f;
    
    bounds.size.width -= NSWidth(buttonRect) + horizontalEdgeGap;
    return bounds;
}

- (void)editWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject event:(NSEvent *)theEvent;
{
    [super editWithFrame:[self titleRectForBounds:aRect] inView:controlView editor:textObj delegate:anObject event:theEvent];
}

- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength;
{
    [super selectWithFrame:[self titleRectForBounds:aRect] inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
}

@end
