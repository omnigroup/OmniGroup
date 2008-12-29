// Copyright 2001-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OACalendarView.h 89466 2007-08-01 23:35:13Z kc $

#import <AppKit/NSControl.h>

@class NSCalendarDate, NSMutableArray;
@class NSTableHeaderCell, NSTextFieldCell;
@class OACalendarView;

#import <AppKit/NSNibDeclarations.h>

@interface NSObject (OACalendarViewDelegate)
- (int)calendarView:(OACalendarView *)aCalendarView highlightMaskForVisibleMonth:(NSCalendarDate *)visibleMonth;
- (void)calendarView:(OACalendarView *)aCalendarView willDisplayCell:(id)aCell forDate:(NSCalendarDate *)aDate;	// implement this on the target if you want to be able to set up the date cell. The cell is only used for drawing (and is reused for every date), so you can not, for instance, enable/disable dates by enabling or disabling the cell.
- (BOOL)calendarView:(OACalendarView *)aCalendarView shouldSelectDate:(NSCalendarDate *)aDate;	// implement this on the target if you need to prevent certain dates from being selected. The target is responsible for taking into account the selection type
- (void)calendarView:(OACalendarView *)aCalendarView didChangeVisibleMonth:(NSCalendarDate *)aDate;	// implement this on the target if you want to know when the visible month changes
@end


typedef enum _OACalendarViewSelectionType {
    OACalendarViewSelectByDay = 0,		// one day
    OACalendarViewSelectByWeek = 1,		// one week (from Sunday to Saturday) 
    OACalendarViewSelectByWeekday = 2,    	// all of one weekday (e.g. Monday) for a whole month
} OACalendarViewSelectionType;

@interface OACalendarView : NSControl
{
    NSCalendarDate *visibleMonth;
    NSMutableArray *selectedDays;

    NSView *monthAndYearView;
    NSTextFieldCell *monthAndYearTextFieldCell;
    NSTextFieldCell *dayOfWeekCell[7];
    NSTextFieldCell *dayOfMonthCell;
    NSMutableArray *buttons;

    int dayHighlightMask;
    OACalendarViewSelectionType selectionType;
    int displayFirstDayOfWeek;
    
    float columnWidth;
    float rowHeight;
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

- (NSCalendarDate *)visibleMonth;
- (void)setVisibleMonth:(NSCalendarDate *)aDate;

- (NSCalendarDate *)selectedDay;
- (void)setSelectedDay:(NSCalendarDate *)newSelectedDay;

- (int)dayHighlightMask;
- (void)setDayHighlightMask:(int)newMask;
- (void)updateHighlightMask;

- (BOOL)showsDaysForOtherMonths;
- (void)setShowsDaysForOtherMonths:(BOOL)value;

- (OACalendarViewSelectionType)selectionType;
- (void)setSelectionType:(OACalendarViewSelectionType)value;

- (int)firstDayOfWeek;
- (void)setFirstDayOfWeek:(int)weekDay;

- (NSArray *)selectedDays;

// Actions
- (IBAction)previousMonth:(id)sender;
- (IBAction)nextMonth:(id)sender;
- (IBAction)previousYear:(id)sender;
- (IBAction)nextYear:(id)sender;

@end
