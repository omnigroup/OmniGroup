// Copyright 2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAResizingTitleBarButton.h>

RCS_ID("$Id$");

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#if 0 && defined(DEBUG)
    #define DEBUG_TITLE_BAR_BUTTON_ENABLED 1
    #define DEBUG_TITLE_BAR_BUTTON(format, ...) NSLog(@"TITLE_BAR_BUTTON %p: " format, self, ## __VA_ARGS__)
#else
    #define DEBUG_TITLE_BAR_BUTTON_ENABLED 0
    #define DEBUG_TITLE_BAR_BUTTON(format, ...)
#endif

#define OA_BUTTON_SPACER 3
#define OA_BUTTON_TEXT_CUSHION 20
#define OA_BUTTON_VERTICAL_OFFSET (-4)
#define OA_BUTTON_HEIGHT 18.0f

@interface OAResizingTitleBarButton (/* private */)
@property (nonatomic,copy) OATitleBarButtonTextForButtonCallback callback; // must not retain host window, see titleBarButtonWithKey:forWindow:textCallback:
@end

static NSFont *_OAButtonTitleFont(void)
{
    return [NSFont boldSystemFontOfSize:11];
}

static NSView *_OABorderView(NSWindow *window)
{
    return [[window standardWindowButton:NSWindowCloseButton] superview];
}

static CGFloat _OAMinButtonX(NSWindow *window, NSView *borderView)
{
    OBPRECONDITION(borderView != nil);
    
    CGFloat maxTitleX = 0;
    NSButton *windowButton = nil;
    if ((windowButton = [window standardWindowButton:NSWindowDocumentVersionsButton])) {
        maxTitleX = NSMaxX([windowButton frame]);
    } else {
        CGFloat titleWidth = [NSWindow minFrameWidthWithTitle:[window title] styleMask:[window styleMask]];
        // try calculating the width that the title, document icon and versions button takes up
        if ((windowButton = [window standardWindowButton:NSWindowCloseButton]))
            titleWidth -= NSWidth([windowButton frame]);
        if ((windowButton = [window standardWindowButton:NSWindowMiniaturizeButton]))
            titleWidth -= NSWidth([windowButton frame]);
        if ((windowButton = [window standardWindowButton:NSWindowZoomButton]))
            titleWidth -= NSWidth([windowButton frame]);
        if ((windowButton = [window standardWindowButton:NSWindowToolbarButton]))
            titleWidth -= NSWidth([windowButton frame]);
        if ((windowButton = [window standardWindowButton:NSWindowFullScreenButton]))
            titleWidth -= NSWidth([windowButton frame]);
        
        maxTitleX = NSMidX([borderView frame]) + titleWidth/2;
    }
    
    return maxTitleX + OA_BUTTON_SPACER;
}

static CGFloat _OAMaxButtonX(NSWindow *window, NSView *borderView)
{
    OBPRECONDITION(borderView != nil);
    
    CGFloat minTopRightCornerX = 0.0f;
    NSButton *buttonInTopRightCorner = [window standardWindowButton:NSWindowToolbarButton];
    if (buttonInTopRightCorner == nil) {
        buttonInTopRightCorner = [window standardWindowButton:NSWindowFullScreenButton];
    }
    
    if (buttonInTopRightCorner != nil) {
        minTopRightCornerX = NSMinX(buttonInTopRightCorner.frame);
    } else {
        // no button
        NSRect borderBounds = [borderView bounds];
        minTopRightCornerX = NSMaxX(borderBounds);
    }
    
    return minTopRightCornerX - OA_BUTTON_SPACER;
}

static CGFloat _OAWidthAvailableForButtonText(NSWindow * window)
{
    NSView *borderView = _OABorderView(window);
    if (borderView == nil)
        return 0.0f;
    
    return _OAMaxButtonX(window, borderView) - _OAMinButtonX(window, borderView) - OA_BUTTON_TEXT_CUSHION;
}

@implementation OAResizingTitleBarButton
{
    BOOL _isObservingWindowTitle;
}

// The window will retain the returned instance using an associated object. The returned instance will retain the callback. To avoid retain cycles, the callback must not retain the window. If called again with the same key-window pair, the existing button will be assigned a new callback block and will be updated in place.
+ (instancetype)titleBarButtonWithKey:(const void *)key forWindow:(NSWindow *)window textCallback:(OATitleBarButtonTextForButtonCallback)callback;
{
    OBPRECONDITION(key != NULL);
    OBPRECONDITION(window != nil);
    OBPRECONDITION(callback != NULL);

    NSView *borderView = _OABorderView(window);
    if (borderView == nil) {
        // Couldn't find expected border view. If the window has a title bar button associated with this key, hide it.
        [OAResizingTitleBarButton hideTitleBarButtonWithKey:key forWindow:window];
        return nil;
    }
    
    // N.B. We use associated objects (as opposed to an expected tag) because of our usage of NSWindowCloseButton's superview as the containing view for the title bar button. See _OABorderView.
    // When/after transitioning to full screen, NSWindowCloseButton's superview won't find the button by tag and at the time of this writing would be stuffed into an NSThemeFrame and appear over the content per <bug:///84608> (Trial information looks like it's part of a task when in full screen mode)
    OAResizingTitleBarButton *button = objc_getAssociatedObject(window, key);
    if (button == nil) {
        button = [[[OAResizingTitleBarButton alloc] initWithFrame:NSZeroRect window:window textCallback:callback] autorelease];
        if (button == nil)
            return nil;
        objc_setAssociatedObject(window, key, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [borderView addSubview:button positioned:NSWindowAbove relativeTo:nil];
    } else {
        button.callback = callback;
    }
    
    [button _updateTitleBarButtonFrame];
    return button;
}

+ (void)hideTitleBarButtonWithKey:(const void *)key forWindow:(NSWindow *)window;
{
    OAResizingTitleBarButton *button = objc_getAssociatedObject(window, key);
    [button setHidden:YES];
}

#pragma mark - Init and Dealloc

- (id)init;
{
    OBRejectInvalidCall(self, _cmd, @"Use factory method or private initializer");
}

- (id)initWithFrame:(NSRect)frameRect;
{
    OBRejectInvalidCall(self, _cmd, @"Use factory method or private initializer");
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    OBRejectInvalidCall(self, _cmd, @"Use factory method or private initializer");
}

static BOOL _OAValidMobileTitleBarButton(NSButton *button)
{
    return button != nil && button.postsFrameChangedNotifications;
}

static NSButton *_OAMobileTitleBarButton(NSWindow *window)
{
    // First try the version button, since it's there for untitled documents
    NSButton *versionsButton = [window standardWindowButton:NSWindowDocumentVersionsButton];
    if (_OAValidMobileTitleBarButton(versionsButton))
        return versionsButton;
    
    // Versions disabled? Try the document proxy icon
    NSButton *documentProxyIcon = [window standardWindowButton:NSWindowDocumentIconButton];
    if (_OAValidMobileTitleBarButton(documentProxyIcon))
        return documentProxyIcon;
    
    return nil;
}

static void *OAResizingTitleBarButtonObservingWindowContext;

- (id)initWithFrame:(NSRect)frameRect window:(NSWindow *)window textCallback:(OATitleBarButtonTextForButtonCallback)callback;
{
    OBPRECONDITION(window != nil);
    OBPRECONDITION(callback != NULL);
    
    self = [super initWithFrame:frameRect];
    if (self == nil)
        return nil;
    
    // Must not retain window.
    _callback = [callback copy];

    [self setBezelStyle:NSRecessedBezelStyle];
    [self setShowsBorderOnlyWhileMouseInside:YES];
    [self setAutoresizingMask:NSViewMinYMargin|NSViewMinXMargin];

    DEBUG_TITLE_BAR_BUTTON(@"Created");

    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &OAResizingTitleBarButtonObservingWindowContext) {
        OBASSERT([object isKindOfClass:[NSWindow class]]);
        [self _updateTitleBarButtonFrame];
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)dealloc
{
    OBPRECONDITION(!_isObservingWindowTitle); // We should have been removed from our window and stopped observing already
    
    DEBUG_TITLE_BAR_BUTTON(@"Deallocating");

    self.callback = NULL;
    
    [super dealloc];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:nil];
    
    if (_isObservingWindowTitle) {
        [self.window removeObserver:self forKeyPath:@"title" context:&OAResizingTitleBarButtonObservingWindowContext];
        _isObservingWindowTitle = NO;
    }
    DEBUG_TITLE_BAR_BUTTON(@"Unsubscribed to frame changes");
}

- (void)viewDidMoveToWindow;
{
    NSWindow *window = self.window;
    
    if (!window)
        return;
    
    NSButton *mobileTitleBarButton = _OAMobileTitleBarButton(window);
    if (mobileTitleBarButton != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_titleBarDidChange:) name:NSViewFrameDidChangeNotification object:mobileTitleBarButton];
        DEBUG_TITLE_BAR_BUTTON(@"Subscribed to frame changes mobileTitleBarButton %@", OBShortObjectDescription(mobileTitleBarButton));
        _isObservingWindowTitle = NO;
    } else {
        NSView *borderView = _OABorderView(window);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_titleBarDidChange:) name:NSViewFrameDidChangeNotification object:borderView];
        [window addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:&OAResizingTitleBarButtonObservingWindowContext];
        DEBUG_TITLE_BAR_BUTTON(@"Subscribed to frame changes borderView %@", OBShortObjectDescription(borderView));
        _isObservingWindowTitle = YES;
    }
}

#if DEBUG_TITLE_BAR_BUTTON_ENABLED
- (void)viewWillMoveToSuperview:(NSView *)newSuperview;
{
    DEBUG_TITLE_BAR_BUTTON(@"Will move to superview %@", OBShortObjectDescription(newSuperview));
    [super viewWillMoveToSuperview:newSuperview];
}
- (void)viewDidMoveToSuperview;
{
    [super viewDidMoveToSuperview];
    DEBUG_TITLE_BAR_BUTTON(@"Did move to superview");
}
#endif

#pragma mark Public API

// utility method for use by callback blocks to determine the width of a putative button title
- (CGFloat)widthForText:(NSString *)text;
{
    NSDictionary *attributes = @{NSFontAttributeName:_OAButtonTitleFont()};
    CGFloat textWidth = [text sizeWithAttributes:attributes].width;
    return textWidth;
}

#pragma mark Private API

- (void)_titleBarDidChange:(NSNotification *)notification;
{
    NSView *view = notification.object;
    OBASSERT([view isKindOfClass:[NSView class]]);
    if ( ! [view isKindOfClass:[NSView class]])
        return; // shouldn't happen, but better safe than sorry
    
    NSWindow *window = view.window;
    DEBUG_TITLE_BAR_BUTTON(@"Got notification from view: %@ window: %@ button: %@", [view shortDescription], window, [self shortDescription]);
    if (window == nil) {
        // the versions button is temporarily removed from the window when duplicating a document, we'll get notified again when it's done
        return;
    }
    
    OBASSERT([window isKindOfClass:[NSWindow class]]);
    if ( ! [window isKindOfClass:[NSWindow class]])
        return; // shouldn't happen, but better safe than sorry
    
    // <bug:///97746> (Assertions when opening and closing windows quickly)
    // It's possible the view whose frame we're observing has been deallocated, and a view in another window has taken its place
    if (window != self.window)
        return;
    
    [self _updateTitleBarButtonFrame];
}

- (void)_updateTitleBarButtonFrame;
{
    DEBUG_TITLE_BAR_BUTTON(@"Updating button %@", [self shortDescription]);

    OBPRECONDITION(self.callback != NULL);
    
    if (self.callback == NULL) {
        OBASSERT_NOT_REACHED("Expected to have callback function but did not. Bailing without updating.");
        return;
    }
    
    NSWindow *window = self.window;
    
    BOOL shouldHideButton = ([window styleMask] & NSFullScreenWindowMask) ? YES : NO;
    if (shouldHideButton && self.isHidden) {
        // no need to do any more work
        return;
    }
    
    NSColor *textColor = nil;
    NSString *text = self.callback(self, _OAWidthAvailableForButtonText(window), &textColor);
    if (text == nil) {
        [self setHidden:YES];
        return;
    }

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    [paragraphStyle setAlignment:NSCenterTextAlignment];
    NSDictionary *attributes = @{NSFontAttributeName:_OAButtonTitleFont(), NSForegroundColorAttributeName:textColor, NSParagraphStyleAttributeName:paragraphStyle};
    [paragraphStyle release];
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    self.attributedTitle = attributedString;
    [attributedString release];
    
    CGFloat textWidth = [text sizeWithAttributes:attributes].width;
    CGFloat width = textWidth + OA_BUTTON_TEXT_CUSHION; // button needs more cushion for the whole text to be drawn

    NSView *borderView = _OABorderView(window);
    NSRect borderBounds = [borderView bounds];
    const float height = OA_BUTTON_HEIGHT;
    
    CGFloat originX = _OAMaxButtonX(window, borderView) - width;
    CGFloat originY = NSMaxY(borderBounds) - height + OA_BUTTON_VERTICAL_OFFSET;
    NSRect frame = NSMakeRect(originX, originY, width, height);
    if (! NSEqualRects(frame, self.frame))
        self.frame = frame;
    
    shouldHideButton |= textWidth > _OAWidthAvailableForButtonText(window);
    [self setHidden:shouldHideButton];
}

@end
