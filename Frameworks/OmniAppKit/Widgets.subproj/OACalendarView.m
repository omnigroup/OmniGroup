// Copyright 2001-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OACalendarView.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/NSBezierPath-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>

RCS_ID("$Id$")


/*
    Some Notes:
    
    - Setting the View Size: see the notes in -initWithFrame: for some guidelines for determining what size you will want to give this view. Those notes also give information about font sizes and how they affect us and the size calculations. If you set the view size to a non-optimal size, we won't use all the space.
    
    - Dynamically Adjusting the Cell Display: check out the "delegate" method -calendarView:willDisplayCell:forDate: in order to adjust the cell attributes (such as the font color, etc.). Note that if you make any changes which impact the cell size, the calendar is unlikely to draw as desired, so this is mostly useful for color changes. You can also use -calendarView:highlightMaskForVisibleMonth: to get highlighting of certain days. This is more efficient since we need only ask once for the month rather than once for each cell, but it is far less flexible, and currently doesn't allow control over the highlight color used. Also, don't bother to implement both methods: only the former will be used if it is available.
    
    - We could benefit from some more configurability: specify whether or not to draw vertical/horizontal grid lines, grid and border widths, fonts, whether or not to display the top control area, whether or not the user can change the displayed month/year independant of whether they can change the selected date, etc.
    
    - We could be more efficient, such as in only calculating things we need. The biggest problem (probably) is that we recalculate everything on every -drawRect:, simply because I didn't see an ideal place to know when we've resized. (With the current implementation, the monthAndYearRect would also need to be recalculated any time the month or year changes, so that the month and year will be correctly centered.)
*/


@interface OACalendarView (/*Private*/)

- (NSButton *)_createButtonWithFrame:(NSRect)buttonFrame;

- (void)_calculateSizes;
- (void)_drawSelectionBackground:(NSRect)rect;
- (void)_drawDaysOfMonthInRect:(NSRect)rect;
- (void)_drawGridInRect:(NSRect)rect;

- (CGFloat)_maximumDayOfWeekWidth;
- (NSSize)_maximumDayOfMonthSize;
- (CGFloat)_minimumColumnWidth;
- (CGFloat)_minimumRowHeight;

- (NSDate *)_hitDateWithLocation:(NSPoint)targetPoint;
- (NSDate *)_hitWeekdayWithLocation:(NSPoint)targetPoint;

@end


@implementation OACalendarView
{
    NSCalendar *calendar;
    NSDate *visibleMonth;
    NSMutableArray *selectedDays;
    
    NSView *monthAndYearView;
    NSTextFieldCell *monthAndYearTextFieldCell;
    NSTextFieldCell *dayOfWeekCell[7];
    NSTextFieldCell *dayOfMonthCell;
    NSMutableArray *buttons;
    
    uint32_t dayHighlightMask;
    OACalendarViewSelectionType selectionType;
    NSInteger displayFirstDayOfWeek;
    
    CGFloat columnWidth;
    CGFloat rowHeight;
    NSRect monthAndYearRect;
    NSRect gridHeaderAndBodyRect;
    NSRect gridHeaderRect;
    NSRect gridBodyRect;
    
    struct {
        unsigned int showsDaysForOtherMonths:1;
        unsigned int targetProvidesHighlightMask:1;
        unsigned int targetWatchesCellDisplay:1;
        unsigned int targetWatchesVisibleMonth:1;
        unsigned int targetApprovesDateSelection:1;
    } flags;
}

const float OACalendarViewSpaceBetweenMonthYearAndGrid = 4.0f;
const int OACalendarViewNumDaysPerWeek = 7;
const int OACalendarViewMaxNumWeeksIntersectedByMonth = 6;

//
// Init / dealloc
//

// The calendar will only resize on certain boundaries. "Ideal" sizes are:
//     - width = (multiple of 7) + 1, where multiple >= 22; "minimum" width is 162
//     - height = (multiple of 6) + 39, where multiple >= 15; "minimum" height is 129

// In reality you can shrink it smaller than the minimums given here, and it tends to look ok for a bit, but this is the "optimum" minimum. But you will want to set your size based on the guidelines above, or the calendar will not actually fill the view exactly.

// The "minimum" view size comes out to be 162w x 129h. (Where minimum.width = 23 [minimum column width] * 7 [num days per week] + 1.0 [for the side border], and minimum.height = 22 [month/year control area height; includes the space between control area and grid] + 17 [the  grid header height] + (15 [minimum row height] * 6 [max num weeks in month]). [Don't need to allow 1 for the bottom border due to the fact that there's no top border per se.]) (We used to say that the minimum height was 155w x 123h, but that was wrong - we weren't including the grid lines in the row/column sizes.)
// These sizes will need to be adjusted if the font changes, grid or border widths change, etc. We use the controlContentFontOfSize:11.0 for the  - if the control content font is changed our calculations will change and the above sizes will be incorrect. Similarly, we use the default NSTextFieldCell font/size for the month/year header, and the default NSTableHeaderCell font/size for the day of week headers; if either of those change, the aove sizes will be incorrect.
- (void)_OACalendarView_sharedInit;
{
    NSRect boundsRect = [self bounds];
    NSDateFormatter *monthAndYearFormatter;
    int index;
    NSRect buttonFrame;
    NSButton *button;
    NSBundle *thisBundle;

    selectedDays = [[NSMutableArray alloc] init];

    thisBundle = [OACalendarView bundle];
    monthAndYearTextFieldCell = [[NSTextFieldCell alloc] init];
    [monthAndYearTextFieldCell setFont:[NSFont boldSystemFontOfSize:12.0f]];

    NSString *dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMM yyyy" options:0 locale:[NSLocale currentLocale]];
    monthAndYearFormatter = [[NSDateFormatter alloc] init];
    [monthAndYearFormatter setDateFormat:dateFormat];

    [monthAndYearTextFieldCell setFormatter:monthAndYearFormatter];
    [monthAndYearFormatter release];

    NSArray *shortWeekDays = [monthAndYearFormatter veryShortWeekdaySymbols];
    if (!shortWeekDays)
        shortWeekDays = [NSArray arrayWithObjects:@"S", @"M", @"T", @"W", @"T", @"F", @"S", nil];

    for (index = 0; index < OACalendarViewNumDaysPerWeek; index++) {
        dayOfWeekCell[index] = [[NSTextFieldCell alloc] init];
        [dayOfWeekCell[index] setAlignment:NSTextAlignmentCenter];
        [dayOfWeekCell[index] setStringValue:[shortWeekDays objectAtIndex:index]];
    }

    dayOfMonthCell = [[NSTextFieldCell alloc] init];
    [dayOfMonthCell setAlignment:NSTextAlignmentCenter];
    [dayOfMonthCell setFont:[NSFont systemFontOfSize:12.0f]];

    buttons = [[NSMutableArray alloc] initWithCapacity:2];
    NSImage *leftImage = OAImageNamed(@"OALeftArrow", thisBundle);
    NSSize imageSize = [leftImage size];

    NSRect _monthAndYearViewRect = NSMakeRect(boundsRect.origin.x, boundsRect.origin.y + 1.0f, boundsRect.size.width, imageSize.height);
    monthAndYearView = [[NSView alloc] initWithFrame:_monthAndYearViewRect];
    [monthAndYearView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];

    // Add left/right buttons

    buttonFrame = NSMakeRect(_monthAndYearViewRect.origin.x + 1.0f, _monthAndYearViewRect.origin.y, imageSize.width, imageSize.height);
    button = [self _createButtonWithFrame:buttonFrame];
    [button setImage:leftImage];
    [button setAlternateImage:OAImageNamed(@"OALeftArrowPressed", thisBundle)];
    [button setAction:@selector(previousMonth:)];
    [button setAutoresizingMask:NSViewMaxXMargin];
    [monthAndYearView addSubview:button];

    buttonFrame = NSMakeRect(NSMaxX(_monthAndYearViewRect) - 1.0f - imageSize.width, _monthAndYearViewRect.origin.y, imageSize.width, imageSize.height);
    button = [self _createButtonWithFrame:buttonFrame];
    [button setImage:OAImageNamed(@"OARightArrow", thisBundle)];
    [button setAlternateImage:OAImageNamed(@"OARightArrowPressed", thisBundle)];
    [button setAction:@selector(nextMonth:)];
    [button setAutoresizingMask:NSViewMinXMargin];
    [monthAndYearView addSubview:button];

    [self addSubview:monthAndYearView];
    [monthAndYearView release];

    //[self sizeToFit];
    //NSLog(@"frame: %@", NSStringFromRect([self frame]));

    NSDate *aDate = [NSDate date];
    NSDateComponents *dateComponents =  [calendar components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:aDate];
    [dateComponents setHour:12];
    aDate = [calendar dateFromComponents:dateComponents];
    [self setVisibleMonth:aDate];
    [self setSelectedDay:aDate];
}

- (id)initWithFrame:(NSRect)frameRect;
{
    self = [super initWithFrame:frameRect];
    if (self == nil) {
        return nil;
    }

    [self _OACalendarView_sharedInit];

    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    if (self == nil) {
        return nil;
    }

    [self _OACalendarView_sharedInit];

    return self;
}

- (void)dealloc;
{
    int index;

    [dayOfMonthCell release];

    for (index = 0; index < OACalendarViewNumDaysPerWeek; index++)
        [dayOfWeekCell[index] release];

    [monthAndYearTextFieldCell release];
    [buttons release];
    [visibleMonth release];
    [selectedDays release];
    
    [super dealloc];
}


//
// NSControl overrides
//

- (BOOL)acceptsFirstResponder;
{
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
{
   return YES;
}

- (void)setEnabled:(BOOL)flag;
{
    [super setEnabled:flag];

    for (NSButton *button in buttons)
        [button setEnabled:flag];
}

- (void)sizeToFit;
{
    NSSize minimumSize;

    // we need calculateSizes in order to get the monthAndYearRect; would be better to restructure some of that
    // it would be good to refactor the size calculation (or pass it some parameters) so that we could merely calculate the stuff we need (or have _calculateSizes do all our work, based on the parameters we provide)
    [self _calculateSizes];

    minimumSize.height = monthAndYearRect.size.height + gridHeaderRect.size.height + ((OACalendarViewMaxNumWeeksIntersectedByMonth * [self _minimumRowHeight]));
    // This should really check the lengths of the months, and include space for the buttons.
    minimumSize.width = ([self _minimumColumnWidth] * OACalendarViewNumDaysPerWeek) + 1.0f;

    [self setFrameSize:minimumSize];
    [self setNeedsDisplay:YES];
}


//
// NSView overrides
//

- (BOOL)isFlipped;
{
    return YES;
}

- (void)drawRect:(NSRect)rect;
{
    int columnIndex;
    NSRect tempRect;
    
    [self _calculateSizes];
    
// for testing, to see if there's anything we're not covering
//[[NSColor greenColor] set];
//NSRectFill(gridHeaderAndBodyRect);
// or...
//NSRectFill([self bounds]);
    
    [[NSColor controlBackgroundColor] set];
    NSRectFill(rect);
    
    // draw the month/year
    [monthAndYearTextFieldCell drawWithFrame:monthAndYearRect inView:self];
    
    // draw the grid header
    tempRect = gridHeaderRect;
    tempRect.size.width = columnWidth;
    for (columnIndex = 0; columnIndex < OACalendarViewNumDaysPerWeek; columnIndex++) {
        [dayOfWeekCell[(columnIndex+displayFirstDayOfWeek)%OACalendarViewNumDaysPerWeek] drawWithFrame:tempRect inView:self];
        tempRect.origin.x += columnWidth;
    }
    
    // draw the weeks and selection
    [self _drawSelectionBackground:gridBodyRect];
    
    // draw the grid
    [self _drawGridInRect:gridBodyRect];

    // fill in the days in the grid
    [self _drawDaysOfMonthInRect:gridBodyRect];
    
    // draw a border around the whole thing. This ends up drawing over the top and right side borders of the header, but that's ok because we don't want their border, we want ours. Also, it ends up covering any overdraw from selected sundays and saturdays, since the selected day covers the bordering area where vertical grid lines would be (an aesthetic decision because we don't draw vertical grid lines, another aesthetic decision).
    [[NSColor gridColor] set];
    NSFrameRect(rect);
}

- (void)mouseDown:(NSEvent *)mouseEvent;
{
    if ([self isEnabled]) {
        NSPoint location = [self convertPoint:[mouseEvent locationInWindow] fromView:nil];
        NSDate *hitDate = [self _hitDateWithLocation:location];
        id target = [self target];
        if (hitDate) {
            if (!flags.targetApprovesDateSelection || [_delegate calendarView:self shouldSelectDate:hitDate]) {
                [self setSelectedDay:hitDate];
                if (flags.showsDaysForOtherMonths)
                    [self setVisibleMonth:hitDate];
                [self sendAction:[self action] to:target];
            }
            
        } else if (selectionType == OACalendarViewSelectByWeekday) {
            NSDate *hitWeekday = [self _hitWeekdayWithLocation:location];
            if (hitWeekday) {
                if (!flags.targetApprovesDateSelection || [_delegate calendarView:self shouldSelectDate:hitWeekday]) {
                    [self setSelectedDay:hitWeekday];
                    [self sendAction:[self action] to:target];
                }
            }
        }
    }
}


//
// API
//

@synthesize calendar;

- (NSDate *)visibleMonth;
{
    return visibleMonth;
}

- (void)setVisibleMonth:(NSDate *)aDate;
{
    NSDateComponents *components = [calendar components:NSCalendarUnitEra | NSCalendarUnitYear| NSCalendarUnitMonth fromDate:aDate];
    aDate = [calendar dateFromComponents:components];
    
    if ([aDate isEqual:visibleMonth])
        return;
    
    [visibleMonth release];
    visibleMonth = [aDate retain];
    [monthAndYearTextFieldCell setObjectValue:visibleMonth];

    [self updateHighlightMask];
    [self setNeedsDisplay:YES];
    
    if (flags.targetWatchesVisibleMonth)
        [_delegate calendarView:self didChangeVisibleMonth:visibleMonth];
}

- (NSDate *)selectedDay;
{
    return [selectedDays count] ? [selectedDays objectAtIndex:0] : nil;
}

#define DAY_IN_SECONDS 86400

- (void)setSelectedDay:(NSDate *)newSelectedDay;
{
    if ([selectedDays containsObject:newSelectedDay])
        return;
    if (newSelectedDay == nil) {
	[selectedDays removeAllObjects];
        [self setNeedsDisplay:YES];
	return;
    }
    
    if (0 == [selectedDays count]) {
	[selectedDays addObject:newSelectedDay];
        [self setNeedsDisplay:YES];
	return;
    }
    
    NSEvent *event = [[NSApplication sharedApplication] currentEvent];
    NSUInteger kflags = [event modifierFlags];
    BOOL shiftMask = (0 != (kflags & NSEventModifierFlagShift));
    BOOL commandMask = (0 != (kflags & NSEventModifierFlagCommand));
    
    NSDate *startDate = [selectedDays objectAtIndex:0];
    if (shiftMask) {

	NSTimeInterval start = [startDate timeIntervalSince1970];
	NSTimeInterval end = [newSelectedDay timeIntervalSince1970];
	
	if (start > end) {
	    NSTimeInterval t = end;
	    end = start;
	    start = t;
	}

	[selectedDays removeAllObjects];
	
	while (start <= end ) {
	    NSDate *date = [NSDate dateWithTimeIntervalSince1970:start];
	    [selectedDays addObject:date];
	    start+= DAY_IN_SECONDS;
	}
    } else if (commandMask) {
	[selectedDays addObject:newSelectedDay];
    } else {
	[selectedDays removeAllObjects];
	[selectedDays addObject:newSelectedDay];
    }
    
    [self setNeedsDisplay:YES];
}

- (int)dayHighlightMask;
{
    return dayHighlightMask;
}

- (void)setDayHighlightMask:(int)newMask;
{
    dayHighlightMask = newMask;
    [self setNeedsDisplay:YES];
}

- (void)updateHighlightMask;
{
    if (flags.targetProvidesHighlightMask) {
        int mask;
        mask = [_delegate calendarView:self highlightMaskForVisibleMonth:visibleMonth];
        [self setDayHighlightMask:mask];
    } else
        [self setDayHighlightMask:0];

    [self setNeedsDisplay:YES];
}

- (BOOL)showsDaysForOtherMonths;
{
    return flags.showsDaysForOtherMonths;
}

- (void)setShowsDaysForOtherMonths:(BOOL)value;
{
    BOOL showsDaysForOtherMonths = (flags.showsDaysForOtherMonths != 0);
    if (value != showsDaysForOtherMonths) {
        flags.showsDaysForOtherMonths = value ? 1 : 0;

        [self setNeedsDisplay:YES];
    }
}

- (OACalendarViewSelectionType)selectionType;
{
    return selectionType;
}

- (void)setSelectionType:(OACalendarViewSelectionType)value;
{
    OBASSERT((value == OACalendarViewSelectByDay) || (value == OACalendarViewSelectByWeek) || (value == OACalendarViewSelectByWeekday));
    if (selectionType != value) {
        selectionType = value;

        [self setNeedsDisplay:YES];
    }
}

- (NSInteger)firstDayOfWeek;
{
    return displayFirstDayOfWeek;
}

- (void)setFirstDayOfWeek:(NSInteger)weekDay;
{
    if (displayFirstDayOfWeek != weekDay) {
        displayFirstDayOfWeek = weekDay;
        [self setNeedsDisplay:YES];
    }
}

- (NSArray *)selectedDays;
{
    if (!selectedDays || [selectedDays count] <= 0 )
        return nil;

    NSDate *selectedDay = [self selectedDay];
    
    switch (selectionType) {
        case OACalendarViewSelectByDay:
            return selectedDays;
            break;
            
        case OACalendarViewSelectByWeek:
            {
                NSMutableArray *days;
                int index;
                
                days = [NSMutableArray arrayWithCapacity:OACalendarViewNumDaysPerWeek];
                NSDateComponents *components = [calendar components:NSCalendarUnitWeekday fromDate:selectedDay];
                [components setWeekday:-([components weekday] -1)];
                NSDate *day = [calendar dateByAddingComponents:components toDate:selectedDay options:NSCalendarWrapComponents];
                NSDateComponents *selectedMonth = [calendar components:NSCalendarUnitMonth fromDate:selectedDay];
                for (index = 0; index < OACalendarViewNumDaysPerWeek; index++) {
                    [components setDay:index];
                    NSDate *nextDay = [calendar dateByAddingComponents:components toDate:day options:NSCalendarWrapComponents];
                    NSDateComponents *monthComponent = [calendar components:NSCalendarUnitMonth fromDate:nextDay];
                    if (flags.showsDaysForOtherMonths || [monthComponent month] == [selectedMonth month])
                        [days addObject:nextDay];                    
                }
            
                return days;
            }            
            break;

        case OACalendarViewSelectByWeekday:
            {
                NSMutableArray *days;
                int index;
             
                // <bug:///104043> (Unassigned: -[NSDateComponents week], -setWeek: deprecated)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                days = [NSMutableArray arrayWithCapacity:OACalendarViewMaxNumWeeksIntersectedByMonth];
                NSDateComponents *components = [calendar components:NSWeekCalendarUnit fromDate:selectedDay];
                [components setWeek:-([components week] -1)];
                NSDate *day = [calendar dateByAddingComponents:components toDate:selectedDay options:NSCalendarWrapComponents];
                [components setWeek:0];
                NSDateComponents *selectedMonth = [calendar components:NSCalendarUnitMonth fromDate:selectedDay];
                for (index = 0; index < OACalendarViewMaxNumWeeksIntersectedByMonth; index++) {
                    [components setDay:(index * OACalendarViewNumDaysPerWeek)];
                    NSDate *nextDay = [calendar dateByAddingComponents:components toDate:day options:NSCalendarWrapComponents];
                    NSDateComponents *monthComponent = [calendar components:NSCalendarUnitMonth fromDate:nextDay];
                    if (flags.showsDaysForOtherMonths || [monthComponent month] == [selectedMonth month])
                        [days addObject:nextDay];
                }
#pragma clang diagnostic pop

                return days;
            }
            break;
            
        default:
            [NSException raise:NSInvalidArgumentException format:@"OACalendarView: Unknown selection type: %d", selectionType];
            return nil;
            break;
    }
}


//
// Actions
//

- (IBAction)previousMonth:(id)sender;
{
    if (([[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSEventModifierFlagOption) != 0)
        return [self previousYear:sender];
    
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setMonth:-1];
    [self setVisibleMonth:[calendar dateByAddingComponents:components toDate:visibleMonth options:0]];
    [components release];
}

- (IBAction)nextMonth:(id)sender;
{
    if (([[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSEventModifierFlagOption) != 0)
        return [self nextYear:sender];

    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setMonth:1];
    [self setVisibleMonth:[calendar dateByAddingComponents:components toDate:visibleMonth options:0]];
    [components release];
}

- (IBAction)previousYear:(id)sender;
{
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setYear:-1];
    [self setVisibleMonth:[calendar dateByAddingComponents:components toDate:visibleMonth options:0]];
    [components release];
}

- (IBAction)nextYear:(id)sender;
{
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setYear:+1];
    [self setVisibleMonth:[calendar dateByAddingComponents:components toDate:visibleMonth options:0]];
    [components release];
}

#pragma mark -
#pragma mark Private

- (NSButton *)_createButtonWithFrame:(NSRect)buttonFrame;
{
    NSButton *button;
    
    button = [[NSButton alloc] initWithFrame:buttonFrame];
    [button setBezelStyle:NSBezelStyleShadowlessSquare];
    [button setBordered:NO];
    [button setImagePosition:NSImageOnly];
    [button setTarget:self];
    [button setContinuous:YES];
    [[button cell] setShowsStateBy:(NSPushInCellMask | NSChangeGrayCellMask | NSChangeBackgroundCellMask)];
    [buttons addObject:button];
    [button release];

    return button;
}

- (void)setDelegate:(NSObject <OACalendarViewDelegate> *)delegate;
{
    _delegate = delegate;
    
    flags.targetProvidesHighlightMask = [delegate respondsToSelector:@selector(calendarView:highlightMaskForVisibleMonth:)];
    flags.targetWatchesCellDisplay = [delegate respondsToSelector:@selector(calendarView:willDisplayCell:forDate:)];
    flags.targetApprovesDateSelection = [delegate respondsToSelector:@selector(calendarView:shouldSelectDate:)];
    flags.targetWatchesVisibleMonth = [delegate respondsToSelector:@selector(calendarView:didChangeVisibleMonth:)];
}

- (void)_calculateSizes;
{
    NSSize cellSize;
    NSRect viewBounds;
    NSRect topRect;
    NSRect discardRect;
    NSRect tempRect;

    viewBounds = [self bounds];
    
    // get the grid cell width (subtract 1.0 from the bounds width to allow for the border)
    columnWidth = (viewBounds.size.width - 1.0f) / OACalendarViewNumDaysPerWeek;
    viewBounds.size.width = (columnWidth * OACalendarViewNumDaysPerWeek) + 1.0f;
    
    // resize the month & year view to be the same width as the grid
    [monthAndYearView setFrameSize:NSMakeSize(viewBounds.size.width, [monthAndYearView frame].size.height)];

    // get the rect for the month and year text field cell
    cellSize = [monthAndYearTextFieldCell cellSize];
    NSDivideRect(viewBounds, &topRect, &gridHeaderAndBodyRect, (CGFloat)ceil(cellSize.height + OACalendarViewSpaceBetweenMonthYearAndGrid), NSMinYEdge);
    NSDivideRect(topRect, &discardRect, &monthAndYearRect, (CGFloat)floor((viewBounds.size.width - cellSize.width) / 2), NSMinXEdge);
    monthAndYearRect.size.width = cellSize.width;
    
    tempRect = gridHeaderAndBodyRect;
    // leave space for a one-pixel border on each side
    tempRect.size.width -= 2.0f;
    tempRect.origin.x += 1.0f;
    // leave space for a one-pixel border at the bottom (the top already looks fine)
    tempRect.size.height -= 1.0f;

    // get the grid header rect
    cellSize = [dayOfWeekCell[0] cellSize];
    NSDivideRect(tempRect, &gridHeaderRect, &gridBodyRect, (CGFloat)ceil(cellSize.height), NSMinYEdge);
    
    // get the grid row height (add 1.0 to the body height because while we can't actually draw on that extra pixel, our bottom row doesn't have to draw a bottom grid line as there's a border right below us, so we need to account for that, which we do by pretending that next pixel actually does belong to us)
    rowHeight = (CGFloat)floor((gridBodyRect.size.height + 1.0f) / OACalendarViewMaxNumWeeksIntersectedByMonth);
    
    // get the grid body rect
    gridBodyRect.size.height = (rowHeight * OACalendarViewMaxNumWeeksIntersectedByMonth) - 1.0f;
    
    // adjust the header and body rect to account for any adjustment made while calculating even row heights
    gridHeaderAndBodyRect.size.height = NSMaxY(gridBodyRect) - NSMinY(gridHeaderAndBodyRect) + 1.0f;
}

- (void)_drawSelectionBackground:(NSRect)rect;
{
    switch (selectionType) {
	case OACalendarViewSelectByDay:
	    // UNDONE
	    break;
	case OACalendarViewSelectByWeek: {
            NSDateComponents *thisDayComponents = [calendar components:NSCalendarUnitWeekday fromDate:visibleMonth];
            NSInteger columnOfFirstOfMonth = ([thisDayComponents weekday] - 1) - displayFirstDayOfWeek;

            if (columnOfFirstOfMonth < 0)
                columnOfFirstOfMonth += 7;

            NSInteger dayOfMonthInLastColumn = OACalendarViewNumDaysPerWeek - columnOfFirstOfMonth;
            NSDateComponents *selectedComponents = [calendar components:NSCalendarUnitDay|NSCalendarUnitMonth fromDate:[self selectedDay]];
            NSInteger dayOfMonthOfSelectedDay = [selectedComponents day];
            NSInteger selectedRow = (dayOfMonthOfSelectedDay - dayOfMonthInLastColumn + (OACalendarViewNumDaysPerWeek-1)) / OACalendarViewNumDaysPerWeek;

	    NSRect weekRect; 
	    weekRect.size.height = rowHeight;
	    weekRect.size.width = rect.size.width;
	    weekRect.origin.x = rect.origin.x;
	    weekRect.origin.y = rect.origin.y + (selectedRow * rowHeight);
	    
            if ([self isOrContainsFirstResponder])
                [[NSColor selectedTextBackgroundColor] set];
            else
                [[NSColor unemphasizedSelectedContentBackgroundColor] set];

	    [NSBezierPath fillRect:weekRect];
	    break;
	} case OACalendarViewSelectByWeekday:
	    // UNDONE
	    break;
    }
}

- (void)_drawGridInRect:(NSRect)rect;
{
    NSRect drawRect = rect;
    int lineIndex;
    
    [[NSColor gridColor] set];
    
    drawRect.size.width = 1.0f;
    for (lineIndex = 1; lineIndex < (OACalendarViewNumDaysPerWeek); lineIndex++) {
	drawRect.origin.x = floor(drawRect.origin.x + columnWidth);
	[NSBezierPath fillRect:drawRect];
    }
    
    drawRect = rect;
    drawRect.size.height = 1.0f;
    for (lineIndex = 0; lineIndex < OACalendarViewMaxNumWeeksIntersectedByMonth+1; lineIndex++) {
	[NSBezierPath fillRect:drawRect];
	drawRect.origin.y = floor(drawRect.origin.y + rowHeight);
    }
}

- (void)_drawDaysOfMonthInRect:(NSRect)rect;
{
    NSRect cellFrame;
    int index, row, column;
    NSSize cellSize;

    // the cell is actually one pixel shorter than the row height, because the row height includes the bottom grid line (or the top grid line, depending on which way you prefer to think of it)
    cellFrame.size.height = rowHeight - 1.0f;
    // the cell would actually be one pixel narrower than the column width but we don't draw vertical grid lines. instead, we want to include the area that would be grid line (were we drawing it) in our cell, because that looks a bit better under the header, which _does_ draw column separators. actually, we want to include the grid line area on _both sides_ or it looks unbalanced, so we actually _add_ one pixel, to cover that. below, our x position as we draw will have to take that into account. note that this means that sunday and saturday overwrite the outside borders, but the outside border is drawn last, so it ends up ok. (if we ever start drawing vertical grid lines, change this to be - 1.0, and adjust the origin appropriately below.)
    cellFrame.size.width = columnWidth - 1.0f;

    cellSize = [dayOfMonthCell cellSize];
    
    NSDateComponents *visibleMonthComponents = [calendar components:NSCalendarUnitMonth | NSCalendarUnitWeekday fromDate:visibleMonth];
    NSInteger visibleMonthIndex = [visibleMonthComponents month];

    NSInteger dayOffset = displayFirstDayOfWeek - ([visibleMonthComponents weekday] - 1);
    if (dayOffset > 0)
        dayOffset -= OACalendarViewNumDaysPerWeek;

    NSDateComponents *dayOffsetComponents = [[NSDateComponents alloc] init];
    [dayOffsetComponents setDay:dayOffset];
    NSDate *thisDay = [calendar dateByAddingComponents:dayOffsetComponents toDate:visibleMonth options:0];
    [dayOffsetComponents setDay:1];
    
    for (row = column = index = 0; index < OACalendarViewMaxNumWeeksIntersectedByMonth * OACalendarViewNumDaysPerWeek; index++) {
        NSColor *textColor;
        BOOL isVisibleMonth;

        cellFrame.origin.x = rect.origin.x + (column * columnWidth);
        cellFrame.origin.y = rect.origin.y + (row * rowHeight) + 1.0f;

        NSDateComponents *thisDayComponents = [calendar components:NSCalendarUnitMonth | NSCalendarUnitWeekday | NSCalendarUnitDay fromDate:thisDay];
        [dayOfMonthCell setIntegerValue:[thisDayComponents day]];
        isVisibleMonth = ([thisDayComponents month] == visibleMonthIndex);

        if (flags.showsDaysForOtherMonths || isVisibleMonth) {
	    
	    BOOL shouldHighlightThisDay = NO;
	    NSDate *selectedDay = [self selectedDay];
	    
	    if (selectedDay) {
 
                // We could just check if thisDay is in [self selectedDays]. However, that makes the selection look somewhat weird when we
                // are selecting by weekday, showing days for other months, and the visible month is the previous/next from the selected day.
                // (Some of the weekdays are shown as highlighted, and later ones are not.)
                // So, we fib a little to make things look better.
                switch (selectionType) {
                    case OACalendarViewSelectByDay:
                        shouldHighlightThisDay = ([selectedDays containsObject:thisDay]);
                        break;
                        
                    case OACalendarViewSelectByWeek:
                        shouldHighlightThisDay = NO; // handled by _drawSelectionBackground:, the other cases should eventually be done that way as well
                        break;
                        
                    case OACalendarViewSelectByWeekday:
                    {
                        NSDateComponents *selectedDayComponents = [calendar components:NSCalendarUnitMonth | NSCalendarUnitWeekday fromDate:selectedDay];
                        shouldHighlightThisDay = ([selectedDayComponents month] == visibleMonthIndex && [selectedDayComponents day] == [thisDayComponents day]);
                        break;
                    }  
                    default:
                        [NSException raise:NSInvalidArgumentException format:@"OACalendarView: Unknown selection type: %d", selectionType];
                        break;
                }
                
            }
            	    
            if (flags.targetWatchesCellDisplay) {
                [_delegate calendarView:self willDisplayCell:dayOfMonthCell forDate:thisDay];
            } else {
                if ((dayHighlightMask & (1 << index)) == 0) {
                    textColor = (isVisibleMonth ? [NSColor blackColor] : [NSColor grayColor]);
                } else {
                    textColor = [NSColor blueColor];
                }
                [dayOfMonthCell setTextColor:textColor];
            }
	    
	    if ([dayOfMonthCell drawsBackground]) {
		[[dayOfMonthCell backgroundColor] set];
		[NSBezierPath fillRect:cellFrame];
		[dayOfMonthCell setDrawsBackground:NO];
	    }

	    NSRect discardRect, dayOfMonthFrame;
            NSDivideRect(cellFrame, &discardRect, &dayOfMonthFrame, (CGFloat)floor((cellFrame.size.height - cellSize.height) / 2.0), NSMinYEdge);
	    [dayOfMonthCell drawInteriorWithFrame:dayOfMonthFrame inView:self];

	    if (shouldHighlightThisDay && [self isEnabled]) {
		[[NSColor selectedControlColor] set];
		NSBezierPath *outlinePath = [NSBezierPath bezierPathWithRect:cellFrame];
		[outlinePath setLineWidth:2.0f];
		[outlinePath stroke];
	    }
        }
        
        thisDay = [calendar dateByAddingComponents:dayOffsetComponents toDate:thisDay options:0];
        column++;
        if (column > OACalendarViewMaxNumWeeksIntersectedByMonth) {
            column = 0;
            row++;
        }
    }
    
    [dayOffsetComponents release];
}

- (CGFloat)_maximumDayOfWeekWidth;
{
    CGFloat maxWidth;
    int index;

    maxWidth = 0;
    for (index = 0; index < OACalendarViewNumDaysPerWeek; index++) {
        NSSize cellSize;

        cellSize = [dayOfWeekCell[index] cellSize];
        if (maxWidth < cellSize.width)
            maxWidth = cellSize.width;
    }

    return (CGFloat)ceil(maxWidth);
}

- (NSSize)_maximumDayOfMonthSize;
{
    NSSize maxSize;
    int index;

    maxSize = NSZeroSize; // I'm sure the height doesn't change, but I need to know the height anyway.
    for (index = 1; index <= 31; index++) {
        NSString *str;
        NSSize cellSize;

        str = [NSString stringWithFormat:@"%d", index];
        [dayOfMonthCell setStringValue:str];
        cellSize = [dayOfMonthCell cellSize];
        if (maxSize.width < cellSize.width)
            maxSize.width = cellSize.width;
        if (maxSize.height < cellSize.height)
            maxSize.height = cellSize.height;
    }

    maxSize.width = (CGFloat)ceil(maxSize.width);
    maxSize.height = (CGFloat)ceil(maxSize.height);

    return maxSize;
}

- (CGFloat)_minimumColumnWidth;
{
    CGFloat dayOfWeekWidth;
    CGFloat dayOfMonthWidth;
    
    dayOfWeekWidth = [self _maximumDayOfWeekWidth];	// we don't have to add 1.0 because the day of week cell whose width is returned here includes it's own border
    dayOfMonthWidth = [self _maximumDayOfMonthSize].width + 1.0f;	// add 1.0 to allow for the grid. We don't actually draw the vertical grid, but we treat it as if there was one (don't respond to clicks "on" the grid, we have a vertical separator in the header, etc.) 
    return (dayOfMonthWidth > dayOfWeekWidth) ? dayOfMonthWidth : dayOfWeekWidth;
}

- (CGFloat)_minimumRowHeight;
{
    return [self _maximumDayOfMonthSize].height + 1.0f;	// add 1.0 to allow for a bordering grid line
}

- (NSDate *)_hitDateWithLocation:(NSPoint)targetPoint;
{
    NSInteger hitRow, hitColumn;
    NSInteger targetDayOfMonth;
    NSPoint offset;

    if (NSPointInRect(targetPoint, gridBodyRect) == NO)
        return nil;

    NSDateComponents *thisDayComponents = [calendar components:NSCalendarUnitWeekday fromDate:visibleMonth];
    NSInteger columnOfFirstOfMonth = ([thisDayComponents weekday] - 1) - displayFirstDayOfWeek;
    
    if (columnOfFirstOfMonth < 0)
        columnOfFirstOfMonth += 7;

    offset = NSMakePoint(targetPoint.x - gridBodyRect.origin.x, targetPoint.y - gridBodyRect.origin.y);
    // if they exactly hit the grid between days, treat that as a miss
    if ((selectionType != OACalendarViewSelectByWeekday) && (((NSInteger)offset.y % (NSInteger)rowHeight) == 0))
        return nil;
    // if they exactly hit the grid between days, treat that as a miss
    if ((selectionType != OACalendarViewSelectByWeek) && ((NSInteger)offset.x % (NSInteger)columnWidth) == 0)
        return nil;
    hitRow = (NSInteger)(offset.y / rowHeight);
    hitColumn = (NSInteger)(offset.x / columnWidth);
    
    targetDayOfMonth = (hitRow * OACalendarViewNumDaysPerWeek) + hitColumn - columnOfFirstOfMonth + 1;
    NSRange rangeOfDaysInMonth = [calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:visibleMonth];
    if (selectionType == OACalendarViewSelectByWeek) {
        if (targetDayOfMonth < 1)
            targetDayOfMonth = 1;
        else if (targetDayOfMonth >= 0 && (NSUInteger)targetDayOfMonth > rangeOfDaysInMonth.length)
            targetDayOfMonth = rangeOfDaysInMonth.length;
    } else if (!flags.showsDaysForOtherMonths && (targetDayOfMonth < 1 || (targetDayOfMonth > 0 && (NSUInteger)targetDayOfMonth > rangeOfDaysInMonth.length))) {
        return nil;
    }

    NSDateComponents *targetDayComponent = [[[NSDateComponents alloc] init] autorelease];
    [targetDayComponent setDay:targetDayOfMonth-1];
    return [calendar dateByAddingComponents:targetDayComponent toDate:visibleMonth options:NSCalendarWrapComponents];
}

- (NSDate *)_hitWeekdayWithLocation:(NSPoint)targetPoint;
{
    NSInteger hitDayOfWeek;
    NSInteger targetDayOfMonth;
    CGFloat offsetX;

    if (NSPointInRect(targetPoint, gridHeaderRect) == NO)
        return nil;
    
    offsetX = targetPoint.x - gridHeaderRect.origin.x;
    // if they exactly hit a border between weekdays, treat that as a miss (besides being neat in general, this avoids the problem where clicking on the righthand border would result in us incorrectly calculating that the _first_ day of the week was hit)
    if (((NSInteger)offsetX % (NSInteger)columnWidth) == 0)
        return nil;
    
    hitDayOfWeek = ((NSInteger)(offsetX / columnWidth) + displayFirstDayOfWeek) % OACalendarViewNumDaysPerWeek;

    NSDateComponents *thisDayComponents = [calendar components:NSCalendarUnitDay fromDate:visibleMonth];
    [thisDayComponents setDay:-([thisDayComponents day] - 1)];
    NSDate *firstDayOfMonth = [calendar dateByAddingComponents:thisDayComponents toDate:visibleMonth options:NSCalendarWrapComponents];
    NSDateComponents *firstDayComponents = [calendar components:NSCalendarUnitWeekday fromDate:firstDayOfMonth];

    NSInteger firstDayOfWeek = [firstDayComponents weekday];
    if (hitDayOfWeek >= firstDayOfWeek)
        targetDayOfMonth = hitDayOfWeek - firstDayOfWeek + 1;
    else
        targetDayOfMonth = hitDayOfWeek + OACalendarViewNumDaysPerWeek - firstDayOfWeek + 1;

    NSDateComponents *targetDayComponent = [[[NSDateComponents alloc] init] autorelease];
    [targetDayComponent setDay:targetDayOfMonth-1];
    return [calendar dateByAddingComponents:targetDayComponent toDate:visibleMonth options:NSCalendarWrapComponents];
}

@end
