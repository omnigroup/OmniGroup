// Copyright 2010, 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OATrackingLoop;

typedef enum {
    OATrackingLoopExitPointNone,
    OATrackingLoopExitPointVertical,
    OATrackingLoopExitPointHorizontal,
} OATrackingLoopExitPoint;

typedef void (^OATrackingLoopHysteresisExit)(OATrackingLoopExitPoint exitPoint);
typedef void (^OATrackingLoopDragged)(void);
typedef void (^OATrackingLoopLongPress)(void);
typedef void (^OATrackingLoopInsideVisibleRectChanged)(void);
typedef BOOL (^OATrackingLoopShouldAutoscroll)(void);
typedef void (^OATrackingLoopModifierFlagsChanged)(NSUInteger oldFlags);
typedef void (^OATrackingLoopUp)(void);

// Tracks the mouse, starting from a -mouseDown: event.
@interface OATrackingLoop : NSObject
{
@private
    NSView *_view;
    NSEvent *_mouseDownEvent;
    NSEventType _upEventType;
    NSEventType _draggedEventType;
    NSString *_runLoopMode;
    NSDate *_limitDate;
    BOOL _stopped;
    BOOL _disablesAnimation;
    BOOL _debug;
    BOOL _invalid;
    
    NSPoint _initialMouseDownPointInView;
    NSPoint _currentMouseDraggedPointInWindow;
    NSPoint _currentMouseDraggedPointInView;
    
    CGFloat _hysteresisSize;
    BOOL _insideHysteresisRect;
    NSRect _hysteresisViewRect;
    BOOL _insideVisibleRect;
    
    NSUInteger _modifierFlags;
    
    OATrackingLoopHysteresisExit _hysteresisExit;
    OATrackingLoopInsideVisibleRectChanged _insideVisibleRectChanged;
    OATrackingLoopShouldAutoscroll _shouldAutoscroll;
    OATrackingLoopModifierFlagsChanged _modifierFlagsChanged;
    OATrackingLoopDragged _dragged;
    OATrackingLoopLongPress _longPress;
    OATrackingLoopUp _up;
}

@property(nonatomic,readonly) NSView *view;
@property(nonatomic,readonly) NSEvent *mouseDownEvent;

// Things like dragging explicitly drive animation by user events. We nearly always want timed animations off and want direct user control. Defaults to YES.
@property(nonatomic,assign) BOOL disablesAnimation;

@property(nonatomic,readonly) BOOL insideHysteresisRect;
@property(nonatomic,assign) CGFloat hysteresisSize;
@property(nonatomic,readonly) BOOL insideVisibleRect;

@property(nonatomic,readonly) NSPoint initialMouseDownPointInView;
@property(nonatomic,readonly) NSPoint currentMouseDraggedPointInView;
@property(nonatomic,readonly) NSSize draggedOffsetInView;
- (NSSize)draggedOffsetInView:(NSView *)view;

@property(nonatomic,readonly) NSUInteger modifierFlags;

@property(nonatomic,copy) OATrackingLoopHysteresisExit hysteresisExit;
@property(nonatomic,copy) OATrackingLoopInsideVisibleRectChanged insideVisibleRectChanged;
@property(nonatomic,copy) OATrackingLoopModifierFlagsChanged modifierFlagsChanged;
@property(nonatomic,copy) OATrackingLoopShouldAutoscroll shouldAutoscroll;
@property(nonatomic,copy) OATrackingLoopDragged dragged;
@property(nonatomic,copy) OATrackingLoopLongPress longPress;
@property(nonatomic,copy) OATrackingLoopUp up;

@property(nonatomic,assign) BOOL debug;

- (void)run;
- (void)stop;

@end

@interface NSView (OATrackingLoop)
- (OATrackingLoop *)trackingLoopForMouseDown:(NSEvent *)mouseDownEvent;
@end
