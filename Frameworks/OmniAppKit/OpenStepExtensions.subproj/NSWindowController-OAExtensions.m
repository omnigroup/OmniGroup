// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSWindowController-OAExtensions.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

@interface NSWindowController (OAExtensionsPrivate)
+ (void)_longIndicatorThread:(id)arg;
@end

#define BORDER_WIDTH  (2.0f)
#define BORDER_GAP    (2.0f)
#define MAX_ALPHA     (0.85f)

#if 0 && defined(DEBUG)
    #define DEBUG_LONG_OPERATION_INDICATOR(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_LONG_OPERATION_INDICATOR(format, ...)
#endif

static BOOL LongOperationIndicatorEnabledForWindow(NSWindow *window)
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"LongOperationIndicatorDisabled"])
        return NO;

    // Let the application's delegate check.
    id controller = [NSApp delegate];
    if ([controller respondsToSelector:@selector(shouldShowLongOperationIndicatorForWindow:)])
        return [controller shouldShowLongOperationIndicatorForWindow:window];
    
    return YES;
}

@interface _OALongOperationIndicatorView : NSView
{
    NSProgressIndicator *_progressIndicator;
    NSDictionary *_attributes;

    NSLock *_titleLock;
    NSString *_title;
    NSAttributedString *_attributedTitle;
    NSPoint _titleLocation;
}

- (id)initWithFrame:(NSRect)frame controlSize:(NSControlSize)controlSize progressStyle:(NSProgressIndicatorStyle)progressStyle;
- (void)setTitle:(NSString *)title documentWindow:(NSWindow *)documentWindow;
- (NSProgressIndicator *)progressIndicator;
@end

@implementation _OALongOperationIndicatorView : NSView

- (void)dealloc;
{
    [_progressIndicator release];
    [_attributes release];
    [_titleLock release];
    [_title release];
    [_attributedTitle release];
    [super dealloc];
}

- (id)initWithFrame:(NSRect)frame controlSize:(NSControlSize)controlSize progressStyle:(NSProgressIndicatorStyle)progressStyle;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    if (progressStyle == NSProgressIndicatorBarStyle) {
        _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 200.0f, 16.0f)];
        [_progressIndicator setIndeterminate:NO];
        [_progressIndicator setControlSize:controlSize];
        [_progressIndicator setUsesThreadedAnimation:YES];
        [_progressIndicator setStyle:NSProgressIndicatorBarStyle];
        [_progressIndicator sizeToFit];
        [_progressIndicator setControlTint:NSClearControlTint];
        [_progressIndicator setMinValue:0.0];
        [_progressIndicator setMaxValue:1.0];
        [_progressIndicator setFrameOrigin:(NSPoint){BORDER_WIDTH + BORDER_GAP, BORDER_WIDTH + BORDER_GAP}];
        [self addSubview:_progressIndicator];
    } else {
        OBASSERT(progressStyle == NSProgressIndicatorSpinningStyle); // It's the only other style!
        _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0,0,10,10)];
        [_progressIndicator setIndeterminate:YES];
        [_progressIndicator setControlSize:controlSize];
        [_progressIndicator setUsesThreadedAnimation:YES];
        [_progressIndicator setStyle:NSProgressIndicatorSpinningStyle];
        [_progressIndicator sizeToFit];
        [_progressIndicator setControlTint:NSClearControlTint];
        [_progressIndicator setFrameOrigin:(NSPoint){BORDER_WIDTH + BORDER_GAP, BORDER_WIDTH + BORDER_GAP}];
        [self addSubview:_progressIndicator];
    }

    float fontSize;
    if (controlSize == NSSmallControlSize)
        fontSize = [NSFont smallSystemFontSize];
    else
        fontSize = [NSFont systemFontSize];
    
    _attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSFont boldSystemFontOfSize:fontSize], NSFontAttributeName,
        [NSColor textColor], NSForegroundColorAttributeName,
        nil];
    
    _titleLock = [[NSLock alloc] init];
    
    return self;
}

- (BOOL)isFlipped;
{
    // Since we are going to draw text
    return YES;
}

- (void)setTitle:(NSString *)title documentWindow:(NSWindow *)documentWindow;
{
    OBPRECONDITION(_progressIndicator);
    OBPRECONDITION(_attributes);
    
    [_titleLock lock];
    if (OFISEQUAL(title, _title)) {
        [_titleLock unlock];
        
        // Maybe the title is equal but the document window moved.  Ever think of that, Mr. Smartypants?
        NSRect documentWindowRect = [documentWindow frame];
        NSRect indicatorRect = [[self window] frame];
        indicatorRect.origin.x = NSMinX(documentWindowRect) + floor((NSWidth(documentWindowRect) - indicatorRect.size.width) / 2.0f);
        indicatorRect.origin.y = NSMinY(documentWindowRect) + floor((NSHeight(documentWindowRect) - indicatorRect.size.height) / 2.0f);
        [[self window] setFrame:indicatorRect display:[[self window] isVisible]];

        return;
    }

    [_title release];
    _title = [title copy];

    [_attributedTitle release];
    _attributedTitle = [[NSAttributedString alloc] initWithString:_title attributes:_attributes];

    // Now, resize our window and reposition the progress indicator and window.
    NSSize stringSize = [_attributedTitle size];
    stringSize.width = ceil(stringSize.width);
    stringSize.height = ceil(stringSize.height);
    
    NSRect indicatorRect;
    NSRect progressIndicatorFrame = _progressIndicator ? [_progressIndicator frame] : NSZeroRect; // Make clang happy; we know it isn't nil.
    NSRect documentWindowRect = [documentWindow frame];

    if ([_progressIndicator style] == NSProgressIndicatorBarStyle) {
        indicatorRect.size.width  = BORDER_WIDTH + BORDER_GAP + MAX(progressIndicatorFrame.size.width, stringSize.width) + BORDER_GAP + 2*BORDER_GAP + BORDER_WIDTH;
        indicatorRect.size.height = BORDER_WIDTH + BORDER_GAP + progressIndicatorFrame.size.height + BORDER_GAP + stringSize.height + BORDER_GAP + BORDER_WIDTH;
        indicatorRect.origin.x = NSMinX(documentWindowRect) + floor((NSWidth(documentWindowRect) - indicatorRect.size.width) / 2.0f);
        indicatorRect.origin.y = NSMinY(documentWindowRect) + floor((NSHeight(documentWindowRect) - indicatorRect.size.height) / 2.0f);

        _titleLocation.x = NSMinX(progressIndicatorFrame);
        _titleLocation.y = NSMaxY(progressIndicatorFrame) + BORDER_GAP;
    } else {
        indicatorRect.size.width  = BORDER_WIDTH + BORDER_GAP + progressIndicatorFrame.size.width + BORDER_GAP + stringSize.width + 2*BORDER_GAP + BORDER_WIDTH;
        indicatorRect.size.height = BORDER_WIDTH + BORDER_GAP + MAX(progressIndicatorFrame.size.height, stringSize.height) + BORDER_GAP + BORDER_WIDTH;
        indicatorRect.origin.x = NSMinX(documentWindowRect) + floor((NSWidth(documentWindowRect) - indicatorRect.size.width) / 2.0f);
        indicatorRect.origin.y = NSMinY(documentWindowRect) + floor((NSHeight(documentWindowRect) - indicatorRect.size.height) / 2.0f);

        _titleLocation.x = NSMaxX(progressIndicatorFrame) + BORDER_GAP;
        _titleLocation.y = floor((NSHeight(indicatorRect) - stringSize.height) / 2.0f);
    }
          
    [_titleLock unlock]; // Must do this before the call to -setFrame:display: since it will call -drawRect:.  Must also do it before -setFrameSize: below since that can take the AppKit lock, draw, and then cause the title lock to be taken (and we'd hold the locks in th opposite order here resulting in deadlock).

    [self setFrameSize:indicatorRect.size];

    // ???: I'm a bit worried that this could cause drawing glitches since the drawing is happening in another thread
    [[self window] setFrame:indicatorRect display:[[self window] isVisible]];
    
}

- (NSProgressIndicator *)progressIndicator;
{
    return _progressIndicator;
}

- (void)drawRect:(NSRect)rect;
{
    NSRect bounds = [self bounds];

    [[NSColor clearColor] set];
    NSRectFillUsingOperation(bounds, NSCompositeCopy);
    
    {
        // We are going to stroke aw well as fill.  That means that the rect we are going to stroke needs to be on a pixel center.
        NSRect rect = NSInsetRect(bounds, 0.5, 0.5);
        
        CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];

        // Append rounded rect
        float radius = 7.0f;
        {
            NSPoint topMid      = NSMakePoint(NSMidX(rect), NSMaxY(rect));
            NSPoint topLeft     = NSMakePoint(NSMinX(rect), NSMaxY(rect));
            NSPoint topRight    = NSMakePoint(NSMaxX(rect), NSMaxY(rect));
            NSPoint bottomRight = NSMakePoint(NSMaxX(rect), NSMinY(rect));
            
            CGContextMoveToPoint(ctx, topMid.x, topMid.y);
            CGContextAddArcToPoint(ctx, topLeft.x, topLeft.y, rect.origin.x, rect.origin.y, radius);
            CGContextAddArcToPoint(ctx, rect.origin.x, rect.origin.y, bottomRight.x, bottomRight.y, radius);
            CGContextAddArcToPoint(ctx, bottomRight.x, bottomRight.y, topRight.x, topRight.y, radius);
            CGContextAddArcToPoint(ctx, topRight.x, topRight.y, topLeft.x, topLeft.y, radius);
            CGContextClosePath(ctx);
        }
        
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] setFill];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.9] setStroke];
        
        CGContextDrawPath(ctx, kCGPathFillStroke);
    }
    
    [_titleLock lock];
    [_attributedTitle drawAtPoint:_titleLocation];
    [_titleLock unlock];
}

@end

// We assume that only one document can be saving at a time.
static BOOL indicatorThreadStarted = NO;
static NSWindow *operationWindow = nil;
static _OALongOperationIndicatorView *indicatorView = nil;
static NSConditionLock *indicatorLock = nil;

enum {
    IndicatorStarting,
    IndicatorStarted,
    IndicatorStopping,
    IndicatorStopped,
};

@interface NSWindowController (LongOperationIndicatorPrivate)
+ (void)_longIndicatorThread:(id)arg;
@end

@interface _OATransparentFillView : NSView
@end
@implementation _OATransparentFillView
- (void)drawRect:(NSRect)r;
{
    [[NSColor clearColor] set];
    NSRectFillUsingOperation(r, NSCompositeCopy);
}
@end

@implementation NSWindowController (OAExtensions)

static NSWindow *RootlessProgressWindow = nil;

+ (void)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize progressStyle:(NSProgressIndicatorStyle)progressStyle inWindow:(NSWindow *)documentWindow automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
{
    OBPRECONDITION([NSThread isMainThread]);

    DEBUG_LONG_OPERATION_INDICATOR(@"%s: documentWindow=%p operationDescription=%@", __PRETTY_FUNCTION__, documentWindow, operationDescription);

    if (!LongOperationIndicatorEnabledForWindow(documentWindow))
        return;
    
    if (![documentWindow isVisible])
        // If we're hidden, window ordering operations will unhide us.
        return;

    if ([operationWindow parentWindow] == documentWindow) {
        // This can happen if you hit cmd-s twice really fast.
        [self continuingLongOperation:operationDescription];
        return;
    } else if ([operationWindow parentWindow]) {
        // There is an operation on a *different* window; cancel it
        [self finishedLongOperation];
    }

    OBASSERT(!operationWindow || [operationWindow parentWindow] == nil || [operationWindow parentWindow] == documentWindow);

    if (!operationWindow) {
        indicatorView = [[_OALongOperationIndicatorView alloc] initWithFrame:NSZeroRect controlSize:controlSize progressStyle:progressStyle];
        operationWindow = [[NSPanel alloc] initWithContentRect:NSZeroRect styleMask:NSBorderlessWindowMask backing:[documentWindow backingType] defer:NO];
        [operationWindow setReleasedWhenClosed:NO]; // We'll manage this manually

        if ([operationWindow respondsToSelector:@selector(setCollectionBehavior:)])
            [operationWindow setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];

        [[operationWindow contentView] addSubview:indicatorView];
        [operationWindow setIgnoresMouseEvents:YES];
        DEBUG_LONG_OPERATION_INDICATOR(@"%s: operationWindow=%@", __PRETTY_FUNCTION__, [operationWindow shortDescription]);
    }

    [indicatorView setTitle:operationDescription documentWindow:documentWindow];
    [operationWindow setOpaque:NO]; // If we do this before the line above, the window thinks it is opaque for some reason and draws as if composited against black.
    [operationWindow setAlphaValue:0.0f]; // Might be running again, so we need to start at zero alpha each time we run.
    [operationWindow displayIfNeeded]; // Make sure the window backing store is clear before we put it on screen, so it doesn't flicker up and then get redrawn clear.
    
    // Group it
    [documentWindow addChildWindow:operationWindow ordered:NSWindowAbove];

    // Ensure the ordering is right if someone was clicking around really fast
    [operationWindow orderWindow:NSWindowAbove relativeTo:[documentWindow windowNumber]];

    if (!indicatorThreadStarted) {
        indicatorThreadStarted = YES;
        indicatorLock = [[NSConditionLock alloc] initWithCondition:IndicatorStarting];
        [NSThread detachNewThreadSelector:@selector(_longIndicatorThread:) toTarget:self withObject:nil];
    } else {
        // Reset the state on the indicator lock to wake up the background thread.
        [indicatorLock lock];
        [indicatorLock unlockWithCondition:IndicatorStarting];
    }

    // Schedule an automatic shutdown of the long operation when we get back to the event loop.  Queue this in both the main and modal modes since otherwise quitting when there are two documents to save (and you select to save both) will never process the finish event from the first.
    if (shouldAutomaticallyEnd)
        [self performSelector:@selector(finishedLongOperation) withObject:nil afterDelay:0.0f inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
}

+ (NSWindow *)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize progressStyle:(NSProgressIndicatorStyle)progressStyle automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
{
    if (!LongOperationIndicatorEnabledForWindow(nil))
        return nil;
        
    // This is to work around <bug://bugs/33685>.  Otherwise we unhide a hidden app. 
    if ([NSApp isHidden])
	return nil;
    
    if (RootlessProgressWindow == nil) {
        // We don't know how long of a message the caller will want to put in our fake document window...
        NSRect contentRect = NSMakeRect(0, 0, 200, 100);
        NSWindow *window = [[[NSPanel alloc] initWithContentRect:contentRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO] autorelease];
        [window setReleasedWhenClosed:NO]; // We'll manage this manually
        
        if ([window respondsToSelector:@selector(setCollectionBehavior:)])
            [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];

        _OATransparentFillView *view = [[_OATransparentFillView alloc] initWithFrame:contentRect];
        [[window contentView] addSubview:view];
        [view release];
        
        [window setIgnoresMouseEvents:YES];
        [window setOpaque:NO]; // If we do this before the line above, the window thinks it is opaque for some reason and draws as if composited against black.

        RootlessProgressWindow = [window retain];
    }
         
    [RootlessProgressWindow center];
    [RootlessProgressWindow orderFront:nil];

    [self startingLongOperation:operationDescription controlSize:controlSize progressStyle:progressStyle inWindow:RootlessProgressWindow automaticallyEnds:shouldAutomaticallyEnd];
    return RootlessProgressWindow;
}

// Public API is unchanged for now, we haven't spent enough time testing the progress bar style and what happens when someone tries to switch between the two in the same window

+ (NSWindow *)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize;
{
    return [self startingLongOperation:operationDescription controlSize:controlSize progressStyle:NSProgressIndicatorSpinningStyle automaticallyEnds:YES];
}

+ (void)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize inWindow:(NSWindow *)documentWindow automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
{
    [self startingLongOperation:operationDescription controlSize:controlSize progressStyle:NSProgressIndicatorSpinningStyle inWindow:documentWindow automaticallyEnds:shouldAutomaticallyEnd];
}

+ (void)continuingLongOperation:(NSString *)operationStatus;
{
    DEBUG_LONG_OPERATION_INDICATOR(@"%s: documentWindow:%p operationStatus=%@", __PRETTY_FUNCTION__, [operationWindow parentWindow], operationStatus);
    OBPRECONDITION([NSThread isMainThread]);

    if (!LongOperationIndicatorEnabledForWindow([operationWindow parentWindow]))
        return;

    if (![operationWindow parentWindow]) {
        // Nothing going on, supposedly.  Maybe the document window isn't visible or we're hidden.
        return;
    }
    
    [indicatorView setTitle:operationStatus documentWindow:[operationWindow parentWindow]];
}

+ (void)continuingLongOperationWithProgress:(double)progress;
    // Not yet published, since we haven't yet published the progress bar style API
{
    OBPRECONDITION([NSThread isMainThread]);

    if (!LongOperationIndicatorEnabledForWindow([operationWindow parentWindow]))
        return;

    if (![operationWindow parentWindow]) {
        // Nothing going on, supposedly.  Maybe the document window isn't visible or we're hidden.
        return;
    }
    
    [[indicatorView progressIndicator] setDoubleValue:progress];
}

// This should be called when closing a window that might have a long operation indicator on it.  Consider the case of a quick cmd-s/cmd-w (<bug://bugs/17833> - Crash saving & closing default document template) where the timer might not fire before the parent window is deallocated.  This would also be fixed if Apple would break the parent/child window association on deallocation of the parent window...
+ (void)finishedLongOperationForWindow:(NSWindow *)window;
{
    if ([operationWindow parentWindow] != window)
        return;
    
    if (!LongOperationIndicatorEnabledForWindow(window))
        return;
    
    [self finishedLongOperation];
}

+ (void)finishedLongOperation;
{
    DEBUG_LONG_OPERATION_INDICATOR(@"%s documentWindow=%p", __PRETTY_FUNCTION__, [operationWindow parentWindow]);
    OBPRECONDITION([NSThread isMainThread]);

    if (!LongOperationIndicatorEnabledForWindow(nil))
        return;

    // Cancel any pending automatic cancellation
    [NSRunLoop cancelPreviousPerformRequestsWithTarget:self];
    
    // Tell the background thread to bail
    [indicatorLock lock];
    if ([indicatorLock condition] == IndicatorStarted) {
        // Tell the background thread to stop
        [indicatorLock unlockWithCondition:IndicatorStopping];

        // Wait for it to do so, so that we can access the window it was mucking with before
        [indicatorLock lockWhenCondition:IndicatorStopped];
        [indicatorLock unlock];
    } else {
        // The background thread never started; revert to the stopped state
        [indicatorLock unlockWithCondition:IndicatorStopped];
    }

    // Might be doing a global long operation (operation window not tied to another window, just floating)
    NSWindow *parentWindow = [operationWindow parentWindow];
    if (parentWindow)
        [parentWindow removeChildWindow:operationWindow];
    [operationWindow orderOut:nil];
    if (operationWindow == RootlessProgressWindow) {
        [RootlessProgressWindow release];
        RootlessProgressWindow = nil;
    }
}

- (void)startingLongOperation:(NSString *)operationDescription;
{
    if (!LongOperationIndicatorEnabledForWindow(nil))
        return;

    [isa startingLongOperation:operationDescription controlSize:NSSmallControlSize inWindow:[self window] automaticallyEnds:YES];
}

@end

@implementation NSWindowController (OAExtensionsPrivate)

+ (void)_longIndicatorThread:(id)arg;
{
    // This thread lives forever once started.  This avoids creating per-thread graphics contexts over and over (since NSProgressIndicator seemed to be leaking them!)
    while (YES) {
        [indicatorLock lockWhenCondition:IndicatorStarting];
        [indicatorLock unlockWithCondition:IndicatorStarted];

        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        BOOL didLock = NO;
    
        if ([indicatorLock lockWhenCondition:IndicatorStopping beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]]) {
            // Cancelled
            didLock = YES;
        } else {
            // Fade the window in, checking for cancellation
#define FADE_IN_TIME (0.25f)
#define FADE_IN_FRAMES (10)
#define TIME_PER_FRAME (FADE_IN_TIME/FADE_IN_FRAMES)

            // This means that there is *another* thread drawing into the window.  We modify the alpha from this thread which should be save since the animation thread isn't poking that and the alpha value is entirely processed on the window server.
            [[indicatorView progressIndicator] startAnimation:nil];

            float elapsedTime = 0.0f;
            while (YES) {
                // Don't build up a ton of autoreleased dates
                [pool release];
                pool = [[NSAutoreleasePool alloc] init];

                [operationWindow setAlphaValue:MIN(MAX_ALPHA, MAX_ALPHA*(elapsedTime/FADE_IN_TIME))];

                // Check the lock to see if we've been told to buzz off
                if ([indicatorLock lockWhenCondition:IndicatorStopping beforeDate:[NSDate dateWithTimeIntervalSinceNow:TIME_PER_FRAME]]) {
                    // Bummer, cancelled
                    didLock = YES;
                    break;
                }
                elapsedTime += TIME_PER_FRAME;
            }

            [[indicatorView progressIndicator] stopAnimation:nil];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantPast]];
        }

        if (!didLock)
            [indicatorLock lock];
        [indicatorLock unlockWithCondition:IndicatorStopped];
        [pool release];
    }
}

@end
