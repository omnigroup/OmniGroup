// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAViewPicker.h>
#import <OmniAppKit/OATrackingLoop.h>

RCS_ID("$Id$");

@implementation OAViewPicker

static OAViewPicker *ActivePicker;

+ (void)beginPickingForWindow:(NSWindow *)window withCompletionHandler:(OAViewPickerCompletionHandler)completionHandler;
{
    OAViewPicker *picker = [[self alloc] initWithContentRect:[window frame] styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    OBASSERT_NOTNULL(picker);
    
    if (!picker) {
        completionHandler(nil);
        return;
    }
    
    [picker setOpaque:NO];
    [picker setBackgroundColor:[NSColor clearColor]];
    [picker setOneShot:YES];
    [picker setReleasedWhenClosed:NO];
    [picker setAcceptsMouseMovedEvents:YES];
    [picker setIgnoresMouseEvents:NO];
    
    [ActivePicker close];
    
    OBASSERT_NULL(ActivePicker);
    ActivePicker = [picker retain];
    
    [picker _beginPickingForWindow:window withCompletionHandler:completionHandler];
}

+ (BOOL)cancelActivePicker;
{
    if (ActivePicker) {
        [ActivePicker close];
        return YES;
    } else {
        return NO;
    }
}

- (void)_beginPickingForWindow:(NSWindow *)window withCompletionHandler:(OAViewPickerCompletionHandler)completionHandler;
{
    [window addChildWindow:self ordered:NSWindowAbove];
    
    OBASSERT_NULL(_nonretained_parentWindowObserver);
    _nonretained_parentWindowObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:window queue:nil usingBlock:^(NSNotification *note) {
        [self close];
    }];
    
    _completionHandler = Block_copy(completionHandler);
    
    [self orderFront:nil];
    [self _updatePickedView:[self mouseLocationOutsideOfEventStream]];
}

static void EndActivePicker()
{
    // This is in its own function to ensure we don't try to access self in the middle of releasing the last reference to it
    [ActivePicker release];
    ActivePicker = nil;
}

- (void)close;
{
    OBASSERT_NOTNULL(_nonretained_parentWindowObserver);
    [[NSNotificationCenter defaultCenter] removeObserver:_nonretained_parentWindowObserver];
    
    [super close];
    
    if (_completionHandler) {
        // If we got here, we didn't pick a view and are closing because our parent window closed
        _completionHandler(nil);
        [_completionHandler release];
        _completionHandler = nil;
    }
    
    OBASSERT(self == ActivePicker);
    EndActivePicker();
}

static NSView *_rootView(NSView *view)
{
    for (NSView *superview = view; superview != nil; superview = [view superview])
        view = superview;
    
    return view;
}

- (NSPoint)mouseLocation:(NSPoint)mouseLocationInOurWindow inWindow:(NSWindow *)otherWindow;
{
    return [otherWindow convertRectFromScreen:[self convertRectToScreen:(NSRect){.origin = mouseLocationInOurWindow, .size={1,1}}]].origin;
}

- (void)_updatePickedView:(NSPoint)mouseLocationInOurWindow;
{
    NSWindow *parentWindow = [self parentWindow];
    NSView *otherRootView = _rootView([parentWindow contentView]);
    NSPoint pointInOtherRootView = [otherRootView convertPoint:[self mouseLocation:mouseLocationInOurWindow inWindow:parentWindow] fromView:nil];
    
    NSView *hitView = [[otherRootView hitTest:pointInOtherRootView] retain];
    [_pickedView release];
    _pickedView = hitView;
    
    [self _updateHighlight];
}

- (void)_updateHighlight;
{
    if (!_pickedView) {
        [_nonretained_highlightBox removeFromSuperview];
        _nonretained_highlightBox = nil;
        return;
    }
    
    NSWindow *parentWindow = [self parentWindow];
    NSRect highlightRectInOtherWindow = [_pickedView convertRect:[_pickedView bounds] toView:nil];
    NSRect highlightRectInThisWindow = [self convertRectFromScreen:[parentWindow convertRectToScreen:highlightRectInOtherWindow]];
    
    NSView *ourContentView = [self contentView];
    NSRect highlightBoxFrame = [ourContentView convertRect:highlightRectInThisWindow fromView:nil];
    
    if (_nonretained_highlightBox) {
        [_nonretained_highlightBox setFrame:highlightBoxFrame];
    } else {
        _nonretained_highlightBox = [[NSBox alloc] initWithFrame:highlightBoxFrame];
        [_nonretained_highlightBox setBoxType:NSBoxCustom];
        [_nonretained_highlightBox setFillColor:[[NSColor blueColor] colorWithAlphaComponent:0.2f]];
        [_nonretained_highlightBox setBorderColor:[NSColor blueColor]];
        [ourContentView addSubview:_nonretained_highlightBox];
        [_nonretained_highlightBox release];
    }
    
    [_nonretained_highlightBox setToolTip:[_pickedView shortDescription]];
}

- (void)_verifyPickedView:(NSPoint)mouseLocationInOurWindow;
{
    NSWindow *parentWindow = [self parentWindow];
    if ([_pickedView window] == parentWindow) {
        NSPoint pointInOtherWindow = [self mouseLocation:mouseLocationInOurWindow inWindow:parentWindow];
        if ([_pickedView mouse:[_pickedView convertPoint:pointInOtherWindow fromView:nil] inRect:[_pickedView visibleRect]])
            return;
    }
    
    // If we didn't early-out, the current picked view is no longer valid
    [self _updatePickedView:mouseLocationInOurWindow];
}

- (void)mouseMoved:(NSEvent *)theEvent;
{
    if (!_isInMouseDown)
        [self _updatePickedView:[theEvent locationInWindow]];
}

- (void)mouseDown:(NSEvent *)theEvent;
{
    _isInMouseDown = YES;
    [self _verifyPickedView:[theEvent locationInWindow]];
    if (_pickedView) {
        if (_completionHandler(_pickedView)) {
            [_completionHandler release];
            _completionHandler = nil;
            [self close];
        }
    }
    _isInMouseDown = NO;
}

- (void)scrollWheel:(NSEvent *)theEvent;
{
    if ([theEvent deltaY] < 0) {
        NSView *superview = [_pickedView superview];
        if (superview != nil) {
            NSView *oldPickedView = _pickedView;
            _pickedView = [superview retain];
            [oldPickedView release];
        }
    }
    
    [self _updateHighlight];
}

@end
