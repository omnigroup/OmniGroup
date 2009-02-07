// Copyright 2002-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAMouseTipWindow.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import "OAMouseTipView.h"

RCS_ID("$Id$");

#define FADE_OUT_INTERVAL (0.1f)
#define OFFSET_FROM_MOUSE_LOCATION 10.0
#define TEXT_X_INSET 7.0
#define TEXT_Y_INSET 3.0
#define DISTANCE_FROM_ACTIVE_RECT 1.0

@interface OAMouseTipWindow (Private)

- (void)_preferenceChanged:(NSNotification *)note;

- (NSDictionary *)textAttributes;

- (void)setStyle:(OAMouseTipStyle)aStyle;
- (void)showMouseTipWithAttributedTitle:(NSAttributedString *)aTitle springPoint:(NSPoint)fromPoint hotSpot:(NSPoint)hotSpot maxWidth:(float)maxWidth delay:(float)delay;

- (void)_reallyOrderOutIfOwnerUnchanged:(NSTimer *)timer;
- (void)_hideAfterDelay:(float)delay;

@end

@implementation OAMouseTipWindow

static OAMouseTipWindow *mouseTipInstance;
static OFPreference *enablingPreference;

+ (void)initialize;
{
    OBINITIALIZE;
    
    mouseTipInstance = [[self alloc] init];
    enablingPreference = [[OFPreference preferenceForKey:OAMouseTipsEnabledPreferenceKey] retain];
}

- (id)init;
{
    [super initWithContentRect:NSMakeRect(0.0, 0.0, 100.0, 20.0) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    [self useOptimizedDrawing:YES];
    [self setFloatingPanel:YES];
    [self setIgnoresMouseEvents:YES];
    [self setOpaque:NO];
    mouseTipView = [[OAMouseTipView alloc] initWithFrame:[[self contentView] bounds]];
    [[self contentView] addSubview:mouseTipView];
    [mouseTipView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
    [OFPreference addObserver:self selector:@selector(_preferenceChanged:) forPreference:enablingPreference];
    
    [self setLevel:NSPopUpMenuWindowLevel];
    [self setStyle:MouseTip_TooltipStyle];

    return self;
}

+ (NSScreen *)_screenUnderPoint:(NSPoint)midPoint
{
    NSArray *screens = [NSScreen screens];
    NSScreen *screen = nil;
    float screenDistance = FLT_MAX;
    unsigned int screenCount = [screens count], screenIndex;
    for(screenIndex = 0; screenIndex < screenCount; screenIndex++) {
        float thisDistance;
        NSScreen *thisScreen;
        NSRect screenRect;
        
        thisScreen = [screens objectAtIndex:screenIndex];
        screenRect = [thisScreen frame];
        if (NSPointInRect(midPoint, screenRect)) {
            return thisScreen;
        }
        thisDistance = OFSquaredDistanceToFitRectInRect((NSRect){midPoint, {1,1}}, screenRect);
        if (thisDistance < screenDistance) {
            screenDistance = thisDistance;
            screen = thisScreen;
        }
    }
    
    return screen;
}

+ (NSRect)_adjustRect:(NSRect)aFrame toFitScreen:(NSScreen *)screen;
{
    NSRect screenRect;
    
    if (!screen)
        return aFrame;
    
    screenRect = [screen visibleFrame];
    screenRect = NSInsetRect(screenRect, 20, 0);

    if (NSHeight(aFrame) > NSHeight(screenRect))
        aFrame.origin.y = floor(NSMaxY(screenRect) - NSHeight(aFrame));
    else if (NSMaxY(aFrame) > NSMaxY(screenRect))
        aFrame.origin.y = floor(NSMaxY(screenRect) - NSHeight(aFrame));
    else if (NSMinY(aFrame) < NSMinY(screenRect))
        aFrame.origin.y = ceil(NSMinY(screenRect));
    
    if (NSMaxX(aFrame) > NSMaxX(screenRect))
        aFrame.origin.x = floor(NSMaxX(screenRect) - NSWidth(aFrame));
    if (NSMinX(aFrame) < NSMinX(screenRect))
        aFrame.origin.x = ceil(NSMinX(screenRect));
    if (aFrame.size.width > screenRect.size.width)
        aFrame.size.width = screenRect.size.width;
    
    return aFrame;
}

+ (void)showMouseTipWithTitle:(NSString *)aTitle;
{
    if (![enablingPreference boolValue])
        return;
    
    NSPoint springPoint = [NSEvent mouseLocation];
    
    springPoint.x += OFFSET_FROM_MOUSE_LOCATION + TEXT_X_INSET;
    springPoint.y += OFFSET_FROM_MOUSE_LOCATION + TEXT_Y_INSET;
    
    NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:aTitle attributes:[mouseTipInstance textAttributes]];
    [mouseTipInstance showMouseTipWithAttributedTitle:attributedTitle springPoint:springPoint hotSpot:(NSPoint){0,0} maxWidth:0 delay:0];
    [attributedTitle release];
}

+ (void)showMouseTipWithTitle:(NSString *)aTitle activeRect:(NSRect)activeRect edge:(NSRectEdge)onEdge delay:(float)delay;
{
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:aTitle attributes:[mouseTipInstance textAttributes]];
    [self showMouseTipWithAttributedTitle:title activeRect:activeRect maxWidth:0.0 edge:onEdge delay:delay];
    [title release];
}

+ (void)showMouseTipWithAttributedTitle:(NSAttributedString *)aTitle activeRect:(NSRect)activeRect maxWidth:(float)maxWidth edge:(NSRectEdge)onEdge delay:(float)delay;
{
    NSPoint hotSpot = NSZeroPoint;
    NSPoint springFrom = activeRect.origin;
    switch (onEdge) {
        case NSMinXEdge:
            springFrom.x = NSMinX(activeRect) - TEXT_X_INSET - DISTANCE_FROM_ACTIVE_RECT;
            springFrom.y = NSMidY(activeRect);
            hotSpot.x = 1.0;
            hotSpot.y = 0.5;
            break;
        case NSMinYEdge:
            springFrom.x = NSMidX(activeRect);
            springFrom.y = NSMinY(activeRect) - DISTANCE_FROM_ACTIVE_RECT - TEXT_Y_INSET;
            hotSpot.x = 0.5;
            hotSpot.y = 1.0;
            break;
        case NSMaxXEdge:
            springFrom.x = NSMaxX(activeRect) + TEXT_X_INSET + DISTANCE_FROM_ACTIVE_RECT;
            springFrom.y = NSMidY(activeRect);
            hotSpot.x = 0.0;
            hotSpot.y = 0.5;
            break;
        case NSMaxYEdge:
            springFrom.x = NSMidX(activeRect);
            springFrom.y = NSMaxY(activeRect) + DISTANCE_FROM_ACTIVE_RECT + TEXT_Y_INSET;
            hotSpot.x = 0.5;
            hotSpot.y = 0.0;
            break;
    }
    
    [mouseTipInstance showMouseTipWithAttributedTitle:aTitle springPoint:springFrom hotSpot:hotSpot maxWidth:maxWidth delay:delay];
}

- (void)_appHide:(NSNotification *)notification;
{
    [self _hideAfterDelay:0];
}

+ (void)hideMouseTip;
{
    [mouseTipInstance _hideAfterDelay:0];
}

+ (void)setOwner:(id)owner;
{
    if (mouseTipInstance != nil)
        mouseTipInstance->nonretainedOwner = owner;
}

+ (void)hideMouseTipForOwner:(id)owner;
{
    if (mouseTipInstance != nil && mouseTipInstance->nonretainedOwner == owner) 
        [self hideMouseTip];
}

+ (void)setStyle:(OAMouseTipStyle)aStyle
{
    [mouseTipInstance setStyle:aStyle];
}

+ (NSDictionary *)textAttributesForCurrentStyle;
{
    return [mouseTipInstance textAttributes];
}

+ (void)setLevel:(int)windowLevel
{
    [mouseTipInstance setLevel:windowLevel];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OBASSERT_NOT_REACHED("Should be using the class methods and be unable to copy.");
    return [self retain];
}

@end

@implementation OAMouseTipWindow (Private)

- (void)setStyle:(OAMouseTipStyle)aStyle;
{
    currentStyle = aStyle;
    [mouseTipView setStyle:aStyle];
    [self setHasShadow:(currentStyle != MouseTip_DockStyle)]; // DockStyle's shadow is handled by the text view
}

- (void)_preferenceChanged:(NSNotification *)note
{
    if (![enablingPreference boolValue])
        [self _reallyOrderOutIfOwnerUnchanged:nil];
}

- (NSDictionary *)textAttributes
{
    return [mouseTipView textAttributes];
}

- (void)showMouseTipWithAttributedTitle:(NSAttributedString *)aTitle
                            springPoint:(NSPoint)fromPoint
                                hotSpot:(NSPoint)hotSpot
                               maxWidth:(float)maxWidth
                                  delay:(float)delay;
{
    NSRect rect;

    if (waitTimer != nil) {
        [waitTimer invalidate];
        waitTimer = nil;
    } 
    
    if (!hasRegisteredForNotification) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appHide:) name:NSApplicationWillHideNotification object:nil];
        hasRegisteredForNotification = YES;
    }
    
    NSScreen *targetScreen = [[self class] _screenUnderPoint:fromPoint];
    
    NSSize toolTipMaxSize = { .width = maxWidth? maxWidth : FLT_MAX, .height = FLT_MAX };
    if (targetScreen) {
        NSRect targetScreenRect = [targetScreen visibleFrame];
        toolTipMaxSize.width = MIN(toolTipMaxSize.width, targetScreenRect.size.width);
        toolTipMaxSize.height = MIN(toolTipMaxSize.height, targetScreenRect.size.height);
    }
    [mouseTipView setMaxSize:toolTipMaxSize];
    
    [mouseTipView setAttributedTitle:aTitle];
    rect.origin = fromPoint;
    rect.size = [mouseTipView sizeOfText];
    if (maxWidth > 0 && rect.size.width > maxWidth)
        rect.size.width = maxWidth;
    
    rect = NSIntegralRect(rect);    // <bug://bugs/35708> (dimensions tooltip will grow continuously if the screen is zoomed) - make sure that the rect has no fractional parts for the following comparison
    if ([self isVisible]) {
        // If we're updating a visible tooltip with a new title it can be very jittery to have it resize a lot.  It may have to grow, but it doesn't have to shrink.
        rect.size.width = MAX(rect.size.width, [self frame].size.width);
        rect.size.height = MAX(rect.size.height, [self frame].size.height);
    }
    
    rect.origin.x -= hotSpot.x * rect.size.width;
    rect.origin.y -= hotSpot.y * rect.size.height;
    // rect = NSIntegralRect(NSInsetRect(rect, -TEXT_X_INSET, -TEXT_Y_INSET));
    rect = NSIntegralRect(rect);
    rect = [[self class] _adjustRect:rect toFitScreen:targetScreen];
    
    [self setFrame:rect display:YES animate:NO];
    if (![self isVisible]) {
        if (delay > 0.0) {
            waitTimer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(_timerFired) userInfo:nil repeats:NO];
        } else {
            [self orderFront:self];
            // [self setLevel:NSScreenSaverWindowLevel - 1];
        }
    }  
}

- (void)_timerFired;
{
    //    NSLog(@"timer fired: %@", nonretainedOwner);
    waitTimer = nil;
    [mouseTipInstance orderFront:self];
    // [mouseTipInstance setLevel:NSScreenSaverWindowLevel - 1];
}

- (void)_reallyOrderOutIfOwnerUnchanged:(NSTimer *)timer;
{
    waitTimer = nil;
    
    if ([timer userInfo] != nil && [[timer userInfo] nonretainedObjectValue] != nonretainedOwner)
        return;
    
    float startAlpha = [mouseTipInstance alphaValue];
    NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
    
    // Fade the tooltip out.  TODO: It might be better to move this to a timer so that the event loop can still run while we're fading out.  This would make the client app more responsive, and it would also allow the user to change her mind and show the tooltip again while it is fading out.
    while (1) {
        NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval delta = (currentTime - startTime) / FADE_OUT_INTERVAL;
        float alpha = startAlpha - delta * startAlpha;
        
        [mouseTipInstance setAlphaValue:alpha];
        [mouseTipInstance displayIfNeeded];
        if (delta >= 1.0)
            break;
    }
    
    [mouseTipInstance orderOut:self];
    [mouseTipInstance setAlphaValue:startAlpha];
    nonretainedOwner = nil;
}

- (void)_hideAfterDelay:(float)delay
{
    if (waitTimer != nil) {
        [waitTimer invalidate];
        waitTimer = nil;
    }
    
    if (delay > 0 && [self isVisible]) {
        waitTimer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(_reallyOrderOutIfOwnerUnchanged:) userInfo:[NSValue valueWithNonretainedObject:nonretainedOwner] repeats:NO]; 
    } else {
        [mouseTipInstance orderOut:self];
        nonretainedOwner = nil;
    }
}

@end
