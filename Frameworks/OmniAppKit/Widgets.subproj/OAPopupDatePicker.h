// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSWindowController.h>
#import <AppKit/NSControl.h>
#import <Foundation/NSGeometry.h>

@class /* Foundation     */ NSCalendar, NSDate, NSFormatter;
@class /* AppKit         */ NSButton, NSDatePicker, NSImage;
@class /* OmniAppKit     */ OADatePicker;

extern NSString * const OAPopupDatePickerWillShowNotificationName;
extern NSString * const OAPopupDatePickerDidHideNotificationName;

extern NSString * const OAPopupDatePickerClientControlKey;
extern NSString * const OAPopupDatePickerCloseReasonKey;

extern NSString * const OAPopupDatePickerCloseReasonStandard;
extern NSString * const OAPopupDatePickerCloseReasonCancel;

@interface OAPopupDatePicker : NSWindowController <NSWindowDelegate>

+ (OAPopupDatePicker *)sharedPopupDatePicker;

+ (NSImage *)calendarImage;
+ (NSButton *)newCalendarButton;
+ (void)showCalendarButton:(NSButton *)button forFrame:(NSRect)calendarRect inView:(NSView *)superview withTarget:(id)aTarget action:(SEL)anAction;
+ (NSRect)calendarRectForFrame:(NSRect)cellFrame;

- (void)setCalendar:(NSCalendar *)calendar;

- (void)startPickingDateWithTitle:(NSString *)title forControl:(NSControl *)aControl dateUpdateSelector:(SEL)dateUpdateSelector defaultDate:(NSDate *)defaultDate;
- (void)startPickingDateWithTitle:(NSString *)title fromRect:(NSRect)viewRect inView:(NSView *)emergeFromView bindToObject:(id)bindObject withKeyPath:(NSString *)bindingKeyPath control:(id)control controlFormatter:(NSFormatter* )controlFormatter defaultDate:(NSDate *)defaultDate;

- (id)destinationObject;
- (NSString *)bindingKeyPath;

- (id)clientControl;

- (BOOL)isKey;
- (void)close;
- (void)closePopoverIfOpen;

// KVC
- (id)datePickerObjectValue;
- (void)setDatePickerObjectValue:(id)newObjectValue;

@end

@interface NSObject (OAPopupDatePickerBoundObject)
- (void)datePicker:(OAPopupDatePicker *)datePicker willUnbindFromKeyPath:(NSString *)keyPath;
@end

