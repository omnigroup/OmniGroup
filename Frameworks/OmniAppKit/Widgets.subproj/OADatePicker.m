// Copyright 2007-2017 Omni Development, Inc. All rights reserved.
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

@interface OADatePicker ()

@property (nonatomic, assign) BOOL sentAction;
@property (nonatomic, strong) NSDate *lastDate;
@property (nonatomic, assign) BOOL ignoreNextDateRequest; // <bug://bugs/38625> (Selecting date selects current date first when switching between months, disappears (with some filters) before proper date can be selected)

@end

@implementation OADatePicker

- (BOOL)sendAction:(SEL)theAction to:(id)theTarget;
{
    if (theAction == self.action) {
        self.ignoreNextDateRequest = NO;
    } else {
        self.lastDate = [self dateValue];
        self.ignoreNextDateRequest = YES;
        self.sentAction = YES;
    } 

    return [super sendAction:theAction to:theTarget];
}

- (void)mouseDown:(NSEvent *)theEvent;
{
    [super mouseDown:theEvent];
    
    if (!self.sentAction && [theEvent type] == NSEventTypeLeftMouseDown && [theEvent clickCount] > 1) {
        [[self window] resignKeyWindow];
    }

    self.clicked = YES;
    self.sentAction = NO;
}

- (NSDate *)dateValue;
{
    if (self.ignoreNextDateRequest) {
	return self.lastDate;
    }
    return [super dateValue];
}

- (void)setDateValue:(NSDate *)newStartDate;
{
    [super setDateValue:newStartDate];
    self.clicked = YES;
}

- (void)reset;
{
    self.lastDate = nil;
    self.ignoreNextDateRequest = NO;
}


@end
