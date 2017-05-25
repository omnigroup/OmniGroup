// Copyright 2006-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAPopupDatePicker.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>

#import <OmniAppKit/NSEvent-OAExtensions.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/OAWindowCascade.h>
#import "OADatePicker.h"
#import <OmniAppKit/OAVersion.h>

NSString * const OAPopupDatePickerWillShowNotificationName = @"OAPopupDatePickerWillShow";
NSString * const OAPopupDatePickerDidHideNotificationName = @"OAPopupDatePickerDidHide";

NSString * const OAPopupDatePickerClientControlKey = @"OAPopupDatePickerClientControl";
NSString * const OAPopupDatePickerCloseReasonKey = @"OAPopupDatePickerCloseReason";

NSString * const OAPopupDatePickerCloseReasonStandard = @"OAPopupDatePickerCloseReasonStandard";
NSString * const OAPopupDatePickerCloseReasonCancel = @"OAPopupDatePickerCloseReasonCancel";

RCS_ID("$Id$");

@interface OAPopupDatePickerWindow : NSWindow
@end

@interface OADatePickerButton : NSButton 
@end

@interface OAPopupDatePicker () {
    id _datePickerObjectValue;
    id _datePickerOriginalValue;
    
    NSObject *_boundObject;
    id _boundObjectKeyPath;
    
    id _control;
    NSFormatter *_controlFormatter;
    
    SEL _dateUpdatedAction;
    
    BOOL _startedWithNilDate;
    
}

@property (nonatomic, retain) IBOutlet OADatePicker *datePicker;
@property (nonatomic, retain) IBOutlet NSDatePicker *timePicker;

- (void)_configureTimePickerFromFormatter:(NSFormatter *)formatter;
    // Show or hide the time picker as needed based on the time style from the given formatter
    // If passed nil or a non-NSDateFormatter, will show the time picker

- (void)_setDefaultDate:(NSDate *)defaultDate respectingValueFromBoundObject:(BOOL)preferBinding;
    // Set the initial date to be selected when the popup is presented
    // If preferBinding is YES, will query _boundObject using _boundObjectKeyPath to attempt to determine an NSDate
    // If preferBinding is NO or the bound object returned a nil date, will fall back on using the given defaultDate

- (void)_prepareBindingsForPopupWindowPresentation;
    // Establish bindings between our visible controls (date & time pickers) and this object
    // Bindings to the presenting control are *optional* and configured by calling -startPickingDateWithTitle:...bindToObject:...

- (void)_showPopupWindowWithTitle:(NSString *)title fromRect:(NSRect)viewRect ofView:(NSView *)emergeFromView;

- (void)_firstDayOfTheWeekDidChange:(NSNotification *)notification;

@end

@implementation OAPopupDatePicker

static NSImage *calendarImage;
static NSSize calendarImageSize;

+ (void)initialize;
{
    OBINITIALIZE;
    calendarImage = [[NSImage imageNamed:@"calendar" inBundle:OMNI_BUNDLE] retain];
    calendarImageSize = [calendarImage size];
}

+ (OAPopupDatePicker *)sharedPopupDatePicker;
{
    static OAPopupDatePicker *sharedPopupDatePicker = nil;

    if (sharedPopupDatePicker == nil)
        sharedPopupDatePicker = [[self alloc] init];
    return sharedPopupDatePicker;
}

+ (NSImage *)calendarImage;
{
    return calendarImage;
}

+ (NSButton *)newCalendarButton;
{ 
    NSButton *button = [[OADatePickerButton alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, calendarImageSize.width, calendarImageSize.height)];
    [button setButtonType:NSMomentaryPushInButton];
    [button setBordered:NO];
    [button setImage:calendarImage];
    [button setImagePosition:NSImageOnly];
    [button setAutoresizingMask:NSViewMinXMargin|NSViewMinYMargin|NSViewMaxYMargin];
    // [button setRefusesFirstResponder:YES];
    return button;
}

+ (void)showCalendarButton:(NSButton *)button forFrame:(NSRect)calendarRect inView:(NSView *)superview withTarget:(id)aTarget action:(SEL)anAction;
{
    [button setTarget:aTarget];
    [button setAction:anAction];
    [button setFrame:calendarRect];
    [superview addSubview:button];
}

+ (NSRect)calendarRectForFrame:(NSRect)cellFrame;
{
    CGFloat verticalEdgeGap = (CGFloat)floor((NSHeight(cellFrame) - calendarImageSize.height) / 2.0f);
    const CGFloat horizontalEdgeGap = 3.0f;
    
    NSRect imageRect;
    imageRect.origin.x = NSMaxX(cellFrame) - calendarImageSize.width - horizontalEdgeGap;
    imageRect.origin.y = NSMinY(cellFrame) + verticalEdgeGap;
    imageRect.size = calendarImageSize;
    
    return imageRect;
}

- (id)init;
{
    if (!(self = [self initWithWindowNibName:@"OAPopupDatePicker"]))
        return nil;

    NSWindow *window = [self window];
    if ([window respondsToSelector:@selector(setCollectionBehavior:)]) {
        unsigned int collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace|NSWindowCollectionBehaviorFullScreenAuxiliary;
    	[window setCollectionBehavior:collectionBehavior];  
    }

    [OFPreference addObserver:self selector:@selector(_firstDayOfTheWeekDidChange:) forPreference:[NSCalendar firstDayOfTheWeekPreference]];
    [self _firstDayOfTheWeekDidChange:nil];
    
    return self;
}

- (void)dealloc;
{
    [OFPreference removeObserver:self forPreference:[NSCalendar firstDayOfTheWeekPreference]];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_datePickerObjectValue release];
    [_boundObject release];
    [_boundObjectKeyPath release];
    [_control release];
    [_datePickerOriginalValue release];
    [_timePicker release];
    
    [super dealloc];
}

- (void)setCalendar:(NSCalendar *)calendar;
{
    [_datePicker setCalendar:calendar];
    [_timePicker setCalendar:calendar];
}

- (void)startPickingDateWithTitle:(NSString *)title forControl:(NSControl *)aControl dateUpdateSelector:(SEL)dateUpdateSelector defaultDate:(NSDate *)defaultDate;
{
    [self close];
    
    _control = [aControl retain];
    _dateUpdatedAction = dateUpdateSelector;
    
    [self _configureTimePickerFromFormatter:[aControl formatter]];
    [self _setDefaultDate:defaultDate respectingValueFromBoundObject:NO];
    
    [self _showPopupWindowWithTitle:title fromRect:[aControl bounds] ofView:aControl];
}

- (void)startPickingDateWithTitle:(NSString *)title fromRect:(NSRect)viewRect inView:(NSView *)emergeFromView bindToObject:(id)bindObject withKeyPath:(NSString *)bindingKeyPath control:(id)control controlFormatter:(NSFormatter* )controlFormatter defaultDate:(NSDate *)defaultDate;
{
    [self close];
    
    // retain the various arguments (bound object/keypath, presenting control)
    _boundObject = [bindObject retain];
    _boundObjectKeyPath = [bindingKeyPath retain];
    _control = [control retain];
    
    // set up default appearance & behavior
    [self _configureTimePickerFromFormatter:controlFormatter];
    [self _setDefaultDate:defaultDate respectingValueFromBoundObject:YES];
    
    [self _showPopupWindowWithTitle:title fromRect:viewRect ofView:emergeFromView];
}

- (id)destinationObject;
{
    return [[_datePicker infoForBinding:@"value"] objectForKey:NSObservedObjectKey];
}

- (NSString *)bindingKeyPath;
{
    return [[_datePicker infoForBinding:@"value"] objectForKey:NSObservedKeyPathKey];
}

- (BOOL)isKey;
{
    return [[self window] isKeyWindow];
}

- (void)close;
{
    if ([self isKey])
	[[self window] resignKeyWindow];
}

- (id)clientControl;
{
    return _control;
}

- (NSDatePicker *)datePicker;
{
    OBASSERT(_datePicker != nil);
    return _datePicker;
}

- (IBAction)datePickerAction:(id)sender;
{
    if (_boundObject && ![_boundObject valueForKeyPath:_boundObjectKeyPath]) {
        [_boundObject setValue:[_datePicker objectValue] forKeyPath:_boundObjectKeyPath];
    }
    
    if (!_boundObject) {
        if (_dateUpdatedAction) {
            [_control performSelector:_dateUpdatedAction withObject:_datePickerObjectValue];
        } else {
            [_control setObjectValue:_datePickerObjectValue];
        }
    }
}

- (void)setWindow:(NSWindow *)window;
{
    NSView *contentView = [window contentView];
    NSWindow *newWindow = [[[OAPopupDatePickerWindow alloc] initWithContentRect:[contentView frame] styleMask:NSBorderlessWindowMask|NSUnifiedTitleAndToolbarWindowMask backing:NSBackingStoreBuffered defer:NO] autorelease];
    [newWindow setContentView:contentView];
    [newWindow setLevel:NSPopUpMenuWindowLevel];
    [newWindow setDelegate:self];
    [super setWindow:newWindow];
}

- (void)closePopoverIfOpen;
{
    NSWindow *window = [self window];
    if (window) {
        NSWindow *parentWindow = [window parentWindow];
        [parentWindow removeChildWindow:window];
        [window close];
    }
}

#pragma mark -
#pragma mark KVC

// Key value coding accessors for the date picker
- (id)datePickerObjectValue;
{
    return _datePickerObjectValue;
}

- (void)setDatePickerObjectValue:(id)newObjectValue;
{
    if (_datePickerObjectValue == newObjectValue)
        return;
    
    [_datePickerObjectValue release];
    _datePickerObjectValue = [newObjectValue retain];
    
    // update the object
    if (_boundObject) {
        [_boundObject setValue:_datePickerObjectValue forKeyPath:_boundObjectKeyPath];
    } else if (_dateUpdatedAction) {
        [_control performSelector:_dateUpdatedAction withObject:_datePickerObjectValue];
    }
}

#pragma mark -
#pragma mark NSObject (NSWindowNotifications)

- (void)windowDidResignKey:(NSNotification *)notification;
{
    OBPRECONDITION([notification object] == [self window]);
    
    NSWindow *parentWindow = [[self window] parentWindow];
    OBASSERT(parentWindow); // Should not have disassociated quite yet
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:parentWindow];
    
    NSString *closeReason = OAPopupDatePickerCloseReasonStandard;
    NSEvent *currentEvent = [[NSApplication sharedApplication] currentEvent];
    
    BOOL isCancel = [currentEvent isUserCancel];
    unichar character = (([currentEvent type] == NSKeyDown) && ([[currentEvent characters] length] == 1)) ? [[currentEvent characters] characterAtIndex:0] : 0;
    BOOL isCommit = ([currentEvent type] == NSKeyDown && (character == 0x1b || character == 0x03 || character == 0x0d));
    
    if (isCancel) {
        closeReason = OAPopupDatePickerCloseReasonCancel;
        
        if (_startedWithNilDate) {
            _datePickerObjectValue = nil;
            
            if (_dateUpdatedAction)
                [_control performSelector:_dateUpdatedAction withObject:nil];
            else
                [_control setObjectValue:nil];
        } else if (!_startedWithNilDate && _datePickerOriginalValue) {
            _datePickerObjectValue = _datePickerOriginalValue;
            
            if (_dateUpdatedAction)
                [_control performSelector:_dateUpdatedAction withObject:_datePickerOriginalValue];
            else
                [_control setObjectValue:_datePickerOriginalValue];
        }
    } else if (isCommit) {
        // Force-set whatever object value we currently have in response to an Enter/Return keypress
        if (_dateUpdatedAction)
            [_control performSelector:_dateUpdatedAction withObject:_datePickerObjectValue];
        else
            [_control setObjectValue:_datePickerObjectValue];
    }
    
    if ([_boundObject respondsToSelector:@selector(datePicker:willUnbindFromKeyPath:)])
        [_boundObject datePicker:self willUnbindFromKeyPath:_boundObjectKeyPath];
    
    [_datePicker unbind:NSValueBinding];
    [_timePicker unbind:NSValueBinding];
    
    [_boundObject release];
    _boundObject = nil;
    [_boundObjectKeyPath release];
    _boundObjectKeyPath = nil;
    
    [self _postNotificationWithName:OAPopupDatePickerDidHideNotificationName additionalUserInfo:@{ OAPopupDatePickerCloseReasonKey : closeReason }];
    
    [_control release];
    _control = nil;
}

- (void)_parentWindowWillClose:(NSNotification *)note;
{
    [self close];
}

#pragma mark - Private

- (void)_configureTimePickerFromFormatter:(NSFormatter *)formatter;
{
    NSWindow *popupWindow = [self window];

    // we want to display the time for all custom date formatters.
    BOOL isCustomDateFormatter = ([formatter isKindOfClass:[NSDateFormatter class]] && [(NSDateFormatter *)formatter dateStyle] == kCFDateFormatterNoStyle && [(NSDateFormatter *)formatter timeStyle] == kCFDateFormatterNoStyle);
    if ([formatter isKindOfClass:[NSDateFormatter class]] && (!isCustomDateFormatter) && [(NSDateFormatter *)formatter timeStyle] == kCFDateFormatterNoStyle) {
        if ([_timePicker superview]) {
            NSRect frame = popupWindow.frame;
            frame.size.height -= NSHeight([_timePicker frame]);
            [_timePicker removeFromSuperview];
            [popupWindow setFrame:frame display:YES];
        }
    } else if (![_timePicker superview]) {
        [[popupWindow contentView] addSubview:_timePicker];
        NSRect frame = popupWindow.frame;
        frame.size.height += NSHeight([_timePicker frame]);
        [popupWindow setFrame:frame display:YES];
    }
}

- (void)_setDefaultDate:(NSDate *)defaultDate respectingValueFromBoundObject:(BOOL)preferBinding;
{
    // set the default date picker value to the bound value
    [_datePickerObjectValue release];
    _datePickerObjectValue = nil;
    _startedWithNilDate = YES;
    
    if (preferBinding) {
        id defaultObjectFromBinding = [_boundObject valueForKeyPath:_boundObjectKeyPath];
        if ([defaultObjectFromBinding isKindOfClass:[NSDate class]]) {
            _datePickerObjectValue = [defaultObjectFromBinding retain];
            _datePickerOriginalValue = [_datePickerObjectValue retain];
            _startedWithNilDate = NO;
        }
    }
    
    //if there is no value from the binding (or we didn't use the binding), use the passed in default time
    if (_datePickerObjectValue == nil)
	_datePickerObjectValue = [defaultDate copy]; // NB: don't update _startedWithNilDate, because a "default" is not the same as an "original" value
    
    [_datePicker reset];
}

- (void)_prepareBindingsForPopupWindowPresentation;
{
    // bind the date picker to our local object value
    [_datePicker bind:NSValueBinding toObject:self withKeyPath:@"datePickerObjectValue" options:@{ NSAllowsEditingMultipleValuesSelectionBindingOption : @YES }];
    [_datePicker setTarget:self];
    [_datePicker setAction:@selector(datePickerAction:)];
    
    [_timePicker bind:NSValueBinding toObject:self withKeyPath:@"datePickerObjectValue" options:@{ NSAllowsEditingMultipleValuesSelectionBindingOption : @YES }];
    
    [self setDatePickerObjectValue:_datePickerObjectValue];
    [_datePicker setClicked:NO];
}

- (void)_showPopupWindowWithTitle:(NSString *)title fromRect:(NSRect)viewRect ofView:(NSView *)emergeFromView;
{
    [self _prepareBindingsForPopupWindowPresentation];
    
    NSWindow *emergeFromWindow = [emergeFromView window];
    NSWindow *popupWindow = [self window];
    NSAppearance *appearance = emergeFromView.window.appearance;
    popupWindow.appearance = appearance;
    BOOL isDark = OFISEQUAL(appearance.name, NSAppearanceNameVibrantDark);
    if (isDark) {
        _timePicker.bordered = YES;
    } else {
        _timePicker.bezeled = YES;
    }

    /* Finally, place the editor window on-screen */
    [popupWindow setTitle:title];
    
    NSRect popupWindowFrame = [popupWindow frame];
    NSRect targetWindowRect = [emergeFromView convertRect:viewRect toView:nil];
    NSPoint viewRectCenter = [emergeFromWindow convertRectToScreen:NSMakeRect(NSMidX(targetWindowRect), NSMidY(targetWindowRect), 0.0f, 0.0f)].origin;
    NSPoint windowOrigin = [emergeFromWindow convertRectToScreen:NSMakeRect(NSMidX(targetWindowRect), NSMinY(targetWindowRect), 0.0f, 0.0f)].origin;
    windowOrigin.x -= (CGFloat)floor(NSWidth(popupWindowFrame) / 2.0f);
    windowOrigin.y -= 2.0f;
    
    NSScreen *screen = [OAWindowCascade screenForPoint:viewRectCenter];
    NSRect visibleFrame = [screen visibleFrame];
    if (windowOrigin.x < visibleFrame.origin.x)
	windowOrigin.x = visibleFrame.origin.x;
    else {
	CGFloat maxX = NSMaxX(visibleFrame) - NSWidth(popupWindowFrame);
	if (windowOrigin.x > maxX)
	    windowOrigin.x = maxX;
    }
    
    if (windowOrigin.y > NSMaxY(visibleFrame))
	windowOrigin.y = NSMaxY(visibleFrame);
    else {
	CGFloat minY = NSMinY(visibleFrame) + NSHeight(popupWindowFrame);
	if (windowOrigin.y < minY)
	    windowOrigin.y = minY;
    }
    
    [self _postNotificationWithName:OAPopupDatePickerWillShowNotificationName additionalUserInfo:nil];
    
    [popupWindow setFrameTopLeftPoint:windowOrigin];
    [popupWindow makeKeyAndOrderFront:nil];
    
    NSWindow *parentWindow = [emergeFromView window];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_parentWindowWillClose:) name:NSWindowWillCloseNotification object:parentWindow];
    [parentWindow addChildWindow:popupWindow ordered:NSWindowAbove];
}

- (void)_postNotificationWithName:(NSString *)notificationName additionalUserInfo:(NSDictionary *)additionalUserInfo;
{
    NSMutableDictionary *userInfo = additionalUserInfo ? [[additionalUserInfo mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    if (self.clientControl != nil)
        [userInfo setObject:[self clientControl] forKey:OAPopupDatePickerClientControlKey];
    
    NSNotification *notification = [NSNotification notificationWithName:notificationName object:self userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (void)_firstDayOfTheWeekDidChange:(NSNotification *)notification;
{
     // OmniPlan lets users set a different first day of week from the system default. See <bug:///30007> (Bug: Preference for first day of the week [start])
    OFPreference *firstWeekdayPreference = [NSCalendar firstDayOfTheWeekPreference];
    NSCalendar *calendar = [[NSCalendar currentCalendar] retain];
    
    if ([firstWeekdayPreference hasNonDefaultValue]) {
        NSCalendar *adjustedCalendar = [calendar copy];
        adjustedCalendar.firstWeekday = [firstWeekdayPreference unsignedIntegerValue];
        
        [calendar release];
        calendar = adjustedCalendar;
    }
    
    [_datePicker setCalendar:calendar];
    [calendar release];
}

@end

@implementation OAPopupDatePickerWindow

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent;
{
    NSString *characters = [theEvent characters];
    if ([characters length] != 1) {
        return [super performKeyEquivalent:theEvent];
    }
    
    unichar character = [characters characterAtIndex:0];
    
    switch (character) {
        case '.':
            if ([theEvent modifierFlags] & NSCommandKeyMask) {
                [self resignKeyWindow];
                return YES;
            } else {
                return [super performKeyEquivalent:theEvent];
            }
        case 0x1b:
        case 0x0d:
        case 0x03:
            [self resignKeyWindow];
            return YES;
        default:
            return [super performKeyEquivalent:theEvent];
    }
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)resignKeyWindow;
{
    [super resignKeyWindow];
    NSWindow *parentWindow = [self parentWindow];
    [parentWindow removeChildWindow:self];
    [self close];
    
    // It looks like this code would never fire since it should have been using NSKeyDown instead of NSKeyDownMask
    // <bug:///104045> (Unassigned: 10.10: OAPopupDatePickerWindow -resignKeyWindow has bad test of event type)
#if 0
    if ([[[NSApplication sharedApplication] currentEvent] type] == NSKeyDownMask) {
        // <bug://bugs/57041> (Enter/Return should commit edits on the split task window)
        [parentWindow makeKeyAndOrderFront:nil];
    }
#endif
}

@end

@implementation OADatePickerButton

- (BOOL)canBecomeKeyView;
{
    return NO;
}

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)theEvent;
{
    return YES;
}

- (void)mouseDown:(NSEvent *)theEvent;
{
    [[NSApplication sharedApplication] preventWindowOrdering];
    [super mouseDown:theEvent];
}

@end

@interface OAPopupDatePickerBackgroundView : NSView
@end

@implementation OAPopupDatePickerBackgroundView

- (void)drawRect:(NSRect)dirtyRect;
{
    NSAppearance *appearance = self.effectiveAppearance;
    BOOL isDark = OFISEQUAL(appearance.name, NSAppearanceNameVibrantDark);
    if (isDark) {
        [[NSColor controlBackgroundColor] set]; // windowBackgroundColor blends in with the black calendar days
    } else {
        [[NSColor windowBackgroundColor] set];
    }
    NSRectFill(dirtyRect);
}

@end
