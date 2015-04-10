// Copyright 2007-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OADatePicker.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSWindow.h>

RCS_ID("$Id$");

@interface NSDatePicker ()
- (void)_clockAndCalendarReturnToHomeMonth:(id)sender;
- (void)_clockAndCalendarRetreatMonth:(id)sender;
- (void)_clockAndCalendarAdvanceMonth:(id)sender;
@end

@implementation OADatePicker

- (void)dealloc;
{
    [_lastDate release];
    [super dealloc];
}

- (BOOL)sendAction:(SEL)theAction to:(id)theTarget;
{
    if (theAction == self.action) {
        ignoreNextDateRequest = NO;
    } else {
        _lastDate = [[self dateValue] retain];
        ignoreNextDateRequest = YES;
        sentAction = YES;
    } 

    return [super sendAction:theAction to:theTarget];
}

- (void)mouseDown:(NSEvent *)theEvent;
{
    [super mouseDown:theEvent];
    
    if (!sentAction && [theEvent type] == NSLeftMouseDown && [theEvent clickCount] > 1) {
        [[self window] resignKeyWindow];
    }

    _clicked = YES;
    sentAction = NO;
}

- (NSDate *)dateValue;
{
    if (ignoreNextDateRequest) {
	return _lastDate;
    }
    return [super dateValue];
}

- (void)setDateValue:(NSDate *)newStartDate;
{
    [super setDateValue:newStartDate];
    _clicked = YES;
}

- (void)setClicked:(BOOL)clicked;
{
    _clicked = clicked;
}

- (BOOL)clicked;
{
    return _clicked;
}

- (void)reset;
{
    [_lastDate release];
    _lastDate = nil;
    ignoreNextDateRequest = NO;
}


@end
