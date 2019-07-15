// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class OATrackingLoop;

typedef enum {
    OATrackingLoopExitPointNone,
    OATrackingLoopExitPointVertical,
    OATrackingLoopExitPointHorizontal,
} OATrackingLoopExitPoint;

typedef void (^OATrackingLoopHysteresisExit)(OATrackingLoop *loop, OATrackingLoopExitPoint exitPoint);
typedef void (^OATrackingLoopDragged)(OATrackingLoop *loop);
typedef void (^OATrackingLoopLongPress)(OATrackingLoop *loop);
typedef void (^OATrackingLoopInsideVisibleRectChanged)(OATrackingLoop *loop);
typedef BOOL (^OATrackingLoopShouldAutoscroll)(OATrackingLoop *loop);
typedef void (^OATrackingLoopModifierFlagsChanged)(OATrackingLoop *loop, NSUInteger oldFlags);
typedef void (^OATrackingLoopUp)(OATrackingLoop *loop);

// Tracks the mouse, starting from a -mouseDown: event.
@interface OATrackingLoop : NSObject

@property(nonatomic,readonly) NSView *view;
@property(nonatomic,readonly) NSEvent *mouseDownEvent;

// Things like dragging explicitly drive animation by user events. We nearly always want timed animations off and want direct user control. Defaults to YES.
// REVIEW: On 10.12.x, `disablesAnimation=YES` also has the side effect of not driving screen updates during tracking, which is less than ideal when this is used for custom control tracking.
// Should we reconsider the default, rather than make each client set `disablesAnimation=NO`?
@property(nonatomic,assign) BOOL disablesAnimation;

@property(nonatomic,readonly) BOOL insideHysteresisRect;
@property(nonatomic,assign) CGFloat hysteresisSize;
@property(nonatomic,readonly) BOOL insideVisibleRect;

@property(nonatomic,readonly) NSPoint initialMouseDownPointInView;
@property(nonatomic,readonly) NSPoint currentMouseDraggedPointInView;
@property(nonatomic,readonly) NSSize draggedOffsetInView;
- (NSSize)draggedOffsetInView:(NSView *)view;

@property(nonatomic,readonly) NSEvent *currentEvent;
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
