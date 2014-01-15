// Copyright 2006-2008, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OADatePickerTextField.h"

#import "OAPopupDatePicker.h"
#import "OADatePickerTextFieldCell.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$");

//static NSString * const DefaultDateBinding = @"defaultDateBinding";

@interface OADatePickerTextField (Private)
- (id)_initDatePickerTextFieldPost;
- (void)_toggleDatePicker;
@end

@implementation OADatePickerTextField

#pragma mark -
#pragma mark Init and dealloc

+ (Class)cellClass;
{
    return [OADatePickerTextFieldCell class];
}

- (id)initWithFrame:(NSRect)frameRect;
{
    if (!(self = [super initWithFrame:frameRect]))
        return nil;
    return [self _initDatePickerTextFieldPost];
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if (!(self = [super initWithCoder:aDecoder]))
        return nil;
    return [self _initDatePickerTextFieldPost];
}

- (void)dealloc;
{
    [minDate release];
    [maxDate release];
    [calendarButton release];
    [calendar release];
    [_defaultTextField release];
    [super dealloc];
}

#pragma mark -
#pragma mark KVO

- (NSDate *)defaultDate;
{
    //   NSDate *defaultDate = (NSDate *)[self valueForKey:DefaultDateBinding];
    NSDate *defaultDate = (NSDate *)[_defaultTextField objectValue];
    if (defaultDate != nil)
    	return defaultDate;
    
    OFRelativeDateFormatter *formatter = [self formatter];
    NSDateComponents *dueTimeDateComponents = [formatter defaultTimeDateComponents];
    NSCalendar *currentCalendar = [NSCalendar currentCalendar];
    NSCalendarDate *midnightToday = [NSCalendarDate calendarDate];
    midnightToday = [midnightToday dateByAddingYears:0 months:0 days:0 hours:(-[midnightToday hourOfDay]) minutes:-[midnightToday minuteOfHour] seconds:0];
    NSDateComponents *defaultDateComponents = [currentCalendar components:NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit fromDate:midnightToday];
    [defaultDateComponents setHour:[dueTimeDateComponents hour]];
    [defaultDateComponents setMinute:[dueTimeDateComponents minute]];
    defaultDate = [currentCalendar dateFromComponents:defaultDateComponents];
    return defaultDate;
}

- (void)setDefaultDateTextField:(NSTextField *)defaultTextField;
{
    //[self bind:DefaultDateBinding toObject:boundObject withKeyPath:boundKey options:nil];
    _defaultTextField = [defaultTextField retain];
}

#pragma mark -
#pragma mark Accessors

- (NSDate *)minDate;
{
    return minDate;
}

- (void)setMinDate:(NSDate *)aDate;
{
    [minDate release];
    minDate = [aDate retain];
}

- (NSDate *)maxDate;
{
    return maxDate;
}

- (void)setMaxDate:(NSDate *)aDate;
{
    [maxDate release];
    maxDate = [aDate retain];
}

- (NSCalendar *)calendar;
{
    return calendar;
}

- (void)setCalendar:(NSCalendar *)aCalendar;
{
    if (aCalendar == calendar) 
        return;
    
    [calendar release];
    calendar = [aCalendar retain];
}


#pragma mark -
#pragma mark OASteppableTextField subclass

- (BOOL)validateSteppedObjectValue:(id)objectValue;
{
    if (objectValue == nil || ![objectValue isKindOfClass:[NSDate class]])
	return NO;

    NSDate *date = objectValue;
    // if a min or max date is set, check against that
    if ((maxDate != nil && [date compare:maxDate] == NSOrderedDescending)) 
	return NO;
    if ((minDate != nil && [date compare:minDate] == NSOrderedAscending))
	return NO;	

    return YES;
}

#pragma mark -
#pragma mark NSControl subclass

- (void)setEditable:(BOOL)editable;
{
    [super setEditable:editable];
    [calendarButton setEnabled:editable];
}
    
#pragma mark -
#pragma mark NSView subclass

- (void)didAddSubview:(NSView *)subview;
{
    if (subview == calendarButton)
        return;

    [calendarButton removeFromSuperview];
    [self addSubview:calendarButton];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow;
{
    if (!newWindow)
        [[OAPopupDatePicker sharedPopupDatePicker] close];
}

- (BOOL)isDatePickerHidden;
{
    return [calendarButton isHidden];
}
- (void)setIsDatePickerHidden:(BOOL)yn;
{
    [calendarButton setHidden:yn];
}

- (void)resetCursorRects
{
    [self addCursorRect:self.bounds cursor:[NSCursor IBeamCursor]];
    if (![calendarButton isHidden])
	[self addCursorRect:[calendarButton frame] cursor:[NSCursor arrowCursor]];
}

@end

@implementation OADatePickerTextField (Private)

- (id)_initDatePickerTextFieldPost;
{
    if (!calendarButton) {
	calendarButton = [OAPopupDatePicker newCalendarButton];
	[OAPopupDatePicker showCalendarButton:calendarButton forFrame:[OAPopupDatePicker calendarRectForFrame:[self bounds]] inView:self withTarget:self action:@selector(_toggleDatePicker)];
	[self setAutoresizesSubviews:YES];
    }
    // Sadly can't set this in IB 2.x; only 3.x; smack it for now.
    Class cls = [OADatePickerTextFieldCell class];
    
    OBASSERT(class_getInstanceSize(cls) == class_getInstanceSize(class_getSuperclass(cls))); // Must not add ivars
    NSCell *cell = [self cell];
    if (![cell isKindOfClass:cls]) {  // if we're already a datepicker we don't need ot do this
	OBASSERT([cell class] == [NSTextFieldCell class]);
	*(Class *)cell = cls;
    }
    OBPOSTCONDITION([cell isKindOfClass:[OADatePickerTextFieldCell class]]);
    
    return self;
}

- (void)_toggleDatePicker;
{
    OAPopupDatePicker *sharedPopupDatePicker = [OAPopupDatePicker sharedPopupDatePicker];
    if ([sharedPopupDatePicker isKey])
        [sharedPopupDatePicker close]; 
    else {
        [sharedPopupDatePicker setCalendar:calendar];
        
        NSString *title = NSLocalizedStringFromTableInBundle(@"Choose Date", @"OmniAppKit", OMNI_BUNDLE, @"Date picker window title");
        
        NSDictionary *bindingInfo = [self infoForBinding:@"value"];
        id bindingObject = [bindingInfo objectForKey:NSObservedObjectKey];
        NSString *bindingKeyPath = [[bindingInfo objectForKey:NSObservedKeyPathKey] stringByReplacingOccurrencesOfString:@"selectedObjects." withString:@"selection."];
        
	[sharedPopupDatePicker startPickingDateWithTitle:title fromRect:[self visibleRect] inView:self bindToObject:bindingObject withKeyPath:bindingKeyPath control:self controlFormatter:[self formatter] defaultDate:[self defaultDate]];
    }
}

@end

@implementation NSDateFormatter (OASteppableTextFieldFormatter)

- (id)stepUpValue:(id)anObjectValue;
{
    if (anObjectValue == nil)
	anObjectValue = [NSDate date];
    
    NSCalendar *currentCalendar = [NSCalendar currentCalendar];
    if ([self formatterBehavior] == NSDateFormatterBehavior10_4 && [self dateStyle] == NSDateFormatterNoStyle && [self timeStyle] != NSDateFormatterNoStyle) {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setMinute:1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
	[components release];
	return date;
    } else {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setDay:1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
	[components release];
	return date;
    }
}

- (id)largeStepUpValue:(id)anObjectValue;
{
    if (anObjectValue == nil)
	anObjectValue = [NSDate date];
    
    NSCalendar *currentCalendar = [NSCalendar currentCalendar];
    if ([self formatterBehavior] == NSDateFormatterBehavior10_4 && [self dateStyle] == NSDateFormatterNoStyle && [self timeStyle] != NSDateFormatterNoStyle) {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setHour:1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
	[components release];
	return date;
    } else {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setMonth:1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
	[components release];
	return date;
    }
}

- (id)stepDownValue:(id)anObjectValue;
{
    if (anObjectValue == nil)
	anObjectValue = [NSDate date];
    
    NSCalendar *currentCalendar = [NSCalendar currentCalendar];
    if ([self formatterBehavior] == NSDateFormatterBehavior10_4 && [self dateStyle] == NSDateFormatterNoStyle && [self timeStyle] != NSDateFormatterNoStyle) {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setMinute:1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
	[components release];
	return date;
    } else {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setDay:-1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
	[components release];
	return date;
    }
}

- (id)largeStepDownValue:(id)anObjectValue;
{
    if (anObjectValue == nil)
	anObjectValue = [NSDate date];
    
    NSCalendar *currentCalendar = [NSCalendar currentCalendar];
    if ([self formatterBehavior] == NSDateFormatterBehavior10_4 && [self dateStyle] == NSDateFormatterNoStyle && [self timeStyle] != NSDateFormatterNoStyle) {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setHour:-1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
	[components release];
	return date;
    } else {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setMonth:-1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
	[components release];
	return date;
    }
}

@end
