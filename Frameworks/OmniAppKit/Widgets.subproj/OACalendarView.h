// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSControl.h>

@class OACalendarView;

#import <AppKit/NSNibDeclarations.h>

@protocol OACalendarViewDelegate
@optional
- (int)calendarView:(OACalendarView *)aCalendarView highlightMaskForVisibleMonth:(NSDate *)visibleMonth;
- (void)calendarView:(OACalendarView *)aCalendarView willDisplayCell:(id)aCell forDate:(NSDate *)aDate;	// implement this on the target if you want to be able to set up the date cell. The cell is only used for drawing (and is reused for every date), so you can not, for instance, enable/disable dates by enabling or disabling the cell.
- (BOOL)calendarView:(OACalendarView *)aCalendarView shouldSelectDate:(NSDate *)aDate;	// implement this on the target if you need to prevent certain dates from being selected. The target is responsible for taking into account the selection type
- (void)calendarView:(OACalendarView *)aCalendarView didChangeVisibleMonth:(NSDate *)aDate;	// implement this on the target if you want to know when the visible month changes
@end


typedef enum _OACalendarViewSelectionType {
    OACalendarViewSelectByDay = 0,		// one day
    OACalendarViewSelectByWeek = 1,		// one week (from Sunday to Saturday) 
    OACalendarViewSelectByWeekday = 2,    	// all of one weekday (e.g. Monday) for a whole month
} OACalendarViewSelectionType;

@interface OACalendarView : NSControl

@property(nonatomic,retain) NSCalendar *calendar;
@property(nonatomic,assign) id<OACalendarViewDelegate> delegate;

- (NSDate *)visibleMonth;
- (void)setVisibleMonth:(NSDate *)aDate;

- (NSDate *)selectedDay;
- (void)setSelectedDay:(NSDate *)newSelectedDay;

- (int)dayHighlightMask;
- (void)setDayHighlightMask:(int)newMask;
- (void)updateHighlightMask;

- (BOOL)showsDaysForOtherMonths;
- (void)setShowsDaysForOtherMonths:(BOOL)value;

- (OACalendarViewSelectionType)selectionType;
- (void)setSelectionType:(OACalendarViewSelectionType)value;

- (NSInteger)firstDayOfWeek;
- (void)setFirstDayOfWeek:(NSInteger)weekDay;

- (NSArray *)selectedDays;

// Actions
- (IBAction)previousMonth:(id)sender;
- (IBAction)nextMonth:(id)sender;
- (IBAction)previousYear:(id)sender;
- (IBAction)nextYear:(id)sender;

@end
