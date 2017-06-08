// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSWindow-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>
#import <OmniAppKit/OAViewPicker.h>

#import "OAConstructionTitlebarAccessoryViewController.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@interface NSView (DebuggingSPI)
- (NSString *)_subtreeDescription;
@end

static void (*oldBecomeKeyWindow)(id self, SEL _cmd);
static void (*oldResignKeyWindow)(id self, SEL _cmd);
static void (*oldMakeKeyAndOrderFront)(id self, SEL _cmd, id sender);
static void (*oldDidChangeValueForKey)(id self, SEL _cmd, NSString *key);
static void (*oldSetFrameDisplayAnimateIMP)(id self, SEL _cmd, NSRect newFrame, BOOL shouldDisplay, BOOL shouldAnimate);
static void (*oldDisplayIfNeededIMP)(id, SEL) = NULL;
static NSWindow * _Nullable becomingKeyWindow = nil;

@implementation NSWindow (OAExtensions)

OBPerformPosing(^{
    Class self = objc_getClass("NSWindow");
    oldBecomeKeyWindow = (void *)OBReplaceMethodImplementationWithSelector(self, @selector(becomeKeyWindow), @selector(replacement_becomeKeyWindow));
    oldResignKeyWindow = (void *)OBReplaceMethodImplementationWithSelector(self, @selector(resignKeyWindow), @selector(replacement_resignKeyWindow));
    oldMakeKeyAndOrderFront = (void *)OBReplaceMethodImplementationWithSelector(self, @selector(makeKeyAndOrderFront:), @selector(replacement_makeKeyAndOrderFront:));
    oldDidChangeValueForKey = (void *)OBReplaceMethodImplementationWithSelector(self, @selector(didChangeValueForKey:), @selector(replacement_didChangeValueForKey:));
    oldSetFrameDisplayAnimateIMP = (typeof(oldSetFrameDisplayAnimateIMP))OBReplaceMethodImplementationWithSelector(self, @selector(setFrame:display:animate:), @selector(replacement_setFrame:display:animate:));    
    oldDisplayIfNeededIMP = (typeof(oldDisplayIfNeededIMP))OBReplaceMethodImplementationWithSelector(self, @selector(displayIfNeeded), @selector(_OA_replacement_displayIfNeeded));
});

static NSMutableArray * _Nullable zOrder;

- (nullable id)_addToZOrderArray;
{
    [zOrder addObject:self];
    return nil;
}

+ (BOOL)hasTabbedWindowSupport;
{
    static BOOL _hasTabbedWindowSupport;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _hasTabbedWindowSupport = [NSWindow instancesRespondToSelector:@selector(tabbedWindows)];
    });
    
    return _hasTabbedWindowSupport;
}


// Note that this will not return miniaturized windows (or any other ordered out window)
+ (NSArray *)windowsInZOrder;
{
    zOrder = [[NSMutableArray alloc] init];
    [[NSApplication sharedApplication] makeWindowsPerform:@selector(_addToZOrderArray) inOrder:YES];
    NSArray *result = zOrder;
    zOrder = nil;
    return result;
}

static NSLock *displayIfNeededBlocksLock = nil;
static NSMapTable *displayIfNeededBlocks = nil;
static BOOL displayIfNeededBlocksInProgress = NO;

+ (void)window:(nullable NSWindow *)window beforeDisplayIfNeededPerformBlock:(void (^)(void))block;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        displayIfNeededBlocks = [NSMapTable weakToStrongObjectsMapTable];
        displayIfNeededBlocksLock = [[NSLock alloc] init];
    });

    void (^copiedBlock)(void) = [block copy];
    [displayIfNeededBlocksLock lock];
    
    id key = window ?: [NSNull null];
    NSMutableArray *perWindowBlocks = [displayIfNeededBlocks objectForKey:key];
    BOOL needsQueue = !displayIfNeededBlocksInProgress && perWindowBlocks.count == 0;

    if (perWindowBlocks == nil) {
        perWindowBlocks = [NSMutableArray array];
        [displayIfNeededBlocks setObject:perWindowBlocks forKey:key];
    }
    [perWindowBlocks addObject:copiedBlock];
    
    [displayIfNeededBlocksLock unlock];

    if (needsQueue) {
        if (window != nil) {
            [window queueSelector:@selector(performDisplayIfNeededBlocks)];
        } else {
            [self queueSelector:@selector(performDisplayIfNeededBlocks)];
        }
    }
}

+ (BOOL)isPerformingDisplayIfNeededBlocks;
{
    return displayIfNeededBlocksInProgress;
}

+ (void)beforeAnyDisplayIfNeededPerformBlock:(void (^)(void))block;
{
    [self window:nil beforeDisplayIfNeededPerformBlock:block];
}

- (void)beforeDisplayIfNeededPerformBlock:(void (^)(void))block;
{
    [NSWindow window:self beforeDisplayIfNeededPerformBlock:block];
}

#ifdef DEBUG_kc0
#define TIME_PERFORM_DISPLAY_IF_NEEDED 1
#endif

+ (void)performDisplayIfNeededBlocks;
{
    [self performDisplayIfNeededBlocksForWindow:nil];
}

- (void)performDisplayIfNeededBlocks;
{
    // Perform all the display if needed blocks registered for us, then all registered for any window
    
    [NSWindow performDisplayIfNeededBlocksForWindow:self];
    [NSWindow performDisplayIfNeededBlocksForWindow:nil];
}

+ (void)performDisplayIfNeededBlocksForWindow:(nullable NSWindow *)window;
{
    // Make sure we are executing these blocks only on the main thread
    OBPRECONDITION([NSThread isMainThread]);
    if (![NSThread isMainThread]) {
        return;
    }
    
    [displayIfNeededBlocksLock lock];

    id key = window ?: [NSNull null];
    NSMutableArray *perWindowBlocks = [displayIfNeededBlocks objectForKey:key];
    
    if (perWindowBlocks.count != 0) {
#if TIME_PERFORM_DISPLAY_IF_NEEDED
        NSLog(@"-[%@ %@]: begin", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
#endif
        displayIfNeededBlocksInProgress = YES;
        
        while (perWindowBlocks.count != 0) {
            NSArray *queuedBlocks = [perWindowBlocks copy];
            [perWindowBlocks removeAllObjects];
            [displayIfNeededBlocksLock unlock];
            
            for (void (^block)(void) in queuedBlocks) {
                block();
            }
            
            [displayIfNeededBlocksLock lock];
        }
        
        displayIfNeededBlocksInProgress = NO;
#if TIME_PERFORM_DISPLAY_IF_NEEDED
        NSLog(@"-[%@ %@]: end", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
#endif
    }
    [displayIfNeededBlocksLock unlock];
}

- (NSPoint)frameTopLeftPoint;
{
    NSRect windowFrame;

    windowFrame = [self frame];
    return NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame));
}

- (void)_sendWindowDidChangeKeyOrFirstResponder;
{
    NSView *rootView = [self contentView];
    NSView *superview;
    
    while ((superview = [rootView superview]))
           rootView = superview;
    
    [rootView windowDidChangeKeyOrFirstResponder];
}

- (void)replacement_becomeKeyWindow;
{
    oldBecomeKeyWindow(self, _cmd);
    [self _sendWindowDidChangeKeyOrFirstResponder];
}

- (void)replacement_resignKeyWindow;
{
    oldResignKeyWindow(self, _cmd);
    [self _sendWindowDidChangeKeyOrFirstResponder];
}

/*" We occasionally want to draw differently based on whether we are in the key window or not (for example, OAAquaButton).  This method allows us to draw correctly the first time we get drawn, when the window is coming on screen due to -makeKeyAndOrderFront:.  The window is not key at that point, but we would like to draw as if it is so that we don't have to redraw later, wasting time and introducing flicker. "*/

- (void)replacement_makeKeyAndOrderFront:(id)sender;
{
    becomingKeyWindow = self;
    oldMakeKeyAndOrderFront(self, _cmd, sender);
    becomingKeyWindow = nil;
}

- (void)replacement_didChangeValueForKey:(NSString *)key;
{
    oldDidChangeValueForKey(self, _cmd, key);
    
    if ([key isEqualToString:@"firstResponder"])
        [self _sendWindowDidChangeKeyOrFirstResponder];
}

/*" There is an elusive crasher (at least in 10.2.x) related to animated frame changes that we believe happens only when the new and old frames are very close in position and size. This method disables the animation if the frame change is below a certain threshold, in an attempt to work around the crasher. "*/
- (void)replacement_setFrame:(NSRect)newFrame display:(BOOL)shouldDisplay animate:(BOOL)shouldAnimate;
{
    NSRect currentFrame = [self frame];

    // Calling this with equal rects prevents any display from actually happening.
    if (NSEqualRects(currentFrame, newFrame))
        return;

    // Don't bother animating if we're not visible
    if (shouldAnimate && ![self isVisible])
        shouldAnimate = NO;

#ifdef OMNI_ASSERTIONS_ON
    // The AppKit method is synchronous, but it can cause timers, etc, to happen that may cause other app code to try to start animating another window (or even the SAME one).  This leads to crashes when AppKit cleans up its animation timer.
    static NSMutableSet *animatingWindows = nil;
    if (!animatingWindows)
        animatingWindows = OFCreateNonOwnedPointerSet();
    OBASSERT([animatingWindows member:self] == nil);
    [animatingWindows addObject:self];
#endif
    
    oldSetFrameDisplayAnimateIMP(self, _cmd, newFrame, shouldDisplay, shouldAnimate);

#ifdef OMNI_ASSERTIONS_ON
    OBASSERT([animatingWindows member:self] == self);
    [animatingWindows removeObject:self];
#endif
}

- (void)_OA_replacement_displayIfNeeded;
{
    [self performDisplayIfNeededBlocks];
    oldDisplayIfNeededIMP(self, _cmd);
}

- (BOOL)isBecomingKey;
{
    return self == becomingKeyWindow;
}

- (BOOL)shouldDrawAsKey;
{
    return [self isKeyWindow];
}

- (void)addConstructionWarning;
{
    OAConstructionTitlebarAccessoryViewController *accessory = [[OAConstructionTitlebarAccessoryViewController alloc] init];
    [self insertTitlebarAccessoryViewController:accessory atIndex:0];
}

- (NSPoint)convertPointToScreen:(NSPoint)windowPoint;
{
    NSRect windowRect = (NSRect){.origin = windowPoint, .size = NSZeroSize};
    NSRect screenRect = [self convertRectToScreen:windowRect];
    return screenRect.origin;
}

- (NSPoint)convertPointFromScreen:(NSPoint)screenPoint;
{
    NSRect screenRect = (NSRect){.origin = screenPoint, .size = NSZeroSize};
    NSRect windowRect = [self convertRectFromScreen:screenRect];
    return windowRect.origin;
}

/*" Convert a point from a window's base coordinate system to the CoreGraphics global ("screen") coordinate system. "*/
- (CGPoint)convertBaseToCGScreen:(NSPoint)windowPoint;
{
    // This isn't documented anywhere (sigh...), but it's borne out by experimentation and by a posting to quartz-dev by Mike Paquette.
    // Cocoa and CG both use a single global coordinate system for "screen coordinates" (even in a multi-monitor setup), but they use slightly different ones.
    // Cocoa uses a coordinate system whose origin is at the lower-left of the "origin" or "zero" screen, with Y values increasing upwards; CG has its coordinate system at the upper-left of the "origin" screen, with +Y downwards.
    // The screen in question here is the screen containing the origin, which is not necessarily the same as +[NSScreen mainScreen] (documented to be the screen containing the key window). However, the CG main display (CGMainDisplayID()) is documented to be a display at the origin.
    // Coordinates continue across other screens according to how the screens are arranged logically.

    // We assume here that both Quartz and CG have the same idea about the height (Y-extent) of the main screen; we should check whether this holds in 10.5 with resolution-independent UI.
    
    NSPoint cocoaScreenCoordinates = [self convertPointToScreen:windowPoint];
    CGRect mainScreenSize = CGDisplayBounds(CGMainDisplayID());
    
    // It's the main screen, so we expect its origin to be at the global origin. If that's not true, our conversion will presumably fail...
    OBASSERT(mainScreenSize.origin.x == 0);
    OBASSERT(mainScreenSize.origin.y == 0);
    
    return CGPointMake(cocoaScreenCoordinates.x,
                       ( mainScreenSize.size.height - cocoaScreenCoordinates.y ));
}

- (void)_visualizeConstraintsMenuAction:(id)sender;
{
    NSMenuItem *item = (NSMenuItem *)sender;
    NSView *view = [item representedObject];
    NSLayoutConstraintOrientation orientation = [item tag];
    [self visualizeConstraints:[view constraintsAffectingLayoutForOrientation:orientation]];
}

- (void)_stopVisualizingConstraintsMenuAction:(id)sender;
{
    [self visualizeConstraints:@[]];
}

- (void)_pickSuperviewMenuAction:(id)sender;
{
    NSView *superview = [(NSView *)[sender representedObject] superview];
    NSRect superviewScreenFrame = [[superview window] convertRectToScreen:[superview convertRect:[superview bounds] toView:nil]];
    NSPoint offsetOrigin = NSMakePoint(NSMinX(superviewScreenFrame) + 20, NSMaxY(superviewScreenFrame) - 20);
    
    [OAViewPicker pickView:superview];
    
    if ([self _showMenuForPickedView:superview atScreenLocation:offsetOrigin])
        [OAViewPicker cancelActivePicker];
    else
        [self visualizeConstraintsForPickedView:nil];
}

- (void)_logSubtreeDescriptionMenuAction:(id)sender;
{
    NSView *view = [sender representedObject];
    if ([view respondsToSelector:@selector(_subtreeDescription)])
        NSLog(@"%@", [[sender representedObject] _subtreeDescription]);
    else
        OBASSERT_NOT_REACHED("Object %@ does not respond to -_subtreeDescription; either the debugging method is gone or it is not an NSView", view);
}

- (void)_copyAddressMenuAction:(id)sender;
{
    NSString *addressString = [NSString stringWithFormat:@"%p", [sender representedObject]];
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard clearContents];
    [pboard writeObjects:[NSArray arrayWithObject:addressString]];
}

- (BOOL)_showMenuForPickedView:(NSView *)pickedView atScreenLocation:(NSPoint)point;
{
    static NSMenu *constraintsOptions;
    static NSMenuItem *headerItem, *frameItem, *alignmentRectItem, *intrinsicContentSizeItem, *ambiguousItem, *translatesItem, *horizontalItem, *verticalItem, *pickSuperviewItem, *logSubtreeItem, *copyAddressItem;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        constraintsOptions = [[NSMenu alloc] initWithTitle:OBUnlocalized(@"View Debugging")];
        [constraintsOptions setAutoenablesItems:NO];
        
        headerItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"<PICKED VIEW>") action:NULL keyEquivalent:@""];
        [headerItem setEnabled:NO];
        
        frameItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"<FRAME>") action:NULL keyEquivalent:@""];
        [frameItem setEnabled:NO];
        
        alignmentRectItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"<ALIGNMENT RECT>") action:NULL keyEquivalent:@""];
        [alignmentRectItem setEnabled:NO];
        
        intrinsicContentSizeItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"<INTRINSIC CONTENT SIZE>") action:NULL keyEquivalent:@""];
        [intrinsicContentSizeItem setEnabled:NO];
        
        [constraintsOptions addItem:[NSMenuItem separatorItem]];
        
        ambiguousItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"<AMBIGIOUS CONSTRAINTS>") action:NULL keyEquivalent:@""];
        [ambiguousItem setEnabled:NO];
        
        translatesItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"<TRANSLATES AUTORESIZING MASK>") action:NULL keyEquivalent:@""];
        [translatesItem setEnabled:NO];
        
        horizontalItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"Visualize horizontal constraints") action:@selector(_visualizeConstraintsMenuAction:) keyEquivalent:@""];
        [horizontalItem setIndentationLevel:1];
        [horizontalItem setTag:NSLayoutConstraintOrientationHorizontal];
        [horizontalItem setEnabled:YES];
        
        verticalItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"Visualize vertical constraints") action:@selector(_visualizeConstraintsMenuAction:) keyEquivalent:@""];
        [verticalItem setIndentationLevel:1];
        [verticalItem setTag:NSLayoutConstraintOrientationVertical];
        [verticalItem setEnabled:YES];
        
        [constraintsOptions addItemWithTitle:OBUnlocalized(@"Stop visualizing constraints") action:@selector(_stopVisualizingConstraintsMenuAction:) keyEquivalent:@""];
        
        [constraintsOptions addItem:[NSMenuItem separatorItem]];
        
        pickSuperviewItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"<SUPERVIEW>") action:@selector(_pickSuperviewMenuAction:) keyEquivalent:@""];
        
        logSubtreeItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"Log subview hierarchy") action:@selector(_logSubtreeDescriptionMenuAction:) keyEquivalent:@""];
        [logSubtreeItem setEnabled:YES];
        
        copyAddressItem = [constraintsOptions addItemWithTitle:OBUnlocalized(@"Copy address") action:@selector(_copyAddressMenuAction:) keyEquivalent:@""];
        [copyAddressItem setEnabled:YES];
    });
    
    [headerItem setTitle:[NSString stringWithFormat:@"%@", [pickedView shortDescription]]];
    [frameItem setTitle:[NSString stringWithFormat:@"Frame: %@", NSStringFromRect([pickedView frame])]];
    [alignmentRectItem setTitle:[NSString stringWithFormat:@"Alignment Rect: %@", NSStringFromRect([pickedView alignmentRectForFrame:[pickedView frame]])]];
    [intrinsicContentSizeItem setTitle:[NSString stringWithFormat:@"Intrinsic Content Size: %@", NSStringFromSize([pickedView intrinsicContentSize])]];
    [ambiguousItem setTitle:OBUnlocalized([pickedView hasAmbiguousLayout] ? @"Has ambiguous layout" : @"Does not have ambiguous layout")];
    [translatesItem setTitle:OBUnlocalized([pickedView translatesAutoresizingMaskIntoConstraints] ? @"Translates autoresizing mask into constraints" : @"Does not translate autoresizing mask into constraints")];
    
    NSView *superview = [pickedView superview];
    [pickSuperviewItem setTitle:OBUnlocalized((superview != nil) ? [NSString stringWithFormat:@"Superview: %@…", [superview shortDescription]] : @"No superview")];
    [pickSuperviewItem setEnabled:superview != nil];
    
    for (NSMenuItem *item in constraintsOptions.itemArray) {
        item.representedObject = pickedView;
        item.target = self;
    }
    
    BOOL picked = [constraintsOptions popUpMenuPositioningItem:headerItem atLocation:point inView:nil];
    
    [horizontalItem setRepresentedObject:nil];
    [verticalItem setRepresentedObject:nil];
    
    return picked;
}

- (void)visualizeConstraintsForPickedView:(nullable id)sender;
{
    [OAViewPicker beginPickingForWindow:self withCompletionHandler:^(NSView *pickedView) {
        if (pickedView)
            return [self _showMenuForPickedView:pickedView atScreenLocation:[NSEvent mouseLocation]];
        else
            return NO;
    }];
}

- (NSResponder * _Nullable)nullableFirstResponder;
{
    return self.firstResponder;
}

// NSCopying protocol

- (id)copyWithZone:(NSZone *)zone;
{
    OBASSERT_NOT_REACHED(@"Who is trying to copy a window?");
    return self;
}

@end

#pragma mark -

@implementation NSWindow (CoalescedRecalculateKeyViewLoop)

static void *RecalculateKeyViewLoopScheduledKey = &RecalculateKeyViewLoopScheduledKey;

- (void)setRecalculateKeyViewLoopScheduled:(BOOL)recalculateKeyViewLoopScheduled
{
    objc_setAssociatedObject(self, RecalculateKeyViewLoopScheduledKey, @(recalculateKeyViewLoopScheduled), OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)isRecalculateKeyViewLoopScheduled
{
    NSNumber *numberRef = objc_getAssociatedObject(self, RecalculateKeyViewLoopScheduledKey);
    BOOL result = [numberRef boolValue];
    return result;
}

- (void)beforeDisplayIfNeededRecalculateKeyViewLoop;
{
    if (self.isRecalculateKeyViewLoopScheduled) {
        return;
    }
    
    self.recalculateKeyViewLoopScheduled = YES;
    
    __weak NSWindow *weakSelf = self;
    [NSWindow beforeAnyDisplayIfNeededPerformBlock:^{
        NSWindow *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        
        if (strongSelf.recalculateKeyViewLoopScheduled) {
            [strongSelf recalculateKeyViewLoop];
            strongSelf.recalculateKeyViewLoopScheduled = NO;
        }
    }];
}

@end

#pragma mark -

static BOOL (*original_validateUserInterfaceItem)(NSWindow *self, SEL _cmd, id <NSValidatedUserInterfaceItem>) = NULL;

@implementation NSWindow (NSWindowTabbingExtensions)

OBPerformPosing(^{
    Class self = objc_getClass("NSWindow");
    original_validateUserInterfaceItem = (typeof(original_validateUserInterfaceItem))OBReplaceMethodImplementation(self, @selector(validateUserInterfaceItem:), (IMP)[[self class] instanceMethodForSelector:@selector(_replacement_validateUserInterfaceItem:)]);
});

- (BOOL)_replacement_validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)item;
{
    BOOL result = original_validateUserInterfaceItem(self, _cmd, item);
    
    if (item.action == @selector(toggleTabBar:)) {
        // Why doesn't NSValidatedUserInterfaceItem conform to NSObject?
        if ([(id)item isKindOfClass:[NSMenuItem class]]) {
            // AppKit puts a checkmark on the menu item title, rather than toggling between Show/Hide as is the convention for other AppKit provided menu items.
            // rdar://problem/28569216
            NSMenuItem *menuItem = OB_CHECKED_CAST(NSMenuItem, item);
            NSString *title = nil;
            
            if (menuItem.state) {
                title = NSLocalizedStringFromTableInBundle(@"Hide Tab Bar", @"OmniAppKit", OMNI_BUNDLE, "menu item title");
            } else {
                title = NSLocalizedStringFromTableInBundle(@"Show Tab Bar", @"OmniAppKit", OMNI_BUNDLE, "menu item title");
            }

            menuItem.title = title;
            menuItem.state = 0;
        }
    }
    
    return result;
}

- (void)withTabbingMode:(NSWindowTabbingMode)tabbingMode performBlock:(void (^)(void))block;
{
    OBPRECONDITION(block != NULL);
    
    if ([[self class] hasTabbedWindowSupport]) {
        NSWindowTabbingMode savedTabbingMode = self.tabbingMode;
        NSDisableScreenUpdates();
        @try {
            self.tabbingMode = tabbingMode;
            block();
        } @finally {
            self.tabbingMode = savedTabbingMode;
            NSEnableScreenUpdates();
        }
    } else {
        block();
    }
}

@end

#pragma mark -

NSNotificationName const OAWindowUserTabbingPreferenceDidChange = @"OAWindowUserTabbingPreferenceDidChange";
void *OAWindowUserTabbingPreferenceDidChangeObservationContext = &OAWindowUserTabbingPreferenceDidChangeObservationContext;

@interface OAWinderUserTabbingPreferenceObserver : NSObject {
  @private
    NSUserDefaults *_userDefaults;
}

@end

#pragma mark -

static OAWinderUserTabbingPreferenceObserver *_sharedUserWindowTabbingPreferenceObserver;

@implementation OAWinderUserTabbingPreferenceObserver : NSObject

OBDidLoad(^{
    if (_sharedUserWindowTabbingPreferenceObserver == nil) {
        _sharedUserWindowTabbingPreferenceObserver = [[OAWinderUserTabbingPreferenceObserver alloc] init];
    }
});

- (instancetype)init;
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    _userDefaults = [NSUserDefaults standardUserDefaults];
    [_userDefaults addObserver:self forKeyPath:@"AppleWindowTabbingMode" options:0 context:OAWindowUserTabbingPreferenceDidChangeObservationContext];
    
    return self;
}

- (void)dealloc;
{
    OBASSERT_NOT_REACHED("Global instance should never be deallocated.");
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey,id> *)change context:(nullable void *)context;
{
    if (context == OAWindowUserTabbingPreferenceDidChangeObservationContext) {
        [[NSNotificationCenter defaultCenter] postNotificationName:OAWindowUserTabbingPreferenceDidChange object:nil];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end

NS_ASSUME_NONNULL_END
