// Copyright 2002-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAToolbarButton.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/rcsid.h>
#import <OmniAppKit/OATrackingLoop.h>

RCS_ID("$Id$");

@interface OAToolbarButton (Private)
- (NSPopUpButton *)_popUpButton;
@end

@implementation OAToolbarButton

- (void)dealloc;
{
    _nonretainedToolbarItem = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)setCell:(NSCell *)aCell;
{
    OBASSERT([aCell isKindOfClass:[NSButtonCell class]]);
             
    [(NSButtonCell *)aCell setImageScaling:NSImageScaleProportionallyUpOrDown];
    [super setCell:aCell];
}

- (NSToolbarItem *)toolbarItem;
{
    return [[_nonretainedToolbarItem retain] autorelease];
}

- (void)setToolbarItem:(NSToolbarItem *)toolbarItem;
{
    _nonretainedToolbarItem = toolbarItem;
}

- (id)delegate;
{
    return delegate;
}

- (void)setDelegate:(id)aDelegate;
{
    delegate = aDelegate;
}

//
// NSToolbarItem view
//

- (NSControlSize)controlSize;
{
    return [[self cell] controlSize];
}

- (void)setEnabled:(BOOL)enabled;
{
    [[self _popUpButton] setEnabled:enabled];
    [super setEnabled:enabled];
}

- (void)setControlSize:(NSControlSize)size;
{
    NSSize newSize;
    
    if (size == NSSmallControlSize)
        newSize = NSMakeSize(24.0f, 24.0f);
    else
        newSize = NSMakeSize(32.0f, 32.0f);

    [self setFrameSize:newSize];
    [_nonretainedToolbarItem setMinSize:newSize];
    [_nonretainedToolbarItem setMaxSize:newSize];

    NSRect myBounds = [self bounds];
    NSArray *subviews = [self subviews];
    if ([subviews count] > 0) {
        NSView *subview = [[self subviews] objectAtIndex:0];
        NSRect subviewFrame = [subview frame];
        [subview setFrame:NSMakeRect(NSWidth(myBounds) - NSWidth(subviewFrame), NSHeight(myBounds) - NSHeight(subviewFrame), NSWidth(subviewFrame), NSHeight(subviewFrame))]; // nasty hack to force it to the corner, because autoresizing doesn't seem to work
    }
    [[self cell] setControlSize:size];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)mouseDownEvent;
{
    if (![self isEnabled])
        return;
    
    if (![self action]) {
        [self highlight:YES];
        [self _showMenu];
        [self highlight:NO];
	return;
    }

    // Highlight
    [self highlight:YES];
        
    __block BOOL longPress = NO;
    
    OATrackingLoop *loop = [self trackingLoopForMouseDown:mouseDownEvent];
    loop.insideVisibleRectChanged = ^(OATrackingLoop *loop){
        [self highlight:loop.insideVisibleRect];
    };
    loop.longPress = ^(OATrackingLoop *loop){
        [self _showMenu];
        longPress = YES;
        [loop stop];
    };
    [loop run];
    
    if (!longPress && loop.insideVisibleRect)
        [self sendAction:[self action] to:[self target]];
    loop = nil;
    
    // Clear highlight
    [self highlight:NO];
}

- (void)_showMenu;
{
    NSPopUpButton *popUp = [self _popUpButton];
    if (popUp == nil)
        return;
        
    // Send fake mouseDown to popup button
    isShowingMenu = YES;
    NSRect popUpBounds = [popUp bounds];
    NSEvent *fakeEvent = [NSEvent mouseEventWithType:NSLeftMouseDown location:[popUp convertPoint:NSMakePoint(NSMidX(popUpBounds), NSMidY(popUpBounds)) toView:nil] modifierFlags:0 timestamp:0 windowNumber:[[popUp window] windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1.0f];
    [popUp mouseDown:fakeEvent];
    isShowingMenu = NO;
}

@end

@implementation OAToolbarButton (Private)

- (NSPopUpButton *)_popUpButton;
{
    if ([delegate respondsToSelector:@selector(popUpButtonForToolbarButton:)])
        return [delegate popUpButtonForToolbarButton:self];
    else
        return nil;
}

// Give the delegate the opportunity to mess with the popup button before it comes up, even if it is hit directly instead of via our action
- (void)_popupWillPop:(NSNotification *)notification;
{
    if (!isShowingMenu)
        [self _popUpButton];
}

- (void)addSubview:(NSView *)aView;
{
    [super addSubview:aView];
    if ([aView isKindOfClass:[NSPopUpButton class]]) 
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_popupWillPop:) name:NSPopUpButtonWillPopUpNotification object:aView];
}


@end
