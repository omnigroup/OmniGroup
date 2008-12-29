// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAPopupDatePicker.h 104581 2008-09-06 21:18:23Z kc $

#import <AppKit/NSWindowController.h>
#import <AppKit/NSControl.h>
#import <Foundation/NSGeometry.h>

@class /* Foundation     */ NSCalendar, NSDate, NSFormatter;
@class /* AppKit         */ NSButton, NSDatePicker, NSImage;
@class /* OmniAppKit     */ OADatePicker;

@interface OAPopupDatePicker : NSWindowController
{
    id _datePickerObjectValue;
    
    id _boundObject;
    id _boundObjectKeyPath;
    
    id _control;
    NSFormatter *_controlFormatter;
    SEL _stringUpdateSelector;
    
    IBOutlet OADatePicker *datePicker;
    IBOutlet NSDatePicker *timePicker;
}

+ (OAPopupDatePicker *)sharedPopupDatePicker;

+ (NSImage *)calendarImage;
+ (NSButton *)newCalendarButton;
+ (void)showCalendarButton:(NSButton *)button forFrame:(NSRect)calendarRect inView:(NSView *)superview withTarget:(id)aTarget action:(SEL)anAction;
+ (NSRect)calendarRectForFrame:(NSRect)cellFrame;

- (void)setCalendar:(NSCalendar *)calendar;

- (void)startPickingDateWithTitle:(NSString *)title forControl:(NSControl *)aControl stringUpdateSelector:(SEL)stringUpdateSelector defaultDate:(NSDate *)defaultDate;
- (void)startPickingDateWithTitle:(NSString *)title fromRect:(NSRect)viewRect inView:(NSView *)emergeFromView bindToObject:(id)bindObject withKeyPath:(NSString *)bindingKeyPath control:(id)control controlFormatter:(NSFormatter* )controlFormatter stringUpdateSelector:(SEL)stringUpdateSelector defaultDate:(NSDate *)defaultDate;

- (id)destinationObject;
- (NSString *)bindingKeyPath;

- (BOOL)isKey;
- (void)close;

// KVC
- (id)datePickerObjectValue;
- (void)setDatePickerObjectValue:(id)newObjectValue;

@end
