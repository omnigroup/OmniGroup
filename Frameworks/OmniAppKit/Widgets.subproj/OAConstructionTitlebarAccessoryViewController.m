// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAConstructionTitlebarAccessoryViewController.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>
#import <OmniAppKit/NSColor-OAExtensions.h>

RCS_ID("$Id$");

static void * _OAConstructionTimeViewTabbedWindowsObservationContext = &_OAConstructionTimeViewTabbedWindowsObservationContext;

@interface _OAConstructionTimeView : NSView

@property (nonatomic, readonly) BOOL wantsBorder;

@end

#pragma mark -

#define CONSTRUCTION_WARNING_HEIGHT (14)

@implementation _OAConstructionTimeView

- (id)initWithFrame:(NSRect)frameRect;
{
    self = [super initWithFrame:frameRect];
    if (self == nil) {
        return nil;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_OAConstructionTimeView_windowDidBecomeMain:) name:NSWindowDidBecomeMainNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_OAConstructionTimeView_windowDidResignMain:) name:NSWindowDidResignMainNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_OAConstructionTimeView_windowWillClose:) name:NSWindowWillCloseNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_OAConstructionTimeView_menuDidSendAction:) name:NSMenuDidSendActionNotification object:nil];

    return self;
}

- (BOOL)isOpaque;
{
    return NO;
}

- (void)drawRect:(NSRect)rect;
{
    NSRect bounds = [self bounds];
    
    [OARGBA(1.0, 0.0, 1.0, 0.5) set];
    
    const CGFloat stripeWidth = 10.0f;
    CGFloat height = bounds.size.height;
    
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(ctx);
    {
	CGContextSetBlendMode(ctx, kCGBlendModeDarken);
	CGContextSetAlpha(ctx, 0.075f);
	CGContextBeginTransparencyLayer(ctx, NULL);
	{
	    [[NSColor blackColor] setFill];
	    NSRectFill(bounds);
	    
	    CGPoint p = CGPointMake(bounds.origin.x - bounds.size.height, bounds.origin.y); // start far enough to the left that we'll cover the title area
	    
	    [[NSColor yellowColor] setFill];
	    while (p.x <= NSMaxX(bounds)) {
		CGContextMoveToPoint(ctx, p.x, p.y);
		CGContextAddLineToPoint(ctx, p.x + height, p.y + height);
		CGContextAddLineToPoint(ctx, p.x + height + stripeWidth, p.y + height);
		CGContextAddLineToPoint(ctx, p.x + stripeWidth, p.y);
		CGContextClosePath(ctx);
		p.x += 2*stripeWidth;
	    }
	    CGContextFillPath(ctx);
	}
	CGContextEndTransparencyLayer(ctx);
        
        if (self.wantsBorder) {
            NSRect border, remainder;
            NSDivideRect(bounds, &border, &remainder, 1.0f, NSRectEdgeMaxY);

            CGContextSetBlendMode(ctx, kCGBlendModeNormal);
            CGContextSetAlpha(ctx, 1.0f);
            
            [[NSColor colorWithWhite:0.0f alpha:0.115f] setFill];
            NSRectFill(border);
        }
    }
    CGContextRestoreGState(ctx);
}

- (NSView *)hitTest:(NSPoint)aPoint;
{
    return nil;
}

- (CGSize)intrinsicContentSize;
{
    return CGSizeMake(NSViewNoIntrinsicMetric, CONSTRUCTION_WARNING_HEIGHT);
}

- (BOOL)wantsBorder;
{
    if (![NSWindow instancesRespondToSelector:@selector(tabbedWindows)]) {
        return NO;
    }
    
    return (self.window.tabbedWindows != nil);
}

- (void)viewDidMoveToWindow;
{
    [super viewDidMoveToWindow];
    [self _setNeedsUpdateWantsBorder];
}

- (void)_OAConstructionTimeView_windowDidBecomeMain:(NSNotification *)notification;
{
    [self _setNeedsUpdateWantsBorder];
}

- (void)_OAConstructionTimeView_windowDidResignMain:(NSNotification *)notification;
{
    [self _setNeedsUpdateWantsBorder];
}

- (void)_OAConstructionTimeView_windowWillClose:(NSNotification *)notification;
{
    if (notification.object != self.window) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self _setNeedsUpdateWantsBorder];
        }];
    }
}

- (void)_OAConstructionTimeView_menuDidSendAction:(NSNotification *)notification;
{
    NSMenuItem *menuItem = OB_CHECKED_CAST(NSMenuItem, notification.userInfo[@"MenuItem"]);
    if (menuItem.action == @selector(toggleTabBar:)) {
        [self _setNeedsUpdateWantsBorder];
    }
}

- (void)_setNeedsUpdateWantsBorder;
{
    // We want to draw a border on top of ourselves if there is a tab bar in the window.
    // Really, we want a border on the top and or bottom depending upon neighboring titlebar accessory view controllers, but the tab test is simpler for now and covers nearly all the use cases.
    //
    // tabbedWindows is not KVO compliant, we we watch for main resignation and window closes to refresh our wantsBorder flag.
    // We don't actually recalculate this until draw time, because we become main before tabbedWindows is updated in the new tab case.

    [self setNeedsDisplay:YES];
}

@end

@implementation OAConstructionTitlebarAccessoryViewController

- (void)loadView;
{
    self.view = [[_OAConstructionTimeView alloc] initWithFrame:CGRectMake(0, 0, 1, CONSTRUCTION_WARNING_HEIGHT)];
    self.layoutAttribute = NSLayoutAttributeBottom;
    self.fullScreenMinHeight = CONSTRUCTION_WARNING_HEIGHT;
}

@end
