// Copyright 2003-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSView.h>
#import <Foundation/NSTimer.h>

@class NSSet;
@class NSCell;

enum OASwoopStyle {
    OASwoop_Linear,
    OASwoop_Harmonic,
    OASwoop_HalfHarmonic,
    OASwoop_Decay,
    OASwoop_LinDecel,
    OASwoop_Immediate,    // duration is ignored for OASwoop_Immediate
    // OASwoop_LinAccAnticipate,
    
    // This can be OR'd with the other flags to request -cellsFinished: notification
    OASwoop_NotifyFinished = 0x10000,
};

@interface OASwoopView : NSView
{
    struct swoopcell {
        NSCell *cell;           // pointer to a cell, or nil if this slot is empty
        NSRect rect;            // frame of this cell
        CGFloat parameter;      // generic user parameter of this cell
    } *cells;                   // array of cells and locations; non-NULL
    unsigned swoopCellCount;
    
    struct swooper {
        unsigned cellIndex;     // Index of this cell in the cells array
        short flags;            // Flags; will be 0 if swooper is idle
        NSPoint begins;         // Cell position at t=0
        NSPoint slideVector;    // Slide vector
        float duration;         // Time to take to slide; may validly be 0
        NSTimeInterval began;   // Time the motion began; assumed to be in past
        enum OASwoopStyle kine; // Cell kinematic style
    } *swoop;                   // may be NULL if swoopCount is 0
    unsigned swoopCount;

    NSTimer *motionTimer;

    struct {
        unsigned int delayingStart: 1;
    } swoopFlags;
}

// API

// Adding and removing cells
- (BOOL)addCellIfAbsent:(NSCell *)newCell frame:(NSRect)newCellFrame parameter:(CGFloat)newParameter;
- (BOOL)addCellIfAbsent:(NSCell *)newCell frame:(NSRect)newCellFrame;
- (unsigned)removeCells:(NSArray *)delenda;
- (unsigned)removeCellsExcept:(NSSet *)keepThese;  // keepThese may be nil to remove all cells

// Inquiring about the view's contents
- (NSArray *)cells;
- (NSCell *)cellAtPoint:(NSPoint)hit getFrame:(NSRect *)cellFrame_out;
- (NSRect)frameOfCell:(NSCell *)aCell;
- (NSRect)targetFrameOfCell:(NSCell *)aCell;
- (CGFloat)parameterOfCell:(NSCell *)aCell;
- (BOOL)isMoving;  // Indicates whether the view is currently animating.

// Modifying the z-ordering of cells. The cells listed in 'existingCells' will be reordered according to their position in that array, with earlier indices corresponding to deeper (more obscured) z-orderings. Cells in the array must already have been added via -addCellIfAbsent:frame:. 'relation' indicates what to do with any cells not specified in 'existingCells': it may be NSWindowBelow or NSWindowAbove to place them above or below the other cells, or NSWindowOut to remove them from the OASwoopView entirely.
- (void)orderCells:(NSArray *)existingCells others:(NSWindowOrderingMode)relation;

// Starting animations
- (void)moveCell:(NSCell *)aCell toOrigin:(NSPoint)newLocation delay:(NSTimeInterval)delay motion:(enum OASwoopStyle)kinematics;
- (void)moveCell:(NSCell *)aCell toSize:(NSSize)newSize delay:(NSTimeInterval)delay motion:(enum OASwoopStyle)kinematics;
- (void)moveCell:(NSCell *)aCell toFrame:(NSRect)newFrame delay:(NSTimeInterval)delay motion:(enum OASwoopStyle)kinematics;
- (void)moveCell:(NSCell *)aCell toParameter:(CGFloat)newParameter delay:(NSTimeInterval)delay motion:(enum OASwoopStyle)kinematics;

- (void)setDelayedStart:(BOOL)flag;  // If true, cells won't start moving until the next time the view is redrawn.

// Available for subclasses to override. Do not invoke these methods directly. They are all no-ops in OASwoopView at the moment.
- (void)willMove;  // Called when the view starts moving after having been idle.
- (void)didMove;   // Called when the number of moving cells drops to 0 again.

- (void)cellsFinished:(NSArray *)cells;  // Called for cells with OASwoop_NotifyFinished set.

@end

#import <AppKit/NSCell.h>
@interface NSCell (OASwoopViewExtensions)
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView parameter:(CGFloat)parameter;
@end
