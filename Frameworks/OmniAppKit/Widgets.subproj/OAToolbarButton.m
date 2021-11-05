// Copyright 2002-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAToolbarButton.h>

#import <Cocoa/Cocoa.h>
#import <OmniBase/rcsid.h>
#import <OmniAppKit/OATrackingLoop.h>
#import <OmniAppKit/OAToolbarItem.h>

RCS_ID("$Id$");

@interface OAToolbarButton (Private)
- (NSPopUpButton *)_popUpButton;
@end

@implementation OAToolbarButton

+ (Class)cellClass;
{
    return [OAToolbarItemButtonCell class];
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setCell:(NSCell *)aCell;
{
    OBASSERT([aCell isKindOfClass:[NSButtonCell class]]);
             
    [(NSButtonCell *)aCell setImageScaling:NSImageScaleProportionallyUpOrDown];
    [super setCell:aCell];
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
    
    if (size == NSControlSizeSmall)
        newSize = NSMakeSize(24.0f, 24.0f);
    else
        newSize = NSMakeSize(32.0f, 32.0f);

    [self setFrameSize:newSize];
    if (@available(macOS 12, *)) {
        //nope don't do this anymore. it should Just Work.
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSToolbarItem *toolbarItem = self.toolbarItem;
        [toolbarItem setMinSize:newSize];
        [toolbarItem setMaxSize:newSize];
#pragma clang diagnostic pop
    }
    
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
    loop.insideVisibleRectChanged = ^(OATrackingLoop *trackingLoop){
        [self highlight:trackingLoop.insideVisibleRect];
    };
    loop.longPress = ^(OATrackingLoop *trackingLoop){
        [self _showMenu];
        longPress = YES;
        [trackingLoop stop];
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
    NSEvent *fakeEvent = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:[popUp convertPoint:NSMakePoint(NSMidX(popUpBounds), NSMidY(popUpBounds)) toView:nil] modifierFlags:0 timestamp:0 windowNumber:[[popUp window] windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1.0f];
    [popUp mouseDown:fakeEvent];
    isShowingMenu = NO;
}

@end

@implementation OAToolbarButton (Private)

- (NSPopUpButton *)_popUpButton;
{
    id delegate = _delegate;
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
