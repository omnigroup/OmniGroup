// Copyright 2006-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OADatePickerTextField.h>

#import <OmniAppKit/OAPopupDatePicker.h>
#import <OmniAppKit/OADatePickerTextFieldCell.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$");

//static NSString * const DefaultDateBinding = @"defaultDateBinding";

@interface OADatePickerTextField ()
@property (nonatomic, strong) NSButton *calendarButton;
@end

@implementation OADatePickerTextField

#pragma mark -
#pragma mark Init and dealloc

+ (Class)cellClass;
{
    return [OADatePickerTextFieldCell class];
}

static id _commonInit(OADatePickerTextField *self)
{
    if (!self.calendarButton) {
        self.calendarButton = [OAPopupDatePicker newCalendarButton];
        [OAPopupDatePicker showCalendarButton:self.calendarButton forFrame:[OAPopupDatePicker calendarRectForFrame:[self bounds]] inView:self withTarget:self action:@selector(_toggleDatePicker)];
        [self setAutoresizesSubviews:YES];
    }
    
    OBPOSTCONDITION([[self cell] isKindOfClass:[OADatePickerTextFieldCell class]], @"If this OADatePickerTextField is coming out of a nib/xib/storyboard, make sure to set the class of its cell to OADatePickerTextFieldCell.");
    
    return self;
}

- (id)initWithFrame:(NSRect)frameRect;
{
    if (!(self = [super initWithFrame:frameRect]))
        return nil;
    return _commonInit(self);
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if (!(self = [super initWithCoder:aDecoder]))
        return nil;
    return _commonInit(self);
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
    NSDate *midnightToday = [currentCalendar startOfDayForDate:[NSDate date]];
    NSDateComponents *defaultDateComponents = [currentCalendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:midnightToday];
    [defaultDateComponents setHour:[dueTimeDateComponents hour]];
    [defaultDateComponents setMinute:[dueTimeDateComponents minute]];
    defaultDate = [currentCalendar dateFromComponents:defaultDateComponents];
    return defaultDate;
}

#pragma mark -
#pragma mark OASteppableTextField subclass

- (BOOL)validateSteppedObjectValue:(id)objectValue;
{
    if (objectValue == nil || ![objectValue isKindOfClass:[NSDate class]])
	return NO;

    NSDate *date = objectValue;
    // if a min or max date is set, check against that
    if ((self.maxDate != nil && [date compare:self.maxDate] == NSOrderedDescending))
	return NO;
    if ((self.minDate != nil && [date compare:self.minDate] == NSOrderedAscending))
	return NO;	

    return YES;
}

#pragma mark -
#pragma mark NSControl subclass

- (void)setEnabled:(BOOL)enabled;
{
    [super setEditable:enabled];
    self.calendarButton.enabled = (self.enabled && self.editable);
    [super setTextColor:(self.enabled && self.editable) ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]];
}

- (void)setEditable:(BOOL)editable;
{
    [super setEditable:editable];
    self.calendarButton.enabled = (self.enabled && self.editable);
    [super setTextColor:(self.enabled && self.editable) ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]];
}
    
#pragma mark -
#pragma mark NSView subclass

- (void)didAddSubview:(NSView *)subview;
{
    if (subview == self.calendarButton) {
        return;
    }

    [self.calendarButton removeFromSuperview];
    [self addSubview:self.calendarButton];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow;
{
    if (!newWindow)
        [[OAPopupDatePicker sharedPopupDatePicker] close];
}

- (BOOL)isDatePickerHidden;
{
    return self.calendarButton.isHidden;
}

- (void)setIsDatePickerHidden:(BOOL)yn;
{
    self.calendarButton.hidden = yn;
}

- (void)resetCursorRects
{
    [self addCursorRect:self.bounds cursor:[NSCursor IBeamCursor]];
    if (!self.calendarButton.isHidden) {
	[self addCursorRect:self.calendarButton.frame cursor:[NSCursor arrowCursor]];
    }
}

#pragma mark - Private

- (void)_toggleDatePicker;
{
    OAPopupDatePicker *sharedPopupDatePicker = [OAPopupDatePicker sharedPopupDatePicker];
    if ([sharedPopupDatePicker isKey])
        [sharedPopupDatePicker close]; 
    else {
        [sharedPopupDatePicker setCalendar:self.calendar];
        
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
	return date;
    } else {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setDay:1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
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
	return date;
    } else {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setMonth:1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
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
	return date;
    } else {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setDay:-1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
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
	return date;
    } else {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setMonth:-1];
	NSDate *date = [currentCalendar dateByAddingComponents:components toDate:anObjectValue options:0];
	return date;
    }
}

@end
