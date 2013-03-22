// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAOpaqueTextField.h>
#import <OmniAppKit/NSView-OAExtensions.h>
#import <OmniAppKit/OAVersion.h>

RCS_ID("$Id$")

#if 0 && defined(DEBUG)
#define DEBUG_OPAQUE_TEXT_FIELD 1
#define LOG_OPAQUE_TEXT_FIELD(...) NSLog(__VA_ARGS__)
#else
#define LOG_OPAQUE_TEXT_FIELD(...)
#endif

extern bool CGFontDefaultGetSmoothingStyle();

static NSString *const OAOpaqueTextFieldAncestorWillDrawNotification = @"com.omnigroup.OAOpaqueTextFieldAncestorWillDraw"; // the object of this notification is the WINDOW, not the VIEW (for fast culling). The actual root drawing view is stored in a static variable:
static NSView *DrawingRootView;

@implementation OAOpaqueTextField

static void (*original_drawRect)(id self, SEL _cmd, NSRect dirtyRect);
static void (*original_drawLayer_inContext)(id self, SEL _cmd, CALayer *layer, CGContextRef ctx);

+ (void)performPosing;
{
    original_drawRect = (typeof(original_drawRect))OBReplaceMethodImplementationWithSelector(self, @selector(drawRect:), @selector(_OAOpaqueTextField_drawRect:));
    original_drawLayer_inContext = (typeof(original_drawLayer_inContext))OBReplaceMethodImplementationWithSelector(self, @selector(drawLayer:inContext:), @selector(_OAOpaqueTextField_drawLayer:inContext:));
}

static void DrawAncestorsOfView(NSView *descendantView, NSRect clipRect)
{
    // Build a stack of ancestor views so that we can draw them all into our backing store.
    // Note: skipping the descendantView because it's the one asking us to draw!
    NSMutableArray *ancestorViews = [[NSMutableArray alloc] init];
    NSView *superview = descendantView;
    while ((superview = superview.superview)) {
        [ancestorViews addObject:superview];
        if (superview.isOpaque)
            break;
    }
    
    OBASSERT(superview.isOpaque, "Failed to find opaque superview!");
    
    void *grafPort = [[NSGraphicsContext currentContext] graphicsPort];
    
#if DEBUG_OPAQUE_TEXT_FIELD
    CGFloat red = 1.0;
#endif
    
    for (NSView *ancestor in [ancestorViews reverseObjectEnumerator]) {
        [NSGraphicsContext saveGraphicsState];
        
        BOOL isFlipped = [ancestor isFlipped];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:grafPort flipped:isFlipped]];
        
        NSAffineTransform *xform = [[NSAffineTransform alloc] init];
        [xform setTransformStruct:[ancestor transformToView:descendantView]];
        [xform concat];
        
        NSRect ancestorClipRect = [ancestor convertRect:clipRect fromView:descendantView];
        if ([ancestor wantsDefaultClipping])
            [NSBezierPath clipRect:ancestorClipRect];
        [ancestor drawRect:ancestorClipRect];
        
#if DEBUG_OPAQUE_TEXT_FIELD
        [[NSColor colorWithDeviceRed:red green:0 blue:0 alpha:1] setFill];
        NSRectFill(ancestorClipRect);
        red -= 0.1;
        if (red < 0)
            red = 1.0f;
#endif
        
        [xform release];
        [NSGraphicsContext restoreGraphicsState];
    }
    
    [ancestorViews release];
}

- (void)_OAOpaqueTextField_drawRect:(NSRect)dirtyRect;
{
    [NSGraphicsContext saveGraphicsState];
    
    if (isDrawingToLayer) {
        DrawAncestorsOfView(self, dirtyRect);
    
        // If LCD font smoothing is disabled in System Preferences, CGContextSetShouldSmoothFonts is ignored. So we can unconditionally set it to true here (since we're drawing opaquely) and the framework will respect the user's wishes.
        CGContextSetShouldSmoothFonts((CGContextRef)[[NSGraphicsContext currentContext] graphicsPort], true);
    }
    
    original_drawRect(self, _cmd, dirtyRect);
    
    [NSGraphicsContext restoreGraphicsState];
}

- (void)_OAOpaqueTextField_drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx;
{
    @try {
        isDrawingToLayer = YES;
        original_drawLayer_inContext(self, _cmd, layer, ctx);
    } @finally {
        isDrawingToLayer = NO;
    }
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow;
{
    [super viewWillMoveToWindow:newWindow];
    
    if (drawingObserver)
        [[NSNotificationCenter defaultCenter] removeObserver:drawingObserver];
}

- (void)viewDidMoveToWindow;
{
    [super viewDidMoveToWindow];
    
    NSWindow *window = self.window;
    if (window) {
        drawingObserver = [[NSNotificationCenter defaultCenter] addObserverForName:OAOpaqueTextFieldAncestorWillDrawNotification object:window queue:nil usingBlock:^(NSNotification *note){
            if ([self isDescendantOf:DrawingRootView])
                [self setNeedsDisplay:YES];
        }];
    }
}

@end

@implementation NSView (OAOpaqueTextFieldDescendants)

static void (*original_viewWillDraw)(id self, SEL _cmd);

+ (void)performPosing;
{
    original_viewWillDraw = (typeof(original_viewWillDraw))OBReplaceMethodImplementationWithSelector(self, @selector(viewWillDraw), @selector(_OAOpaqueTextFieldDescendants_viewWillDraw));
}

- (void)_OAOpaqueTextFieldDescendants_viewWillDraw;
{
    OBPRECONDITION([NSThread isMainThread]); // AppKit release notes guarantee this; saves us from having to use TLS
    
    BOOL didSetRootView = NO;
    
    if (!DrawingRootView) {
        LOG_OPAQUE_TEXT_FIELD(@"+++ Begin updating at root view %@", OBShortObjectDescription(self));
        
        DrawingRootView = self;
        didSetRootView = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:OAOpaqueTextFieldAncestorWillDrawNotification object:self.window];
    }
    
    original_viewWillDraw(self, _cmd);
    
    if (didSetRootView) {
        DrawingRootView = nil;
        LOG_OPAQUE_TEXT_FIELD(@"+++ Done updating at root view %@", OBShortObjectDescription(self));
    }
}

@end
