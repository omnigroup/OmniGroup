// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OASteppableTextField.h"

@class /* AppKit */ NSButton;

@interface OADatePickerTextField : OASteppableTextField
{
    NSDate *minDate;
    NSDate *maxDate;
    NSButton *calendarButton;
    NSCalendar *calendar;
    
    NSTrackingRectTag visibleRectTag;

    NSTextField *_defaultTextField;
}

- (NSDate *)defaultDate;
- (void)setDefaultDateTextField:(NSTextField *)defaultTextField;

- (NSDate *)minDate;
- (void)setMinDate:(NSDate *)aDate;
- (NSDate *)maxDate;
- (void)setMaxDate:(NSDate *)aDate;

- (BOOL)isDatePickerHidden;
- (void)setIsDatePickerHidden:(BOOL)yn;

- (NSCalendar *)calendar;
- (void)setCalendar:(NSCalendar *)aCalendar;

@end

