// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATrackingLoop.h>

RCS_ID("$Id$");

#define DEBUG_LOOP(format, ...) do { \
    if (_debug) \
        NSLog(@"TRACKING IN %@: " format, [_view shortDescription], ## __VA_ARGS__); \
} while(0)

static BOOL OATrackingLoopDebug = YES;

@interface OATrackingLoop ()

// Redeclared readwrite to encourage their use internally. This allows for their replacement at runtime (in tests so that correct mouse tracking can be verified, for example)
@property(nonatomic,readwrite) NSPoint initialMouseDownPointInView;
@property(nonatomic,readwrite) NSPoint currentMouseDraggedPointInView;
@property(nonatomic,readwrite) NSPoint currentMouseDraggedPointInWindow;

@end

@implementation OATrackingLoop
{
    NSEventType _upEventType;
    NSEventType _draggedEventType;
    NSString *_runLoopMode;
    NSDate *_limitDate;
    BOOL _stopped;
    BOOL _invalid;

    CGFloat _hysteresisSize;
    NSRect _hysteresisViewRect;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    // Default value for the debug property
    OATrackingLoopDebug = [[NSUserDefaults standardUserDefaults] boolForKey:@"OATrackingLoopDebug"];
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (void)dealloc;
{
    [_insideVisibleRectChanged release];
    [_hysteresisExit release];
    [_dragged release];
    [_up release];
    
    [_limitDate release];
    [_runLoopMode release];
    [_mouseDownEvent release];
    [_view release];
    [_longPress release];
    [_modifierFlagsChanged release];
    [_shouldAutoscroll release];

    [super dealloc];
}

// This is usable if the tracking operation doesn't move the view itself.
- (NSSize)draggedOffsetInView;
{
    return NSMakeSize(self.currentMouseDraggedPointInView.x - self.initialMouseDownPointInView.x,
                      self.currentMouseDraggedPointInView.y - self.initialMouseDownPointInView.y);
}

// If the tracking operation moves the original view, you'll likely want to ask for the dragged offset relative to some other stationary view.
- (NSSize)draggedOffsetInView:(NSView *)view;
{
    // We could support views anywhere on screen, but for now the common case is that some superview will be used.
    OBPRECONDITION([view window] == [_view window]);
    
    NSPoint initialPoint = [view convertPoint:[_mouseDownEvent locationInWindow] fromView:nil];
    NSPoint currentPoint = [view convertPoint:self.currentMouseDraggedPointInWindow fromView:nil];
    
    return NSMakeSize(currentPoint.x - initialPoint.x, currentPoint.y - initialPoint.y);
}


// TODO: Make this class a subclass of NSResponder and allow subclassing things like -flagsChanged:? Or just provide block callouts for those?
// TODO: If the view wants to track the mouse position via NSTrackingAreas while dragging (as opposed to simplistic tracking rects here) what state/blocks do we need to have to support that?
// TODO: If you drag away from the hysteresis rect and then drag back, should we snap back? Add a BOOL property to allow this?
// TODO: Compute the hysterisis rect in screen or user coordinates. You really want to compute it in something relative in ruler-measured space; high dpi screens should allow for more pixels, that is. This also raises the question of what the units of hysteresisSize is -- points?

- (void)run;
{
    OBASSERT(!_invalid);
    
    BOOL disableAnimations = _disablesAnimation; // In case the user fiddles this while running.
    @try {
        if (disableAnimations) {
            [NSAnimationContext beginGrouping];
            [[NSAnimationContext currentContext] setDuration:0];
        }
        
        [self _run];
    } @finally {
        if (disableAnimations)
            [NSAnimationContext endGrouping];
    }
    
    [self _invalidate];
}

- (void)stop;
{
    _stopped = YES;
}


#pragma mark -
#pragma mark Private

- _initWithView:(NSView *)view mouseDown:(NSEvent *)event;
{
    OBPRECONDITION(view);
    OBPRECONDITION(event);
    
    if (!(self = [super init]))
        return nil;
    
    _debug = OATrackingLoopDebug;
    _view = [view retain];
    _mouseDownEvent = [event retain];
    _modifierFlags = [event modifierFlags];
    _hysteresisSize = 0.0f;
    _runLoopMode = [NSEventTrackingRunLoopMode copy];
    _limitDate = [[NSDate distantFuture] copy];
    _disablesAnimation = YES;
    
    _initialMouseDownPointInView = [_view convertPoint:[event locationInWindow] fromView:nil];
    _currentMouseDraggedPointInView = _initialMouseDownPointInView;
    
    _insideVisibleRect = [_view mouse:_initialMouseDownPointInView inRect:[_view visibleRect]];
    
    switch ([_mouseDownEvent type]) {
        case NSLeftMouseDown:
            _upEventType = NSLeftMouseUp;
            _draggedEventType = NSLeftMouseDragged;
            break;
        default:
            OBASSERT_NOT_REACHED("Need to record which mouse button went down and only signal up when *that* button goes up.");
            break;
    }
    
    return self;
}

#define LONG_PRESS_INTERVAL (0.5)

- (void)_run;
{
    NSWindow *window = [_view window];
    BOOL hasStartedPeriodicEvents = NO;
    NSEvent *lastMouseEvent = nil;
    
    // Compute the hysteresis rect, now that the caller has had a chance to set _hysteresisSize.
    {
        NSPoint mouseDownWindowPoint = [_mouseDownEvent locationInWindow];
        NSRect hysteresisWindowRect = NSMakeRect(mouseDownWindowPoint.x - _hysteresisSize,
                                                 mouseDownWindowPoint.y - _hysteresisSize,
                                                 _hysteresisSize * 2,
                                                 _hysteresisSize * 2);
        _hysteresisViewRect = [_view convertRect:hysteresisWindowRect fromView:nil];
    }
    
    _insideHysteresisRect = (_hysteresisSize > 0.0) && [_view mouse:self.initialMouseDownPointInView inRect:_hysteresisViewRect];
    
    NSTimer *timer = nil;
    if (_longPress) {
        timer = [NSTimer timerWithTimeInterval:LONG_PRESS_INTERVAL target:self selector:@selector(_longPress:) userInfo:nil repeats:NO];
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:_runLoopMode];
    }
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    while (!_stopped) {
        // If you want to do a tracking loop w/o consuming the mouseUp, you can call -stop in one of the other callbacks and then start a *new* tracking loop.  At least, that's the theory.
        [_currentEvent autorelease];
        _currentEvent = [[window nextEventMatchingMask:NSAnyEventMask untilDate:_limitDate inMode:_runLoopMode dequeue:YES] retain];
        DEBUG_LOOP(@"event: %@", _currentEvent);
        
        NSUInteger oldFlags = _modifierFlags;
        _modifierFlags = [_currentEvent modifierFlags];
        
        NSEventType eventType = [_currentEvent type];
        // It looks as though we can't get an actual notification that Mission Control, Expose, or Dashboard is coming up. If invoke them with a key and mouse up while they're in front, we actually seem to get the mouse up when we come back. Mouse buttons invoking them appear to be a problem.  NSSystemDefined events of subtype 7 seem to be "mouse button state change events". data1 is the mouse/mice that changed state, and data2 is the current state of all mouse buttons. CGEventTaps cause us to get what appears to be "mouse button 1 changed state and mouse button 1 is down, which we already know, because we're here.  Exit for any other mouse button changing state.
        if (eventType == _upEventType ||
            ((eventType == NSSystemDefined && [_currentEvent subtype] == 7) && ([_currentEvent data1] != 1 || [_currentEvent data2] != 1))) {
            DEBUG_LOOP(@"  up!");
            if (_up)
                _up(self);
            [self stop];
        } else if (eventType == _draggedEventType) {
            DEBUG_LOOP(@"  dragged!");
            self.currentMouseDraggedPointInWindow = [_currentEvent locationInWindow];
            self.currentMouseDraggedPointInView = [_view convertPoint:self.currentMouseDraggedPointInWindow fromView:nil];
            
            // If there is a hysteresis rect, check if we have gone outside it.
            if (_hysteresisSize > 0.0) {
                BOOL nowInsideHysteresisRect = [_view mouse:self.currentMouseDraggedPointInView inRect:_hysteresisViewRect];
                if (_insideHysteresisRect && !nowInsideHysteresisRect) {
                    // Leaving the rect. Calculate whether we left vertically or horizontally. We might want to use NSRectEdge, but we don't need that much information anywhere (even picking between vertical and horizontal -- for row dragging vs. text selection in OO -- is finicky if the hysteresis size is too small).
                    NSSize delta = (NSSize){self.initialMouseDownPointInView.x - self.currentMouseDraggedPointInView.x, self.initialMouseDownPointInView.y - self.currentMouseDraggedPointInView.y};
                    
                    OATrackingLoopExitPoint exitPoint;
                    if (fabs(delta.height) >= fabs(delta.width))
                        exitPoint = OATrackingLoopExitPointVertical;
                    else
                        exitPoint = OATrackingLoopExitPointHorizontal;
                    
                    if (_hysteresisExit)
                        _hysteresisExit(self, exitPoint);
                    _insideHysteresisRect = NO;
                }
            }
            
            // If we are still inside the hysteresis rect, snap the position back (without reporting a drag). Otherwise, report the new drag position.
            if (_insideHysteresisRect)
                self.currentMouseDraggedPointInView = self.initialMouseDownPointInView;
            else {
                // TODO: Add a 'snap' block that allows for other data-based snapping.
                if (_dragged)
                    _dragged(self);
            }
            
            // Check if the drag position changes whether we are inside the visible rect or not.
            // TODO: Allow the caller to customize what tracking rect to use? Useful for cell tracking, but possibly less useful for autoscroll.  Maybe we want a screen or window rect instead of a rect in the dragging view.
            BOOL nowInsideVisibleRect = [_view mouse:self.currentMouseDraggedPointInView inRect:[_view visibleRect]];
            if (nowInsideVisibleRect ^ _insideVisibleRect) {
                _insideVisibleRect = nowInsideVisibleRect;
                if (_insideVisibleRectChanged)
                    _insideVisibleRectChanged(self);
            }
            
            if (_shouldAutoscroll) {
                BOOL shouldScroll = _shouldAutoscroll(self);
                if (shouldScroll != hasStartedPeriodicEvents) {
                    if (shouldScroll)
                        [NSEvent startPeriodicEventsAfterDelay:0 withPeriod:0.1];
                    else
                        [NSEvent stopPeriodicEvents];
                    hasStartedPeriodicEvents = shouldScroll;
                }
                
                if (shouldScroll) {
                    [lastMouseEvent release];
                    lastMouseEvent = [_currentEvent retain];
                }
            }
        } else if (eventType == NSFlagsChanged) {
            if (_modifierFlagsChanged)
                _modifierFlagsChanged(self, oldFlags);
        } else if (eventType == NSPeriodic) {
            OBASSERT(_shouldAutoscroll);
            OBASSERT_NOTNULL(lastMouseEvent);
            if (lastMouseEvent != nil && [_view autoscroll:lastMouseEvent]) {
                // visible rect has scrolled from under our even location, so need to adjust mouseDraggedPoint
                self.currentMouseDraggedPointInWindow = [lastMouseEvent locationInWindow];
                self.currentMouseDraggedPointInView = [_view convertPoint:self.currentMouseDraggedPointInWindow fromView:nil];

                if (_dragged)
                    _dragged(self);
            }
        } else {
            // Discard? -sendEvent: to the window? Call another customizable hook?
            DEBUG_LOOP(@"  dropped event");
        }
        
        [pool drain];
        pool = [[NSAutoreleasePool alloc] init];
        
    }
    
    [timer invalidate];
    
    [_currentEvent release];
    _currentEvent = nil;
    
    [lastMouseEvent release];
    if (hasStartedPeriodicEvents)
        [NSEvent stopPeriodicEvents];

    [pool drain];
}

- (void)_longPress:(NSTimer *)timer;
{
    if (_longPress)
        _longPress(self);
}

- (void)_invalidate;
{
    self.hysteresisExit = NULL;
    self.insideVisibleRectChanged = NULL;
    self.shouldAutoscroll = NULL;
    self.modifierFlagsChanged = NULL;
    self.dragged = NULL;
    self.up = NULL;
    
    [_currentEvent release];
    _currentEvent = nil;
    
    _invalid = YES;
}

@end

@implementation NSView (OATrackingLoop)

// Subclasses may twiddle settings. The OATrackingLoop initializer is private to encourage going through this creation method, allowing view-based subclassing.
- (OATrackingLoop *)trackingLoopForMouseDown:(NSEvent *)mouseDownEvent;
{
    return [[[OATrackingLoop alloc] _initWithView:self mouseDown:mouseDownEvent] autorelease];
}

@end
