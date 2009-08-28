// Copyright 2001-2008 Omni Development, Inc.  All rights reserved.
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
    
    - We should have a real delegate instead of treating the target as the delgate.
    
    - We could benefit from some more configurability: specify whether or not to draw vertical/horizontal grid lines, grid and border widths, fonts, whether or not to display the top control area, whether or not the user can change the displayed month/year independant of whether they can change the selected date, etc.
    
    - We could be more efficient, such as in only calculating things we need. The biggest problem (probably) is that we recalculate everything on every -drawRect:, simply because I didn't see an ideal place to know when we've resized. (With the current implementation, the monthAndYearRect would also need to be recalculated any time the month or year changes, so that the month and year will be correctly centered.)
*/


@interface OACalendarView (Private)

- (NSButton *)_createButtonWithFrame:(NSRect)buttonFrame;

- (void)_calculateSizes;
- (void)_drawSelectionBackground:(NSRect)rect;
- (void)_drawDaysOfMonthInRect:(NSRect)rect;

- (float)_maximumDayOfWeekWidth;
- (NSSize)_maximumDayOfMonthSize;
- (float)_minimumColumnWidth;
- (float)_minimumRowHeight;

- (NSCalendarDate *)_hitDateWithLocation:(NSPoint)targetPoint;
- (NSCalendarDate *)_hitWeekdayWithLocation:(NSPoint)targetPoint;

@end


@implementation OACalendarView

const float OACalendarViewButtonWidth = 15.0;
const float OACalendarViewButtonHeight = 15.0;
const float OACalendarViewSpaceBetweenMonthYearAndGrid = 2.0;
const int OACalendarViewNumDaysPerWeek = 7;
const int OACalendarViewMaxNumWeeksIntersectedByMonth = 6;

//
// Init / dealloc
//

- (id)initWithFrame:(NSRect)frameRect;
{
    // The calendar will only resize on certain boundaries. "Ideal" sizes are: 
    //     - width = (multiple of 7) + 1, where multiple >= 22; "minimum" width is 162
    //     - height = (multiple of 6) + 39, where multiple >= 15; "minimum" height is 129
    
    // In reality you can shrink it smaller than the minimums given here, and it tends to look ok for a bit, but this is the "optimum" minimum. But you will want to set your size based on the guidelines above, or the calendar will not actually fill the view exactly.

    // The "minimum" view size comes out to be 162w x 129h. (Where minimum.width = 23 [minimum column width] * 7 [num days per week] + 1.0 [for the side border], and minimum.height = 22 [month/year control area height; includes the space between control area and grid] + 17 [the  grid header height] + (15 [minimum row height] * 6 [max num weeks in month]). [Don't need to allow 1 for the bottom border due to the fact that there's no top border per se.]) (We used to say that the minimum height was 155w x 123h, but that was wrong - we weren't including the grid lines in the row/column sizes.)
    // These sizes will need to be adjusted if the font changes, grid or border widths change, etc. We use the controlContentFontOfSize:11.0 for the  - if the control content font is changed our calculations will change and the above sizes will be incorrect. Similarly, we use the default NSTextFieldCell font/size for the month/year header, and the default NSTableHeaderCell font/size for the day of week headers; if either of those change, the aove sizes will be incorrect.

    NSDateFormatter *monthAndYearFormatter;
    int index;
    NSArray *shortWeekDays;
    NSRect buttonFrame;
    NSButton *button;
    NSBundle *thisBundle;

    if ([super initWithFrame:frameRect] == nil)
        return nil;
    
    selectedDays = [[NSMutableArray alloc] init];
    
    thisBundle = [OACalendarView bundle];
    monthAndYearTextFieldCell = [[NSTextFieldCell alloc] init];
    monthAndYearFormatter = [[NSDateFormatter alloc] initWithDateFormat:@"%B %Y" allowNaturalLanguage:NO];
    [monthAndYearTextFieldCell setFormatter:monthAndYearFormatter];
    [monthAndYearFormatter release];

#if defined(MAC_OS_X_VERSION_10_5) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    // This works under 10.5, but 10.6 10A222 returns nil (Radar 6533889)
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    shortWeekDays = [formatter shortWeekdaySymbols];
    if (!shortWeekDays)
        shortWeekDays = [NSArray arrayWithObjects:@"Sun", @"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat", nil];
#else
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    shortWeekDays = [defaults objectForKey:NSShortWeekDayNameArray];
#endif
    OBASSERT(shortWeekDays);
    
    for (index = 0; index < OACalendarViewNumDaysPerWeek; index++) {
	dayOfWeekCell[index] = [[NSTextFieldCell alloc] init];
        [dayOfWeekCell[index] setAlignment:NSCenterTextAlignment];
        [dayOfWeekCell[index] setStringValue:[[shortWeekDays objectAtIndex:index] substringToIndex:1]];
    }

    dayOfMonthCell = [[NSTextFieldCell alloc] init];
    [dayOfMonthCell setAlignment:NSCenterTextAlignment];
    [dayOfMonthCell setFont:[NSFont boldSystemFontOfSize:9.0]];

    buttons = [[NSMutableArray alloc] initWithCapacity:2];

    NSRect _monthAndYearViewRect = NSMakeRect(frameRect.origin.x, frameRect.origin.y, frameRect.size.width, OACalendarViewButtonHeight);
    monthAndYearView = [[NSView alloc] initWithFrame:_monthAndYearViewRect];
    [monthAndYearView setAutoresizingMask:NSViewWidthSizable];

    // Add left/right buttons

    buttonFrame = NSMakeRect(_monthAndYearViewRect.origin.x, _monthAndYearViewRect.origin.y, OACalendarViewButtonWidth, OACalendarViewButtonHeight);
    button = [self _createButtonWithFrame:buttonFrame];
    [button setImage:[NSImage imageNamed:@"OALeftArrow" inBundle:thisBundle]];
    [button setAlternateImage:[NSImage imageNamed:@"OALeftArrowPressed" inBundle:thisBundle]];
    [button setAction:@selector(previousMonth:)];
    [button setAutoresizingMask:NSViewMaxXMargin];
    [monthAndYearView addSubview:button];

    buttonFrame = NSMakeRect(_monthAndYearViewRect.origin.x + _monthAndYearViewRect.size.width - OACalendarViewButtonWidth, _monthAndYearViewRect.origin.y, OACalendarViewButtonWidth, OACalendarViewButtonHeight);
    button = [self _createButtonWithFrame:buttonFrame];
    [button setImage:[NSImage imageNamed:@"OARightArrow" inBundle:thisBundle]];
    [button setAlternateImage:[NSImage imageNamed:@"OARightArrowPressed" inBundle:thisBundle]];
    [button setAction:@selector(nextMonth:)];
    [button setAutoresizingMask:NSViewMinXMargin];
    [monthAndYearView addSubview:button];

    [self addSubview:monthAndYearView];
    [monthAndYearView release];

//[self sizeToFit];
//NSLog(@"frame: %@", NSStringFromRect([self frame]));

    NSCalendarDate *aDate = [NSCalendarDate calendarDate];
    aDate = [NSCalendarDate dateWithYear:[aDate yearOfCommonEra] month:[aDate monthOfYear] day:[aDate dayOfMonth] hour:12 minute:0 second:0 timeZone:[aDate timeZone]];
    [self setVisibleMonth:aDate];
    [self setSelectedDay:aDate];
    
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

+ (Class)cellClass;
{
    // We need to have an NSActionCell (or subclass of that) to handle the target and action; otherwise, you just can't set those values.
    return [NSActionCell class];
}

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
    unsigned int buttonIndex;

    [super setEnabled:flag];
    
    buttonIndex = [buttons count];
    while (buttonIndex--)
        [[buttons objectAtIndex:buttonIndex] setEnabled:flag];
}

- (void)sizeToFit;
{
    NSSize minimumSize;

    // we need calculateSizes in order to get the monthAndYearRect; would be better to restructure some of that
    // it would be good to refactor the size calculation (or pass it some parameters) so that we could merely calculate the stuff we need (or have _calculateSizes do all our work, based on the parameters we provide)
    [self _calculateSizes];

    minimumSize.height = monthAndYearRect.size.height + gridHeaderRect.size.height + ((OACalendarViewMaxNumWeeksIntersectedByMonth * [self _minimumRowHeight]));
    // This should really check the lengths of the months, and include space for the buttons.
    minimumSize.width = ([self _minimumColumnWidth] * OACalendarViewNumDaysPerWeek) + 1.0;

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
    
    // draw a white background
    [[NSColor whiteColor] set];
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

    // fill in the grid
    [self _drawDaysOfMonthInRect:gridBodyRect];
    
    // draw a border around the whole thing. This ends up drawing over the top and right side borders of the header, but that's ok because we don't want their border, we want ours. Also, it ends up covering any overdraw from selected sundays and saturdays, since the selected day covers the bordering area where vertical grid lines would be (an aesthetic decision because we don't draw vertical grid lines, another aesthetic decision).
    [[NSColor gridColor] set];
    NSFrameRect(rect);
}

- (void)mouseDown:(NSEvent *)mouseEvent;
{
    if ([self isEnabled]) {
        NSCalendarDate *hitDate;
        NSPoint location;
    
        location = [self convertPoint:[mouseEvent locationInWindow] fromView:nil];
        hitDate = [self _hitDateWithLocation:location];
        if (hitDate) {
            id target;

            target = [self target];
            if (!flags.targetApprovesDateSelection || [target calendarView:self shouldSelectDate:hitDate]) {
                [self setSelectedDay:hitDate];
                if (flags.showsDaysForOtherMonths)
                    [self setVisibleMonth:hitDate];
                [self sendAction:[self action] to:target];
            }
            
        } else if (selectionType == OACalendarViewSelectByWeekday) {
            NSCalendarDate *hitWeekday;
            
            hitWeekday = [self _hitWeekdayWithLocation:location];
            if (hitWeekday) {
                if (!flags.targetApprovesDateSelection || [[self target] calendarView:self shouldSelectDate:hitWeekday]) {
                    [self setSelectedDay:hitWeekday];
                    [self sendAction:[self action] to:[self target]];
                }
            }
        }
    }
}


//
// API
//

- (NSCalendarDate *)visibleMonth;
{
    return visibleMonth;
}

- (void)setVisibleMonth:(NSCalendarDate *)aDate;
{
    [visibleMonth release];
    visibleMonth = [[aDate firstDayOfMonth] retain];
    [monthAndYearTextFieldCell setObjectValue:visibleMonth];

    [self updateHighlightMask];
    [self setNeedsDisplay:YES];
    
    if (flags.targetWatchesVisibleMonth)
        [[self target] calendarView:self didChangeVisibleMonth:visibleMonth];
}

- (NSCalendarDate *)selectedDay;
{
    return [selectedDays count] ? [selectedDays objectAtIndex:0] : nil;
}

#define DAY_IN_SECONDS 86400

- (void)setSelectedDay:(NSCalendarDate *)newSelectedDay;
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
    
    NSEvent *event = [NSApp currentEvent];
    unsigned int kflags = [event modifierFlags];
    BOOL shiftMask = (0 != (kflags & NSShiftKeyMask));
    BOOL commandMask = (0 != (kflags & NSCommandKeyMask));
    
    NSCalendarDate *startDate = [selectedDays objectAtIndex:0];
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
	    NSCalendarDate *date = [NSCalendarDate dateWithTimeIntervalSince1970:start];
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
        mask = [[self target] calendarView:self highlightMaskForVisibleMonth:visibleMonth];
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
    if (value != flags.showsDaysForOtherMonths) {
        flags.showsDaysForOtherMonths = value;

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

- (int)firstDayOfWeek;
{
    return displayFirstDayOfWeek;
}

- (void)setFirstDayOfWeek:(int)weekDay;
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

    NSCalendarDate *selectedDay = [self selectedDay];
    
    switch (selectionType) {
        case OACalendarViewSelectByDay:
            return selectedDays;
            break;
            
        case OACalendarViewSelectByWeek:
            {
                NSMutableArray *days;
                NSCalendarDate *day;
                int index;
                
                days = [NSMutableArray arrayWithCapacity:OACalendarViewNumDaysPerWeek];
                day = [selectedDay dateByAddingYears:0 months:0 days:-[selectedDay dayOfWeek] hours:0 minutes:0 seconds:0];
                for (index = 0; index < OACalendarViewNumDaysPerWeek; index++) {
                    NSCalendarDate *nextDay;

                    nextDay = [day dateByAddingYears:0 months:0 days:index hours:0 minutes:0 seconds:0];
                    if (flags.showsDaysForOtherMonths || [nextDay monthOfYear] == [selectedDay monthOfYear])
                        [days addObject:nextDay];                    
                }
            
                return days;
            }            
            break;

        case OACalendarViewSelectByWeekday:
            {
                NSMutableArray *days;
                NSCalendarDate *day;
                int index;
                
                days = [NSMutableArray arrayWithCapacity:OACalendarViewMaxNumWeeksIntersectedByMonth];
                day = [selectedDay dateByAddingYears:0 months:0 days:-(([selectedDay weekOfMonth] - 1) * OACalendarViewNumDaysPerWeek) hours:0 minutes:0 seconds:0];
                for (index = 0; index < OACalendarViewMaxNumWeeksIntersectedByMonth; index++) {
                    NSCalendarDate *nextDay;

                    nextDay = [day dateByAddingYears:0 months:0 days:(index * OACalendarViewNumDaysPerWeek) hours:0 minutes:0 seconds:0];
                    if (flags.showsDaysForOtherMonths || [nextDay monthOfYear] == [selectedDay monthOfYear])
                        [days addObject:nextDay];
                }

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
    if (([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0)
        return [self previousYear:sender];
    
    [self setVisibleMonth:[visibleMonth dateByAddingYears:0 months:-1 days:0 hours:0 minutes:0 seconds:0]];
}

- (IBAction)nextMonth:(id)sender;
{
    if (([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0)
        return [self nextYear:sender];

    [self setVisibleMonth:[visibleMonth dateByAddingYears:0 months:1 days:0 hours:0 minutes:0 seconds:0]];
}

- (IBAction)previousYear:(id)sender;
{
    [self setVisibleMonth:[visibleMonth dateByAddingYears:-1 months:0 days:0 hours:0 minutes:0 seconds:0]];
}

- (IBAction)nextYear:(id)sender;
{
    [self setVisibleMonth:[visibleMonth dateByAddingYears:1 months:0 days:0 hours:0 minutes:0 seconds:0]];
}

@end


@implementation OACalendarView (Private)

- (NSButton *)_createButtonWithFrame:(NSRect)buttonFrame;
{
    NSButton *button;
    
    button = [[NSButton alloc] initWithFrame:buttonFrame];
    [button setBezelStyle:NSShadowlessSquareBezelStyle];
    [button setBordered:NO];
    [button setImagePosition:NSImageOnly];
    [button setTarget:self];
    [button setContinuous:YES];
//    [self addSubview:button];
    [buttons addObject:button];
    [button release];

    return button;
}

- (void)setTarget:(id)value;
{
    [super setTarget:value];
    flags.targetProvidesHighlightMask = [value respondsToSelector:@selector(calendarView:highlightMaskForVisibleMonth:)];
    flags.targetWatchesCellDisplay = [value respondsToSelector:@selector(calendarView:willDisplayCell:forDate:)];
    flags.targetApprovesDateSelection = [value respondsToSelector:@selector(calendarView:shouldSelectDate:)];
    flags.targetWatchesVisibleMonth = [value respondsToSelector:@selector(calendarView:didChangeVisibleMonth:)];
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
    columnWidth = (viewBounds.size.width - 1.0) / OACalendarViewNumDaysPerWeek;
    viewBounds.size.width = (columnWidth * OACalendarViewNumDaysPerWeek) + 1.0;
    
    // resize the month & year view to be the same width as the grid
    [monthAndYearView setFrameSize:NSMakeSize(viewBounds.size.width, [monthAndYearView frame].size.height)];

    // get the rect for the month and year text field cell
    cellSize = [monthAndYearTextFieldCell cellSize];
    NSDivideRect(viewBounds, &topRect, &gridHeaderAndBodyRect, ceil(cellSize.height + OACalendarViewSpaceBetweenMonthYearAndGrid), NSMinYEdge);
    NSDivideRect(topRect, &discardRect, &monthAndYearRect, floor((viewBounds.size.width - cellSize.width) / 2), NSMinXEdge);
    monthAndYearRect.size.width = cellSize.width;
    
    tempRect = gridHeaderAndBodyRect;
    // leave space for a one-pixel border on each side
    tempRect.size.width -= 2.0;
    tempRect.origin.x += 1.0;
    // leave space for a one-pixel border at the bottom (the top already looks fine)
    tempRect.size.height -= 1.0;

    // get the grid header rect
    cellSize = [dayOfWeekCell[0] cellSize];
    NSDivideRect(tempRect, &gridHeaderRect, &gridBodyRect, ceil(cellSize.height), NSMinYEdge);
    
    // get the grid row height (add 1.0 to the body height because while we can't actually draw on that extra pixel, our bottom row doesn't have to draw a bottom grid line as there's a border right below us, so we need to account for that, which we do by pretending that next pixel actually does belong to us)
    rowHeight = floor((gridBodyRect.size.height + 1.0) / OACalendarViewMaxNumWeeksIntersectedByMonth);
    
    // get the grid body rect
    gridBodyRect.size.height = (rowHeight * OACalendarViewMaxNumWeeksIntersectedByMonth) - 1.0;
    
    // adjust the header and body rect to account for any adjustment made while calculating even row heights
    gridHeaderAndBodyRect.size.height = NSMaxY(gridBodyRect) - NSMinY(gridHeaderAndBodyRect) + 1.0;
}

- (void)_drawSelectionBackground:(NSRect)rect;
{
    switch (selectionType) {
	case OACalendarViewSelectByDay:
	    // UNDONE
	    break;
	case OACalendarViewSelectByWeek: {
	    int selectedWeek = [[self selectedDay] weekOfMonth];
	    int weekIndex;
	    NSRect weekRect;
            
            if (displayFirstDayOfWeek > [visibleMonth dayOfWeek])
                selectedWeek++;
	    if ([[self selectedDay] dayOfWeek] < displayFirstDayOfWeek)
                selectedWeek--;
	    
	    weekRect.size.height = rowHeight - 1.0;
	    weekRect.size.width = rect.size.width - 2.0;
	    weekRect.origin.x = rect.origin.x + 1.0;
	    	    
	    for (weekIndex = 1; weekIndex <= OACalendarViewMaxNumWeeksIntersectedByMonth; weekIndex++) {
		weekRect.origin.y = rect.origin.x + ((weekIndex+1) * rowHeight) - 2.0;
		[self drawRoundedRect:NSInsetRect(weekRect, 1.0, 1.0) cornerRadius:7.0 color:(weekIndex == selectedWeek ? [NSColor controlShadowColor] : [NSColor controlHighlightColor])];
	    }
	    break;
	} case OACalendarViewSelectByWeekday:
	    // UNDONE
	    break;
    }
}

- (void)_drawDaysOfMonthInRect:(NSRect)rect;
{
    NSRect cellFrame;
    int visibleMonthIndex;
    NSCalendarDate *thisDay;
    int index, row, column;
    NSSize cellSize;

    // the cell is actually one pixel shorter than the row height, because the row height includes the bottom grid line (or the top grid line, depending on which way you prefer to think of it)
    cellFrame.size.height = rowHeight - 1.0f;
    // the cell would actually be one pixel narrower than the column width but we don't draw vertical grid lines. instead, we want to include the area that would be grid line (were we drawing it) in our cell, because that looks a bit better under the header, which _does_ draw column separators. actually, we want to include the grid line area on _both sides_ or it looks unbalanced, so we actually _add_ one pixel, to cover that. below, our x position as we draw will have to take that into account. note that this means that sunday and saturday overwrite the outside borders, but the outside border is drawn last, so it ends up ok. (if we ever start drawing vertical grid lines, change this to be - 1.0, and adjust the origin appropriately below.)
    cellFrame.size.width = columnWidth - 1.0f;

    cellSize = [dayOfMonthCell cellSize];
    
    visibleMonthIndex = [visibleMonth monthOfYear];

    int dayOffset = displayFirstDayOfWeek - [visibleMonth dayOfWeek];
    if (dayOffset > 0)
        dayOffset -= OACalendarViewNumDaysPerWeek;
    thisDay = [visibleMonth dateByAddingYears:0 months:0 days:dayOffset hours:0 minutes:0 seconds:0];

    for (row = column = index = 0; index < OACalendarViewMaxNumWeeksIntersectedByMonth * OACalendarViewNumDaysPerWeek; index++) {
        NSColor *textColor;
        BOOL isVisibleMonth;

        // subtract 1.0 from the origin because we're including the area where vertical grid lines would be were we drawing them
        cellFrame.origin.x = rect.origin.x + (column * columnWidth);
        cellFrame.origin.y = rect.origin.y + (row * rowHeight);

        [dayOfMonthCell setIntValue:[thisDay dayOfMonth]];
        isVisibleMonth = ([thisDay monthOfYear] == visibleMonthIndex);

        if (flags.showsDaysForOtherMonths || isVisibleMonth) {
	    
	    BOOL shouldHighlightThisDay = NO;
	    NSCalendarDate* selectedDay = [self selectedDay];
	    
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
                        shouldHighlightThisDay = ([selectedDay monthOfYear] == visibleMonthIndex && [selectedDay dayOfWeek] == [thisDay dayOfWeek]);
                        break;
                        
                    default:
                        [NSException raise:NSInvalidArgumentException format:@"OACalendarView: Unknown selection type: %d", selectionType];
                        break;
                }
                
            }
            	    
            if (flags.targetWatchesCellDisplay) {
                [[self target] calendarView:self willDisplayCell:dayOfMonthCell forDate:thisDay];
            } else {
                if ((dayHighlightMask & (1 << index)) == 0) {
                    textColor = (isVisibleMonth ? [NSColor blackColor] : [NSColor grayColor]);
                } else {
                    textColor = [NSColor blueColor];
                }
                [dayOfMonthCell setTextColor:textColor];
            }
	    
	    if (selectionType != OACalendarViewSelectByWeek) {
		[[NSColor controlHighlightColor] set];
		[NSBezierPath strokeRect:cellFrame];
	    }

	    if ([dayOfMonthCell drawsBackground]) {
		[[dayOfMonthCell backgroundColor] set];
		[NSBezierPath fillRect:cellFrame];
		[dayOfMonthCell setDrawsBackground:NO];
	    }

	    NSRect discardRect, dayOfMonthFrame;
            NSDivideRect(cellFrame, &discardRect, &dayOfMonthFrame, floor((cellFrame.size.height - cellSize.height) / 2.0), NSMinYEdge);
	    [dayOfMonthCell drawInteriorWithFrame:dayOfMonthFrame inView:self];

	    if (shouldHighlightThisDay && [self isEnabled]) {
		[[NSColor selectedControlColor] set];
		NSBezierPath *outlinePath = [NSBezierPath bezierPathWithRect:cellFrame];
		[outlinePath setLineWidth:2.0f];
		[outlinePath stroke];
	    }
        }
        
        thisDay = [thisDay dateByAddingYears:0 months:0 days:1 hours:0 minutes:0 seconds:0];
        column++;
        if (column > OACalendarViewMaxNumWeeksIntersectedByMonth) {
            column = 0;
            row++;
        }
    }
}

- (float)_maximumDayOfWeekWidth;
{
    float maxWidth;
    int index;

    maxWidth = 0;
    for (index = 0; index < OACalendarViewNumDaysPerWeek; index++) {
        NSSize cellSize;

        cellSize = [dayOfWeekCell[index] cellSize];
        if (maxWidth < cellSize.width)
            maxWidth = cellSize.width;
    }

    return ceil(maxWidth);
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

    maxSize.width = ceil(maxSize.width);
    maxSize.height = ceil(maxSize.height);

    return maxSize;
}

- (float)_minimumColumnWidth;
{
    float dayOfWeekWidth;
    float dayOfMonthWidth;
    
    dayOfWeekWidth = [self _maximumDayOfWeekWidth];	// we don't have to add 1.0 because the day of week cell whose width is returned here includes it's own border
    dayOfMonthWidth = [self _maximumDayOfMonthSize].width + 1.0;	// add 1.0 to allow for the grid. We don't actually draw the vertical grid, but we treat it as if there was one (don't respond to clicks "on" the grid, we have a vertical separator in the header, etc.) 
    return (dayOfMonthWidth > dayOfWeekWidth) ? dayOfMonthWidth : dayOfWeekWidth;
}

- (float)_minimumRowHeight;
{
    return [self _maximumDayOfMonthSize].height + 1.0;	// add 1.0 to allow for a bordering grid line
}

- (NSCalendarDate *)_hitDateWithLocation:(NSPoint)targetPoint;
{
    int hitRow, hitColumn;
    int firstDayOfWeek, targetDayOfMonth;
    NSPoint offset;

    if (NSPointInRect(targetPoint, gridBodyRect) == NO)
        return nil;

    firstDayOfWeek = [[visibleMonth firstDayOfMonth] dayOfWeek] - displayFirstDayOfWeek;

    offset = NSMakePoint(targetPoint.x - gridBodyRect.origin.x, targetPoint.y - gridBodyRect.origin.y);
    // if they exactly hit the grid between days, treat that as a miss
    if ((selectionType != OACalendarViewSelectByWeekday) && (((int)offset.y % (int)rowHeight) == 0))
        return nil;
    // if they exactly hit the grid between days, treat that as a miss
    if ((selectionType != OACalendarViewSelectByWeek) && ((int)offset.x % (int)columnWidth) == 0)
        return nil;
    hitRow = (int)(offset.y / rowHeight);
    hitColumn = (int)(offset.x / columnWidth);
    
    if ([[visibleMonth firstDayOfMonth] dayOfWeek] < displayFirstDayOfWeek)
        hitRow--;

    targetDayOfMonth = (hitRow * OACalendarViewNumDaysPerWeek) + hitColumn - firstDayOfWeek + 1;
    if (selectionType == OACalendarViewSelectByWeek) {
        if (targetDayOfMonth < 1)
            targetDayOfMonth = 1;
        else if (targetDayOfMonth > [visibleMonth numberOfDaysInMonth])
            targetDayOfMonth = [visibleMonth numberOfDaysInMonth];
    } else if (!flags.showsDaysForOtherMonths && (targetDayOfMonth < 1 || targetDayOfMonth > [visibleMonth numberOfDaysInMonth])) {
        return nil;
    }

    return [visibleMonth dateByAddingYears:0 months:0 days:targetDayOfMonth-1 hours:0 minutes:0 seconds:0];
}

- (NSCalendarDate *)_hitWeekdayWithLocation:(NSPoint)targetPoint;
{
    int hitDayOfWeek;
    int firstDayOfWeek, targetDayOfMonth;
    float offsetX;

    if (NSPointInRect(targetPoint, gridHeaderRect) == NO)
        return nil;
    
    offsetX = targetPoint.x - gridHeaderRect.origin.x;
    // if they exactly hit a border between weekdays, treat that as a miss (besides being neat in general, this avoids the problem where clicking on the righthand border would result in us incorrectly calculating that the _first_ day of the week was hit)
    if (((int)offsetX % (int)columnWidth) == 0)
        return nil;
    
    hitDayOfWeek = ((int)(offsetX / columnWidth) + displayFirstDayOfWeek) % OACalendarViewNumDaysPerWeek;

    firstDayOfWeek = [[visibleMonth firstDayOfMonth] dayOfWeek];
    if (hitDayOfWeek >= firstDayOfWeek)
        targetDayOfMonth = hitDayOfWeek - firstDayOfWeek + 1;
    else
        targetDayOfMonth = hitDayOfWeek + OACalendarViewNumDaysPerWeek - firstDayOfWeek + 1;

    return [visibleMonth dateByAddingYears:0 months:0 days:targetDayOfMonth-1 hours:0 minutes:0 seconds:0];
}

@end
