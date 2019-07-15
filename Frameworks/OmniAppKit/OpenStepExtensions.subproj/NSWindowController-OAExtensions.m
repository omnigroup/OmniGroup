// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSWindowController-OAExtensions.h>

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <OmniAppKit/NSAppearance-OAExtensions.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

#if 0 && defined(DEBUG)
    #define DEBUG_LONG_OPERATION_INDICATOR(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_LONG_OPERATION_INDICATOR(format, ...)
#endif

static BOOL LongOperationIndicatorEnabledForWindow(NSWindow * _Nullable window)
{
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"LongOperationIndicatorDisabled"]) {
        return NO;
    }

    // Let the application's delegate check.
    id controller = [NSApplication.sharedApplication delegate];
    if ([controller respondsToSelector:@selector(shouldShowLongOperationIndicatorForWindow:)]) {
        return [controller shouldShowLongOperationIndicatorForWindow:window];
    }
    
    return YES;
}

static void _AutosizeLongOperationWindow(NSWindow *documentWindow);

static void _DisplayWindow(NSWindow *window)
{
    // Seems like the only way to force a screen update when the main thread is blocked is -displayIfNeeded, followed by flushing the results to the screen.
    
    if (window.visible) {
        [window updateConstraintsIfNeeded];
        [window layoutIfNeeded];
        [window displayIfNeeded];
    }

    // We need to get the results on the screen. Use +[CATransaction flush] instead of running the run loop, which may hve the side effect of firing timers.
    [CATransaction flush];
//  [NSRunLoop.currentRunLoop runUntilDate:NSDate.distantPast];
}

#pragma mark -

@interface NSProgressIndicator (OALongOperationIndicatorExtensions_Radar_34468617)

@property (nonatomic, readonly) BOOL omni_threadedAnimationIsBroken;
@property (nonatomic, readonly) NSImage *omni_imageRepresentation;

@end

#pragma mark -

@interface _OALongOperationIndicatorView : NSView {
  @private
    NSProgressIndicator *_progressIndicator;
    NSImageView *_progressIndicatorImageView;
    NSTextField *_label;
    NSColor *_backgroundColor;
    NSColor *_borderColor;
}

- (id)initWithFrame:(NSRect)frame controlSize:(NSControlSize)controlSize progressStyle:(NSProgressIndicatorStyle)progressStyle;

- (void)setTitle:(NSString *)title documentWindow:(NSWindow *)documentWindow;

@property (nonatomic, readonly) NSProgressIndicator *progressIndicator;
@property (nonatomic, readonly) NSProgressIndicatorStyle progressStyle;

@end

#pragma mark -

@implementation _OALongOperationIndicatorView : NSView

- (void)dealloc;
{
    [_progressIndicator release];
    [_progressIndicatorImageView release];
    [_label release];
    [_backgroundColor release];
    [_borderColor release];

    [super dealloc];
}

- (id)initWithFrame:(NSRect)frame controlSize:(NSControlSize)controlSize progressStyle:(NSProgressIndicatorStyle)progressStyle;
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }

    _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _progressIndicator.controlSize = controlSize;
    _progressIndicator.usesThreadedAnimation = YES;
    _progressIndicator.style = progressStyle;
    _progressIndicator.indeterminate = (progressStyle == NSProgressIndicatorStyleSpinning);
    _progressIndicator.displayedWhenStopped = YES;
    
    _backgroundColor = [[NSColor colorWithCalibratedWhite:0.95 alpha:1.0] copy];
    _borderColor = [[NSColor colorWithWhite:0.0 alpha:0.05] copy];

#if 0 && defined(DEBUG_correia)
    _progressIndicator.wantsLayer = YES;
    _progressIndicator.layer.backgroundColor = [NSColor.yellowColor colorWithAlphaComponent:0.5].CGColor;
#endif

    if (!_progressIndicator.indeterminate) {
        _progressIndicator.minValue = 0.0;
        _progressIndicator.maxValue = 1.0;
    }

    [_progressIndicator sizeToFit];
    
    [self addSubview:_progressIndicator];

    CGFloat fontSize = (controlSize == NSControlSizeSmall) ? NSFont.smallSystemFontSize : NSFont.systemFontSize;
    
    _label = [[NSTextField labelWithString:@""] retain];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.controlSize = controlSize;
    _label.textColor = [NSColor.blackColor colorWithAlphaComponent:0.85];
    _label.font = [NSFont boldSystemFontOfSize:fontSize];
    _label.lineBreakMode = NSLineBreakByTruncatingTail;

    [self addSubview:_label];
    
    const CGFloat standardSpacing = 10;
    // Note that we also specify a minimum width for both styles so that the window looks reasonable.
    
    if (progressStyle == NSProgressIndicatorStyleSpinning) {
        NSArray<NSLayoutConstraint *> *constraints = @[
            // Horizontal
            [_progressIndicator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:standardSpacing],
            [_label.leadingAnchor constraintEqualToAnchor:_progressIndicator.trailingAnchor constant:standardSpacing],
            [self.trailingAnchor constraintEqualToAnchor:_label.trailingAnchor constant:standardSpacing],
            [self.widthAnchor constraintGreaterThanOrEqualToConstant:208],

            // Vertical
            [_progressIndicator.topAnchor constraintEqualToAnchor:self.topAnchor constant:standardSpacing],
            [self.bottomAnchor constraintEqualToAnchor:_progressIndicator.bottomAnchor constant:standardSpacing],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            
            // Sizes
            [_progressIndicator.widthAnchor constraintGreaterThanOrEqualToConstant:32],
            [_progressIndicator.heightAnchor constraintGreaterThanOrEqualToConstant:32],
        ];

        [NSLayoutConstraint activateConstraints:constraints];
    } else {
        NSArray<NSLayoutConstraint *> *constraints = @[
            // Horizontal
            [_progressIndicator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:standardSpacing],
            [self.trailingAnchor constraintEqualToAnchor:_progressIndicator.trailingAnchor constant:standardSpacing],
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:standardSpacing],
            [self.trailingAnchor constraintEqualToAnchor:_label.trailingAnchor constant:standardSpacing],
            [self.widthAnchor constraintGreaterThanOrEqualToConstant:345],

            // Vertical
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:standardSpacing],
            [_progressIndicator.topAnchor constraintEqualToAnchor:_label.bottomAnchor constant:standardSpacing],
            [self.bottomAnchor constraintEqualToAnchor:_progressIndicator.bottomAnchor constant:standardSpacing],

            // Sizes
            [_progressIndicator.heightAnchor constraintGreaterThanOrEqualToConstant:_progressIndicator.frame.size.height],
        ];

        [NSLayoutConstraint activateConstraints:constraints];
    }
    
    // If threaded animation is known to be broken, display a static representation of the progress indicator instead.
    if (progressStyle == NSProgressIndicatorStyleSpinning && _progressIndicator.omni_threadedAnimationIsBroken) {
        _progressIndicatorImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _progressIndicatorImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _progressIndicatorImageView.image = _progressIndicator.omni_imageRepresentation;
        
        _progressIndicator.hidden = YES;
        
        [self addSubview:_progressIndicatorImageView];

        NSArray<NSLayoutConstraint *> *constraints = @[
            [_progressIndicatorImageView.centerXAnchor constraintEqualToAnchor:_progressIndicator.centerXAnchor],
            [_progressIndicatorImageView.centerYAnchor constraintEqualToAnchor:_progressIndicator.centerYAnchor],
        ];

        [NSLayoutConstraint activateConstraints:constraints];
    }
    
    [self _OALongOperationIndicatorView_updateForCurrentAppearance];

    return self;
}

- (void)setTitle:(NSString *)title documentWindow:(NSWindow *)documentWindow;
{
    OBPRECONDITION(_progressIndicator != nil);
    OBPRECONDITION(_label != nil);

    OBASSERT_NOTNULL(title); // This is the default since we are default-nonnull in this file, but OFISEQUAL checks for nil.

    if (!OFISEQUAL(title, _label.stringValue)) {
        _label.stringValue = title;
    }
    
    _AutosizeLongOperationWindow(documentWindow);
}

- (NSProgressIndicator *)progressIndicator;
{
    return _progressIndicator;
}

- (NSProgressIndicatorStyle)progressStyle;
{
    return _progressIndicator.style;
}

- (BOOL)isOpaque;
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect;
{
    NSRect bounds = self.bounds;

    [NSColor.clearColor set];
    NSRectFillUsingOperation(bounds, NSCompositingOperationCopy);

    NSRect rect = NSInsetRect(bounds, 0.5f, 0.5f);
    CGFloat radius = 7.0f;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    
    [_backgroundColor setFill];
    [_borderColor setStroke];
    
    [path fill];
    [path stroke];
    
#if 0 && defined(DEBUG_correia)
    [NSColor.redColor set];
    NSFrameRect(_progressIndicator.frame);
#endif
}

- (void)viewDidChangeEffectiveAppearance;
{
    [super viewDidChangeEffectiveAppearance];
    [self _OALongOperationIndicatorView_updateForCurrentAppearance];
}

- (void)_OALongOperationIndicatorView_updateForCurrentAppearance;
{
    [_backgroundColor release];
    _backgroundColor = nil;
    
    [_borderColor release];
    _borderColor = nil;
    
    if ([self.effectiveAppearance OA_isDarkAppearance]) {
        _backgroundColor = [[NSColor colorWithCalibratedWhite:0.17 alpha:1.0] copy];
        _borderColor = [[NSColor colorWithWhite:1.0 alpha:0.05] copy];
        _label.textColor = [NSColor.whiteColor colorWithAlphaComponent:0.85];
    } else {
        _backgroundColor = [[NSColor colorWithCalibratedWhite:0.95 alpha:1.0] copy];
        _borderColor = [[NSColor colorWithWhite:0.0 alpha:0.05] copy];
        _label.textColor = [NSColor.blackColor colorWithAlphaComponent:0.85];
    }
}

@end

#pragma mark -

@interface _OATransparentFillView : NSView
@end

#pragma mark -

@implementation _OATransparentFillView

- (void)drawRect:(NSRect)dirtyRect;
{
    [NSColor.clearColor set];
    NSRectFillUsingOperation(dirtyRect, NSCompositingOperationCopy);
}

@end

#pragma mark -

// We assume that only one document can be saving at a time.

static const NSTimeInterval FadeInDelay = 0.50;
static const NSTimeInterval FadeInTime = 0.25;

static NSWindow * _Nullable _RootlessProgressWindow = nil;

static NSWindow * _Nullable _LongOperationWindow = nil;
static _OALongOperationIndicatorView * _Nullable _IndicatorView = nil;

static NSAnimation * _Nullable _DelayAnimation = nil;
static NSAnimation * _Nullable _FadeInAnimation = nil;

static void _BeginFadeInAnimation(void);
static void _CancelFadeInAnimation(void);

static void _BeginFadeInAnimation(void)
{
    OBPRECONDITION(_DelayAnimation == nil);
    OBPRECONDITION(_FadeInAnimation == nil);
    OBPRECONDITION(_LongOperationWindow != nil);

    _CancelFadeInAnimation();
    
    _DelayAnimation = [[NSAnimation alloc] init];
    _DelayAnimation.animationBlockingMode = NSAnimationNonblockingThreaded;
    _DelayAnimation.duration = FadeInDelay;
    
    NSArray *animations = @[
        @{
            NSViewAnimationTargetKey: _LongOperationWindow,
            NSViewAnimationEffectKey: NSViewAnimationFadeInEffect,
        },
    ];
    
    _FadeInAnimation = [[NSViewAnimation alloc] initWithViewAnimations:animations];
    _FadeInAnimation.duration = FadeInTime;
    _FadeInAnimation.animationBlockingMode = NSAnimationNonblockingThreaded;

    [_FadeInAnimation startWhenAnimation:_DelayAnimation reachesProgress:1.0];

    [_IndicatorView.progressIndicator startAnimation:nil];

    // Make sure the window has been "displayed" and layed out once before we start the animation.
    _DisplayWindow(_LongOperationWindow);
    [_DelayAnimation startAnimation];
}

static void _CancelFadeInAnimation(void)
{
    [_IndicatorView.progressIndicator stopAnimation:nil];
    
    [_FadeInAnimation stopAnimation];
    [_FadeInAnimation release];
    _FadeInAnimation = nil;

    [_DelayAnimation stopAnimation];
    [_DelayAnimation release];
    _DelayAnimation = nil;
}

static BOOL _IsFadeAnimationInProgress(void)
{
    return _FadeInAnimation.animating || _DelayAnimation.animating;
}

static void _AutosizeLongOperationWindow(NSWindow *documentWindow)
{
    OBPRECONDITION(_LongOperationWindow != nil);
    OBPRECONDITION(_IndicatorView != nil);

    NSWindow *window = _LongOperationWindow;
    NSView *indicatorView = _IndicatorView;

    // We can't resize the operation window if the face in animation is in progress because NSViewAnimation repeatedly sets the frame on the window during the fade-in, and this will cause the autolayout engine to become dirty, then be accessed from a background thread.
    //
    // It is fairly uncommon to change the string during progress, and if we do, trunctation plus the minimum window size will cover us there.
    
    if (_IsFadeAnimationInProgress()) {
        _DisplayWindow(window);
    } else {
        NSSize fittingSize = indicatorView.fittingSize;
        indicatorView.frameSize = fittingSize;
        
        NSRect windowFrame = documentWindow.frame;
        windowFrame.origin.x = NSMinX(windowFrame) + (CGFloat)floor((NSWidth(windowFrame) - fittingSize.width) / 2.0f);
        if (NSHeight(documentWindow.frame) < 300) {
            // Center on small windows
            windowFrame.origin.y = NSMinY(windowFrame) + (CGFloat)floor((NSHeight(windowFrame) - fittingSize.height) / 2.0f);
        } else {
            // Alert position (1/3 of the way down) over the content area of the window
            windowFrame.origin.y = NSMaxY(windowFrame) - (CGFloat)floor((NSHeight(windowFrame) + fittingSize.height) / 3.0f);
            windowFrame.origin.y -= (CGFloat)floor((NSHeight(windowFrame) - NSHeight(documentWindow.contentView.frame)) / 2.0f);
        }
        windowFrame.size = fittingSize;
        
    #if 0 && defined(DEBUG_correia)
        NSLog(@"Setting window frame to: %@", NSStringFromRect(windowFrame));
    #endif
        
        [indicatorView setNeedsDisplay:YES];
        [window setFrame:windowFrame display:window.visible];
        
        _DisplayWindow(window);
    }
}

@implementation NSWindowController (OAExtensions)

+ (void)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize progressStyle:(NSProgressIndicatorStyle)progressStyle inWindow:(NSWindow *)documentWindow automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
{
    OBPRECONDITION([NSThread isMainThread]);

    DEBUG_LONG_OPERATION_INDICATOR(@"%s: documentWindow=%p operationDescription=%@", __PRETTY_FUNCTION__, documentWindow, operationDescription);

    if (!LongOperationIndicatorEnabledForWindow(documentWindow)) {
        return;
    }
    
    if (!documentWindow.visible) {
        // If we're hidden, window ordering operations will unhide us.
        return;
    }

    NSWindow *parentWindow = _LongOperationWindow.parentWindow;
    if (parentWindow == documentWindow) {
        // This can happen if you hit cmd-s twice really fast.
        [self continuingLongOperation:operationDescription];
        return;
    } else if (parentWindow != nil) {
        // There is an operation on a *different* window; cancel it
        [self finishedLongOperation];
    }

    OBASSERT(_LongOperationWindow == nil || parentWindow == nil || parentWindow == documentWindow);

    if (_LongOperationWindow != nil && _IndicatorView.progressStyle != progressStyle) {
        [_LongOperationWindow release];
        _LongOperationWindow = nil;
        
        [_IndicatorView release];
        _IndicatorView = nil;
    }
    
    if (_LongOperationWindow == nil) {
        NSRect frame = NSMakeRect(0, 0, 500, 500); // Some non-zero size large enough that constraints are satisfiable.
        _IndicatorView = [[_OALongOperationIndicatorView alloc] initWithFrame:frame controlSize:controlSize progressStyle:progressStyle];
        _IndicatorView.autoresizingMask = NSViewNotSizable;
        
        _LongOperationWindow = [[NSPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:documentWindow.backingType defer:NO];
        _LongOperationWindow.releasedWhenClosed = NO; // We'll manage this manually

        if ([_LongOperationWindow respondsToSelector:@selector(setCollectionBehavior:)]) {
            [_LongOperationWindow setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
        }

        [_LongOperationWindow.contentView addSubview:_IndicatorView];
        [_LongOperationWindow setIgnoresMouseEvents:YES];
        
        DEBUG_LONG_OPERATION_INDICATOR(@"%s: operationWindow=%@", __PRETTY_FUNCTION__, [operationWindow shortDescription]);
    }

    [_IndicatorView setTitle:operationDescription documentWindow:documentWindow];
    _LongOperationWindow.backgroundColor = NSColor.clearColor;
    _LongOperationWindow.opaque = NO; // If we do this before the line above, the window thinks it is opaque for some reason and draws as if composited against black.
    _LongOperationWindow.alphaValue = 0; // Might be running again, so we need to start at zero alpha each time we run.
    [_LongOperationWindow displayIfNeeded]; // Make sure the window backing store is clear before we put it on screen, so it doesn't flicker up and then get redrawn clear.
    
    // Group it
    [documentWindow addChildWindow:_LongOperationWindow ordered:NSWindowAbove];

    // Ensure the ordering is right if someone was clicking around really fast
    [_LongOperationWindow orderWindow:NSWindowAbove relativeTo:documentWindow.windowNumber];

    _DisplayWindow(_LongOperationWindow);
    _BeginFadeInAnimation();

    // Schedule an automatic shutdown of the long operation when we get back to the event loop.  Queue this in both the main and modal modes since otherwise quitting when there are two documents to save (and you select to save both) will never process the finish event from the first.
    if (shouldAutomaticallyEnd) {
        [self performSelector:@selector(finishedLongOperation) withObject:nil afterDelay:0.0f inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
    }
}

+ (nullable NSWindow *)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize progressStyle:(NSProgressIndicatorStyle)progressStyle automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (!LongOperationIndicatorEnabledForWindow(nil)) {
        return nil;
    }
        
    // This is to work around <bug://bugs/33685>.  Otherwise we unhide a hidden app. 
    if ([NSApplication.sharedApplication isHidden]) {
	return nil;
    }
    
    if (_RootlessProgressWindow == nil) {
        // We don't know how long of a message the caller will want to put in our fake document window...
        NSRect contentRect = NSMakeRect(0, 0, 200, 100);
        NSWindow *window = [[[NSPanel alloc] initWithContentRect:contentRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO] autorelease];
        [window setReleasedWhenClosed:NO]; // We'll manage this manually
        [window setLevel:NSFloatingWindowLevel]; // Float above normal windows. This also triggers NSWindowCollectionBehaviorTransient on 10.6.
        window.backgroundColor = NSColor.clearColor;
        
        if ([window respondsToSelector:@selector(setCollectionBehavior:)]) {
            [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
        }

        _OATransparentFillView *view = [[_OATransparentFillView alloc] initWithFrame:contentRect];
        [window.contentView addSubview:view];
        [view release];
        
        [window setIgnoresMouseEvents:YES];
        [window setOpaque:NO]; // If we do this before the line above, the window thinks it is opaque for some reason and draws as if composited against black.

        _RootlessProgressWindow = [window retain];
    }
         
    [_RootlessProgressWindow center];
    [_RootlessProgressWindow displayIfNeeded]; // Make sure the window backing store is clear before we put it on screen, so it doesn't flicker up (or get stuck) and then get redrawn clear.
    [_RootlessProgressWindow orderFront:nil];

    [self startingLongOperation:operationDescription controlSize:controlSize progressStyle:progressStyle inWindow:_RootlessProgressWindow automaticallyEnds:shouldAutomaticallyEnd];
    return _RootlessProgressWindow;
}

// Public API is unchanged for now, we haven't spent enough time testing the progress bar style and what happens when someone tries to switch between the two in the same window

+ (nullable NSWindow *)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize;
{
    return [self startingLongOperation:operationDescription controlSize:controlSize progressStyle:NSProgressIndicatorStyleSpinning automaticallyEnds:YES];
}

+ (void)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize inWindow:(NSWindow *)documentWindow automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
{
    [self startingLongOperation:operationDescription controlSize:controlSize progressStyle:NSProgressIndicatorStyleSpinning inWindow:documentWindow automaticallyEnds:shouldAutomaticallyEnd];
}

+ (void)continuingLongOperation:(NSString *)operationStatus;
{
    DEBUG_LONG_OPERATION_INDICATOR(@"%s: documentWindow:%p operationStatus=%@", __PRETTY_FUNCTION__, operationWindow.parentWindow, operationStatus);
    OBPRECONDITION([NSThread isMainThread]);

    NSWindow *parentWindow = _LongOperationWindow.parentWindow;
    if (!LongOperationIndicatorEnabledForWindow(parentWindow)) {
        return;
    }

    if (parentWindow == nil) {
        // Nothing going on, supposedly.  Maybe the document window isn't visible or we're hidden.
        return;
    }
    
    [_IndicatorView setTitle:operationStatus documentWindow:parentWindow];
}

+ (void)continuingLongOperationWithProgress:(double)progress;
    // Not yet published, since we haven't yet published the progress bar style API
{
    OBPRECONDITION([NSThread isMainThread]);

    NSWindow *parentWindow = _LongOperationWindow.parentWindow;
    if (!LongOperationIndicatorEnabledForWindow(parentWindow)) {
        return;
    }

    if (parentWindow == nil) {
        // Nothing going on, supposedly.  Maybe the document window isn't visible or we're hidden.
        return;
    }
    
    [_IndicatorView.progressIndicator setDoubleValue:progress];
    _DisplayWindow(_LongOperationWindow);
}

// This should be called when closing a window that might have a long operation indicator on it.  Consider the case of a quick cmd-s/cmd-w (<bug://bugs/17833> - Crash saving & closing default document template) where the timer might not fire before the parent window is deallocated.  This would also be fixed if Apple would break the parent/child window association on deallocation of the parent window...
+ (void)finishedLongOperationForWindow:(NSWindow *)window;
{
    if (_LongOperationWindow.parentWindow != window) {
        return;
    }
    
    if (!LongOperationIndicatorEnabledForWindow(window)) {
        return;
    }
    
    [self finishedLongOperation];
}

+ (void)finishedLongOperation;
{
    DEBUG_LONG_OPERATION_INDICATOR(@"%s documentWindow=%p", __PRETTY_FUNCTION__, operationWindow.parentWindow);
    OBPRECONDITION([NSThread isMainThread]);

    if (!LongOperationIndicatorEnabledForWindow(nil)) {
        return;
    }

    // Cancel any pending automatic cancellation
    [NSRunLoop cancelPreviousPerformRequestsWithTarget:self];

    // Cancel the show animation and hide the window if needed
    _CancelFadeInAnimation();
    
    // Order out, Rootless window managment
    NSWindow *parentWindow = _LongOperationWindow.parentWindow;
    if (parentWindow != nil) {
        [parentWindow removeChildWindow:_LongOperationWindow];
    }

    [_LongOperationWindow orderOut:nil];
    
    if (parentWindow == _RootlessProgressWindow) {
        [_RootlessProgressWindow close];
        [_RootlessProgressWindow release];
        _RootlessProgressWindow = nil;
    }
}

- (void)startingLongOperation:(NSString *)operationDescription;
{
    if (!LongOperationIndicatorEnabledForWindow(nil)) {
        return;
    }

    [[self class] startingLongOperation:operationDescription controlSize:NSControlSizeSmall inWindow:[self window] automaticallyEnds:YES];
}

@end

#pragma mark -

@implementation NSProgressIndicator (OALongOperationIndicatorExtensions_Radar_34468617)

- (BOOL)omni_threadedAnimationIsBroken;
{
    // Threaded animation appears to be broken on High Sierra, and prevents the spinner from showing up at all.
    // If this returns YES, we subtitute a static image instead.
    //
    // rdar://problem/34468617

    return ![OFVersionNumber isOperatingSystemMojaveOrLater];
}

- (NSImage *)omni_imageRepresentation;
{
    NSRect rect = self.bounds;

    NSBitmapImageRep *imageRep = [self bitmapImageRepForCachingDisplayInRect:rect];
    [self cacheDisplayInRect:rect toBitmapImageRep:imageRep];
    
    NSImage *image = [[NSImage alloc] initWithSize:imageRep.size];
    [image addRepresentation:imageRep];
    
    return [image autorelease];
}

@end

NS_ASSUME_NONNULL_END
