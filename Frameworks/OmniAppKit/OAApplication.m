// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/OAVersion.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OADocument.h>
#import <OmniAppKit/NSResponder-OAExtensions.h>
#import <OmniAppKit/OAViewPicker.h>

#import <Carbon/Carbon.h>
#import <ExceptionHandling/NSExceptionHandler.h>

#import <OmniAppKit/NSEvent-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/OAAppKitQueueProcessor.h>
#import <OmniAppKit/OAPreferenceController.h>
#import <OmniAppKit/OAWebPageViewer.h>

RCS_ID("$Id$")

NSString * const OAFlagsChangedNotification = @"OAFlagsChangedNotification";
NSString * const OAFlagsChangedQueuedNotification = @"OAFlagsChangedNotification (Queued)";

static NSEventModifierFlags launchModifierFlags;
static BOOL OATargetSelection;

BOOL OATargetSelectionEnabled(void)
{
    [OAApplication sharedApplication]; // Make sure global is set up.
    return OATargetSelection;
}

OBDEPRECATED_METHOD(-handleRunException:)
OBDEPRECATED_METHOD(-handleInitException:)
OBDEPRECATED_METHOD(-currentRunExceptionPanel)

@interface OAApplication ()

@property (nonatomic, assign) BOOL isTerminating;

@end

@implementation OAApplication
{
    NSTimeInterval lastEventTimeInterval;
    NSUInteger mouseButtonState;
}

+ (void)initialize;
{
    OBINITIALIZE;

    launchModifierFlags = [NSEvent modifierFlags];
}

- (OFVersionNumber *)buildVersionNumber;
{
    return [OFVersionNumber mainBundleVersionNumber];
}

static NSImage *CautionIcon = nil;

#pragma mark -
#pragma mark NSApplication subclass

+ (instancetype)sharedApplication;
{
    static OAApplication *omniApplication = nil;

    if (omniApplication) {
        OBASSERT([omniApplication isKindOfClass:self]);
        return omniApplication;
    }

    omniApplication = OB_CHECKED_CAST(OAApplication, [super sharedApplication]);
    [self _setupOmniApplication];
    return omniApplication;
}

// This is for the benefit of -miniaturizeWindows: below.
static NSArray *overrideWindows = nil;
- (NSArray *)windows;
{
    if (overrideWindows)
        return overrideWindows;
    return [super windows];
}

#ifdef CustomScrollWheelHandling

#define MAXIMUM_LINE_FACTOR 12.0
#define PAGE_FACTOR MAXIMUM_LINE_FACTOR * 2.0 * 2.0 * 2.0
#define ACCELERATION 2.0
#define MAX_SCALE_SETTINGS 12

static struct {
    float targetScrollFactor;
    float timeSinceLastScroll;
} mouseScaling[MAX_SCALE_SETTINGS] = {
    {1.0, 0.0}
};

static void OATargetScrollFactorReadFromDefaults(void)
{
    NSArray *values;
    unsigned int settingIndex, valueCount;
    NSString *defaultsKey;

    defaultsKey = @"OAScrollWheelTargetScrollFactor";
    values = [[NSUserDefaults standardUserDefaults] arrayForKey:defaultsKey];
    if (values == nil)
        return;
    valueCount = [values count];
    for (settingIndex = 0; settingIndex < MAX_SCALE_SETTINGS; settingIndex++) {
        unsigned int factorValueIndex;
        float factor, cutoff;

        factorValueIndex = settingIndex * 2;
        factor = factorValueIndex < valueCount ? [[values objectAtIndex:factorValueIndex] floatValue] : 0.0;
        cutoff = factorValueIndex + 1 < valueCount ? (1.0 / [[values objectAtIndex:factorValueIndex + 1] floatValue]) : 0.0;
        mouseScaling[settingIndex].targetScrollFactor = factor;
        mouseScaling[settingIndex].timeSinceLastScroll = cutoff;
    }
}

static float OATargetScrollFactorForTimeInterval(NSTimeInterval timeSinceLastScroll)
{
    static BOOL alreadyInitialized = NO;
    unsigned int mouseScalingIndex;

    if (!alreadyInitialized) {
        OATargetScrollFactorReadFromDefaults();
        alreadyInitialized = YES;
    }
    for (mouseScalingIndex = 0;
         mouseScalingIndex < MAX_SCALE_SETTINGS && MAX(0.0, timeSinceLastScroll) < mouseScaling[mouseScalingIndex].timeSinceLastScroll;
         mouseScalingIndex++) {
    }

    return mouseScaling[mouseScalingIndex].targetScrollFactor;
}

static float OAScrollFactorForWheelEvent(NSEvent *event)
{
    static NSTimeInterval lastScrollWheelTimeInterval = 0.0;
    static float scrollFactor = 100.0;
    NSTimeInterval timestamp;
    NSTimeInterval timeSinceLastScroll;
    float targetScrollFactor;
    
    timestamp = [event timestamp];
    timeSinceLastScroll = timestamp - lastScrollWheelTimeInterval;
    targetScrollFactor = OATargetScrollFactorForTimeInterval(timeSinceLastScroll);
    lastScrollWheelTimeInterval = timestamp;
    if (scrollFactor == targetScrollFactor) {
        // Do nothing
    } else if (timeSinceLastScroll > 0.5) {
        // If it's been more than half a second, just start over at the target factor
        scrollFactor = targetScrollFactor;
    } else if (scrollFactor * (1.0 / ACCELERATION) > targetScrollFactor) {
        // Reduce our scroll factor
        scrollFactor *= (1.0 / ACCELERATION);
    } else if (scrollFactor * ACCELERATION < targetScrollFactor) {
        // Increase our scroll factor
        scrollFactor *= ACCELERATION;
    } else {
        // The target is near, just jump to it
        scrollFactor = targetScrollFactor;
    }
    return scrollFactor;
}
#endif

#define OASystemDefinedEvent_MouseButtonsChangedSubType 7

static NSArray *flagsChangedRunLoopModes;

- (void)sendEvent:(NSEvent *)event;
{
    // The -timestamp method on NSEvent doesn't seem to return an NSTimeInterval based off the same reference date as NSDate (which is what we want).
    lastEventTimeInterval = [NSDate timeIntervalSinceReferenceDate];

    @try {
        switch ([event type]) {
            case NSSystemDefined:
                if ([event subtype] == OASystemDefinedEvent_MouseButtonsChangedSubType)
                    [self processMouseButtonsChangedEvent:event];
                [super sendEvent:event];
                break;
            case NSFlagsChanged:
                [super sendEvent:event];
                [[NSNotificationCenter defaultCenter] postNotificationName:OAFlagsChangedNotification object:event];
                if (!flagsChangedRunLoopModes)
                    flagsChangedRunLoopModes = [[NSArray alloc] initWithObjects:
                                                NSDefaultRunLoopMode,
                                                NSRunLoopCommonModes,
                                                NSEventTrackingRunLoopMode, nil];
                [[NSNotificationQueue defaultQueue] enqueueNotification:[NSNotification notificationWithName:OAFlagsChangedQueuedNotification object:event]
                                                           postingStyle:NSPostWhenIdle
                                                           coalesceMask:NSNotificationCoalescingOnName
                                                               forModes:flagsChangedRunLoopModes];
                break;
            case NSLeftMouseDown:
            {
                NSUInteger modifierFlags = [event modifierFlags];
                BOOL justControlDown = (modifierFlags & NSControlKeyMask) && !(modifierFlags & NSShiftKeyMask) && !(modifierFlags & NSCommandKeyMask) && !(modifierFlags & NSAlternateKeyMask);
                
                if (justControlDown) {
                    NSView *contentView = [[event window] contentView];
                    NSView *viewUnderMouse = [contentView hitTest:[event locationInWindow]];
                    
                    if (viewUnderMouse != nil && [viewUnderMouse respondsToSelector:@selector(controlMouseDown:)]) {
                        [viewUnderMouse controlMouseDown:event];
                        return;
                    }
                }
                [super sendEvent:event];
                    
                break;
            }
#ifdef OMNI_ASSERTIONS_ON
            case NSKeyDown:
                if ([[event charactersIgnoringModifiers] isEqualToString:@"\033"] && [OAViewPicker cancelActivePicker]) {
                    break;
                } else if ([[event charactersIgnoringModifiers] isEqualToString:@"V"] && [event checkForAllModifierFlags:NSControlKeyMask|NSCommandKeyMask|NSAlternateKeyMask|NSShiftKeyMask without:0]) {
                    NSUInteger windowNumberUnderMouse = [NSWindow windowNumberAtPoint:[NSEvent mouseLocation] belowWindowWithWindowNumber:0];
                    if (windowNumberUnderMouse) {
                        NSWindow *window = [self windowWithWindowNumber:windowNumberUnderMouse];
                        if ([window isKindOfClass:[OAViewPicker class]])
                            window = [window parentWindow];
                        
                        [window visualizeConstraintsForPickedView:self];
                        break;
                    }
                    
                    [self sendAction:@selector(visualizeConstraintsForPickedView:) to:nil from:self];
                    break;
                } else {
                    // fall through
                }
#endif
                
            default:
                [super sendEvent:event];
                break;
        }
    } @catch (NSException *localException) {
        if ([[localException name] isEqualToString:NSAbortModalException] || [[localException name] isEqualToString:NSAbortPrintingException])
            [localException raise];
        [self reportException:localException];
    }

    [[OFScheduler mainSchedulerIfCreated] scheduleEvents]; // Ping the scheduler, in case NSConditionLock doesn't wake up on schedule
}

BOOL OADebugTargetSelection = NO;
#define DEBUG_TARGET_SELECTION(format, ...) do { \
    if (OADebugTargetSelection) \
        NSLog((format), ## __VA_ARGS__); \
} while (0)

- (BOOL)sendAction:(SEL)theAction to:(id)theTarget from:(id)sender;
{
    OBRecordBacktrace(sel_getName(theAction), OBBacktraceBuffer_PerformSelector);

    if (OATargetSelection) {
        DEBUG_TARGET_SELECTION(@"Checking for modal panel with target %@, key window %@, is modal %d", OBShortObjectDescription(theTarget), OBShortObjectDescription([self keyWindow]), [[self keyWindow] isModalPanel]);

        // The normal NSApplication version, sadly, uses internal target lookup for the nil case. It should really call -targetForAction:to:from:.
        // The AppKit version of this uses _NSTargetForSendAction() which has fewer restrictions on the nil target case (since it 'knows' it will pick the right thing _objectFromResponderChainWhichRespondsToAction()). Even if we return the exact same result as it would have calculated, it bails when we are in a modal session and have a menu item targetting a view in the modal window. See bug:///136395 (Mac-OmniOutliner Bug: Should allow pasting into the password decryption field)
        if (!theTarget && ![[self keyWindow] isModalPanel])
            theTarget = [self targetForAction:theAction to:nil from:sender];
    }
    
    return [super sendAction:theAction to:theTarget from:sender];
}

// Just does our portion of the chain.
- (BOOL)applyToResponderChain:(OAResponderChainApplier)applier;
{
    if (![super applyToResponderChain:applier])
        return NO;
    
    id delegate = (id)self.delegate;
    if (delegate)
        DEBUG_TARGET_SELECTION(@"---> checking OAApplication delegate ");
    if (delegate && ![delegate applyToResponderChain:applier])
        return NO;
    
    return YES;
}

static NSWindow *_documentWindowClaimingSheet(NSWindow *sheet)
{
    // Apple has a private method -[NSWindow _documentWindow]. Since that's not available to us, we search all the app's windows, looking for one that claims the sheet in question.
    OBASSERT([sheet isSheet]); // Not actually dangerous, but I doubt it's ever even convenient to ask us about a window that isn't actually a sheet.
    NSArray *windows = [[NSApplication sharedApplication] windows];
    for (NSWindow *window in windows) {
        if ([window isSheet]) {
            continue;
        }
        NSWindow *attachedSheet = [window attachedSheet];
        // It may not ever be a good idea, but it's possible for a sheet to be presented on another sheet, so we have to accommodate that possibility.
        do {
            if (attachedSheet == sheet) {
                return window;
            }
            attachedSheet = [attachedSheet attachedSheet];
        } while (attachedSheet != nil);
    }
    return nil;
}

static BOOL _windowIsDismissedSheet(NSWindow *window)
{
    // While there is no direct API for determining if a sheet has been dismissed, once it has been dismissed it no other window will claim it as their attachedSheet.
    return (window.isSheet && (_documentWindowClaimingSheet(window) == nil));
}

static BOOL _applySearchToWindow(NSWindow *window, SEL theAction, id theTarget, id sender, OAResponderChainApplier applier)
{
    // If the window is a dismissed sheet, don't search it. This comes up frequently because -[NSApplication keyWindow] will return a sheet that has been dismissed and is in the process of animating out. We of course don't want to target a dismissed sheet to begin with, but there can also be a big penalty for messaging a dismissed sheet: a dismissed Powerbox sheet in a sandboxed app (such as the Save sheet) is taking about 1/3 of a second to respond to our messages, so we were seeing ~five-second pauses after exiting a Powerbox sheet, which turned out to be us messaging the dismissed sheet for multiple toolbar items and so forth as we validated them.
    if ((window != nil) && !_windowIsDismissedSheet(window)) {
        // Search the responder chain - unless the window has an attached sheet, in which case the sheet "blocks" the responder chain
        BOOL windowHasAttachedSheet = (window.attachedSheet != nil);
        if (!windowHasAttachedSheet) {
            NSResponder *firstResponder = window.firstResponder;
            if ((firstResponder != nil) && ![firstResponder applyToResponderChain:applier]) {
                return NO; // Don't continue searching
            }
        }
        
        // Try the window object itself. This may have been tried as part of the responder chain above, but in case not, we have to check it here.
        if (!applier(window)) {
            return NO; // Don't continue searching
        }

        // If the window has an attached sheet, we won't have tried the responder chain above and thus won't have checked the supplemental target, so we need to check it here. (But note that NSWindow's supplemental target check changes if the window has an attached sheet - it won't offer either the delegate or window controller as the responsible target in that case, even if they implement the action in question.)
        if (windowHasAttachedSheet) {
            id supplementalTarget = [window supplementalTargetForAction:theAction sender:sender];
            if ((supplementalTarget != nil) && !applier(supplementalTarget)) {
                return NO; // Don't continue searching
            }
        }
    }
    
    return YES; // Continue searching, because we haven't found the target yet
}

// Does the full search documented for -targetForAction:to:from:
static void _applyFullSearch(OAApplication *self, SEL theAction, id theTarget, id sender, OAResponderChainApplier applier)
{
    // Toolbar items always validate from the view they belong to, but there's no public way to get at that window (because NSToolbarItem is a model object).
    if ([sender isKindOfClass:[NSToolbarItem class]]) {
        Ivar itemViewerIvar = class_getInstanceVariable([NSToolbarItem class], "_itemViewer");
        if (itemViewerIvar) {
            id itemViewer = object_getIvar(sender, itemViewerIvar);
            if (itemViewer) {
                OBASSERT([itemViewer respondsToSelector:@selector(window)]);
                if (!_applySearchToWindow([itemViewer window], theAction, theTarget, sender, applier))
                    return;
            }
        }
    } else {
        // Try the key window
        NSWindow *keyWindow = self.keyWindow;
        if (!_applySearchToWindow(keyWindow, theAction, theTarget, sender, applier)) {
            return;
        }
        
        // Try the main window (if it is not the same window as the key window)
        NSWindow *mainWindow = self.mainWindow;
        if ((mainWindow != keyWindow) && !_applySearchToWindow(mainWindow, theAction, theTarget, sender, applier)) {
            return;
        }
    }
    
    if (![self applyToResponderChain:applier]) {
        return;
    }
    
    // This isn't ideal since this forces an NSDocumentController to be created.  AppKit presumably has some magic to avoid this...  We could avoid this if there are no registered document types, if that becomes an issue.
    NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
    if (documentController && ![documentController applyToResponderChain:applier])
        return;
}

- (id)targetForAction:(SEL)theAction;
{
    if (!theAction || !OATargetSelection)
        return [super targetForAction:theAction];
    else {
        DEBUG_TARGET_SELECTION(@"Forwarding -targetForAction: to targetForAction:to:from: for action %@", NSStringFromSelector(theAction));
        return [self targetForAction:theAction to:nil from:nil];
    }
}

- (id)targetForAction:(SEL)theAction to:(id)theTarget from:(id)sender;
{
    if (!theAction || !OATargetSelection)
        return [super targetForAction:theAction to:theTarget from:sender];
    
    __block id target = nil;
    
    DEBUG_TARGET_SELECTION(@"looking for target for action: %@ given\n   target:%@\n    sender:%@\n    keyWindow first responder:%@\n    mainWindow first responder:%@)", NSStringFromSelector(theAction), [theTarget shortDescription], [sender shortDescription], [[[self keyWindow] firstResponder] shortDescription], [[[self mainWindow] firstResponder] shortDescription]);
    
    OAResponderChainApplier applier = ^(id object){
        DEBUG_TARGET_SELECTION(@" ... trying %@", [object shortDescription]);
        
        if (OADebugTargetSelection && [object respondsToSelector:@selector(window)]) {
            DEBUG_TARGET_SELECTION(@"       has window: %@", [[object window] shortDescription]);
        }
        
        id responsible = [object responsibleTargetForAction:theAction sender:sender];
        
        // Use the supplementalTargetForAction mechanism that was introduced in 10.7 to look for delegates and other helper objects attached to responders, but still use our OATargetSelection approach of requiring objects to override responsibleTargetForAction if they wish to terminate the search.
        if (!responsible && [object isKindOfClass:[NSResponder class]]) {
            DEBUG_TARGET_SELECTION(@"      ... trying supplementalTarget");
            responsible = [(NSResponder *)object supplementalTargetForAction:theAction sender:sender];
            if (responsible)
                DEBUG_TARGET_SELECTION(@"      ... got supplementalTarget: %@", [responsible shortDescription]);
            responsible = [responsible responsibleTargetForAction:theAction sender:sender];
        }
        
        if (responsible) {
            // Someone claimed to be responsible for the action.  The sender will re-validate with any appropriate means and might still get refused, but we should stop iterating.
            DEBUG_TARGET_SELECTION(@"      ... got responsible target: %@", responsible);

            if (([responsible isKindOfClass:[NSWindow class]]) && [(NSWindow *)responsible isSheet]) {
                NSWindow *documentWindow = _documentWindowClaimingSheet(responsible);
                OBASSERT(documentWindow != nil); // responsible is a sheet; we better be able to find its document window
                if ((documentWindow != nil) && [documentWindow responsibleTargetForAction:theAction sender:sender]) {
                    responsible = documentWindow;
                    DEBUG_TARGET_SELECTION(@"          ... responsible target overridden by its document window: %@", responsible);
                }
            }

            target = responsible;
            return NO; // stop the search
        }
        return YES; // continue searching
    };
    
    // The caller had a specific target in mind.  Start there and follow the responder chain.  The documentation states that if the target is non-nil, it is returned (which is silly since why would you call this method then?)
    if (theTarget)
        [theTarget applyToResponderChain:applier];
    else {
        _applyFullSearch(self, theAction, theTarget, sender, applier);
    }
    
    DEBUG_TARGET_SELECTION(@" ... using %@", [target shortDescription]);
    return target;
}

- (void)reportException:(NSException *)anException;
{
    // Let OFController have a crack at this.  It may decide it wants to up and crash to report uncaught exceptions back to home base.  Strange, but we'll cover our bases here.  Do our alert regardless of the result, which is intended to control whether AppKit logs the message (but we are displaying UI, not just spewing to Console).
    // Pass NSLogUncaughtExceptionMask to simulate a totally uncaught exception, even though AppKit has a top-level handler.  This will cause OFController to get the exception two times; once with NSLogOtherExceptionMask (ignored, since it might be caught) and here with NSLogUncaughtExceptionMask (it turned out to not get caught).  One bonus is that since it is the same exception, the NSStackTraceKey is in place and has the location of the original exception raise point.
    if ([[OFController sharedController] exceptionHandler:[NSExceptionHandler defaultExceptionHandler] shouldLogException:anException mask:NSLogUncaughtExceptionMask])
        [super reportException:anException];
}

- (void)terminate:(id)sender
{
    self.isTerminating = YES;
    [super terminate:sender];
}

#pragma mark NSResponder subclass

- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate didPresentSelector:(SEL)didPresentSelector contextInfo:(void *)contextInfo;
{
    OBPRECONDITION(error); // The superclass will call CFRetain and we'll crash if this is nil.
    
    // If you want to pass nil/NULL, could call the simpler method above.
    OBPRECONDITION(delegate);
    OBPRECONDITION(didPresentSelector);
    
    if (!error) {
        NSLog(@"%s called with a nil error", __PRETTY_FUNCTION__);
        NSBeep();
        return;
    }

    if (self.isTerminating) {
        // Can’t run a modal error while terminating. This avoids a crash-on-quit.
        NSLog(@"%s called while terminating with error: %@", __PRETTY_FUNCTION__, error);
        return;
    }

    // nil/NULL here can crash in the superclass crash trying to build an NSInvocation from this goop.  Let's not.
    if (!delegate) {
        delegate = self;
        didPresentSelector = @selector(noop_didPresentErrorWithRecovery:contextInfo:); // From NSResponder(OAExtensions)
    }
    
    // Log all errors so users can report them.
    if (![error causedByUserCancelling])
        NSLog(@"Presenting application modal error for window %@: %@", [window title], [error toPropertyList]);
    [super presentError:error modalForWindow:window delegate:delegate didPresentSelector:didPresentSelector contextInfo:contextInfo];
}

- (BOOL)presentError:(NSError *)error;
{
    // Log all errors so users can report them.
    if (![error causedByUserCancelling])
        NSLog(@"Presenting modal error: %@", [error toPropertyList]);
    return [super presentError:error];
}

#pragma mark -
#pragma mark API

- (NSWindow *)frontWindowForMouseLocation;
{
    for (NSWindow *window in [NSWindow windowsInZOrder]) {
	if ([window ignoresMouseEvents])
	    continue;
	    
        NSPoint mouse = [window mouseLocationOutsideOfEventStream];
        NSView *contentView = [window contentView];
        if ([contentView mouse:mouse inRect:[contentView frame]])
            return window;
    }
    
    return nil;
}

- (NSTimeInterval)lastEventTimeInterval;
{
    return lastEventTimeInterval;
}

- (BOOL)mouseButtonIsDownAtIndex:(unsigned int)mouseButtonIndex;
{
    return (mouseButtonState & (1 << mouseButtonIndex)) != 0;
}

- (BOOL)scrollWheelButtonIsDown;
{
    return [self mouseButtonIsDownAtIndex:2];
}

- (NSEventModifierFlags)launchModifierFlags;
{
    return launchModifierFlags;
}

// Prefix the URL string with "anchor:" if the string is the name of an anchor in the help files. Prefix it with "search:" to search for the string in the help book.
- (void)showHelpURL:(NSString *)helpURLString;
{
    // We prefer to display help in an internal help viewer
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *infoDict = [mainBundle infoDictionary];
    NSString *helpFolder = [infoDict objectForKey:@"OAHelpFolder"];
    if (helpFolder != nil) { // Display our help internally
        NSURL *targetURL = [self builtInHelpURLForHelpURLString:helpURLString];
        if (targetURL == nil) {
            NSLog(@"Warning: couldn't determine help page resource for help URL `%@`", helpURLString);
            NSBeep();
            return;
        }

        NSString *title = [[mainBundle localizedInfoDictionary] stringForKey:@"OAHelpBookName"];
        if ([NSString isEmptyString:title]) {
            title = [infoDict stringForKey:@"OAHelpBookName"];
        }
        
        if ([NSString isEmptyString:title]) {
            title = NSLocalizedStringFromTableInBundle(@"Help", @"OmniAppKit", [OAApplication bundle], "Help window default title");
        }

        OAWebPageViewer *viewer = [OAWebPageViewer sharedViewerNamed:@"Help"];
        viewer.usesWebPageTitleForWindowTitle = NO;

        CGFloat startingWidth = [infoDict floatForKey:@"OAHelpWidth" defaultValue:800.0f];
        CGFloat startingHeight = [infoDict floatForKey:@"OAHelpHeight" defaultValue:650.0f];
        CGFloat minHeight = [infoDict floatForKey:@"OAHelpMinHeight" defaultValue:200.0f];
        CGFloat minWidth = [infoDict floatForKey:@"OAHelpMinWidth" defaultValue:startingWidth];
        CGFloat maxWidth = [infoDict floatForKey:@"OAHelpMaxWidth" defaultValue:startingWidth];

        NSWindow *window = [viewer window];
        [window setTitle:title];
        [window setContentMinSize:(NSSize) {.height = minHeight, .width = minWidth}];
        [window setContentMaxSize:(NSSize) {.height = CGFLOAT_MAX, .width = maxWidth}];
        [window setContentSize:(NSSize) {.height = startingHeight, .width = startingWidth}];
        [window center];

        NSURLRequest *request = [NSURLRequest requestWithURL:targetURL];
        [viewer loadRequest:request];
        return;
    }

    // OmniWeb displays its help in one of its browser windows
    id applicationDelegate = [[NSApplication sharedApplication] delegate];
    if ([applicationDelegate respondsToSelector:@selector(openAddressWithString:)]) {
        // We're presumably in OmniWeb, in which case we display our help internally
        NSString *omniwebHelpBaseURL = @"omniweb:/Help/";
        if ([helpURLString isEqualToString:@"anchor:updatepreferences"])
            helpURLString = @"reference/preferences/Update.html";
        [applicationDelegate performSelector:@selector(openAddressWithString:) withObject:[omniwebHelpBaseURL stringByAppendingString:helpURLString]];
        return;
    }

    // Standard Apple Help
    NSString *bookName = [mainBundle localizedStringForKey:@"CFBundleHelpBookName" value:@"" table:@"InfoPlist"];
    if (![bookName isEqualToString:@"CFBundleHelpBookName"]) {
        // We've got Apple Help.  First, make sure the help book is registered.  NSHelpManager would do this for us, but we use AHGotoPage, which it doesn't cover.
        static BOOL helpBookRegistered = NO;
        if (!helpBookRegistered) {
            helpBookRegistered = YES;
            NSURL *appBundleURL = [NSURL fileURLWithPath:[mainBundle bundlePath]];
            if (appBundleURL) {
                OSStatus status = AHRegisterHelpBookWithURL((CFURLRef)appBundleURL);
                if (status != 0) {
                    NSLog(@"AHRegisterHelpBookWithURL(%@) returned %ld", appBundleURL, (long)status);
                }
            }
        }


        OSStatus err;
        NSRange range = [helpURLString rangeOfString:@"search:"];
        if ((range.length != 0) || (range.location == 0))
            err = AHSearch((CFStringRef)bookName, (CFStringRef)[helpURLString substringFromIndex:NSMaxRange(range)]);
        else {
            range = [helpURLString rangeOfString:@"anchor:"];
            if ((range.length != 0) || (range.location == 0))
                err = AHLookupAnchor((CFStringRef)bookName, (CFStringRef)[helpURLString substringFromIndex:NSMaxRange(range)]);
            else
                err = AHGotoPage((CFStringRef)bookName, (CFStringRef)helpURLString, NULL);
        }

        if (err != noErr)
            NSLog(@"Apple Help error: %@", OFOSStatusDescription(err));
        return;
    }

    // No help?
    NSLog(@"Warning: could not find built-in help for %@", helpURLString);
    NSBeep();
}

- (NSString *)helpIndexFilename;
{
    return @"index";
}

- (NSString *)anchorsPlistFilename;
{
    return @"anchors";
}

- (NSURL *)builtInHelpURLForHelpURLString:(NSString *)helpURLString;
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *infoDict = [mainBundle infoDictionary];
    NSString *helpFolder = [infoDict objectForKey:@"OAHelpFolder"];

    if (helpFolder != nil) {
        NSURL *indexPageURL = [[NSBundle mainBundle] URLForResource:[self helpIndexFilename] withExtension:@"html" subdirectory:helpFolder];
        NSURL *targetURL = [NSURL URLWithString:helpURLString relativeToURL:indexPageURL];

        if (OFISEQUAL([targetURL scheme], @"anchor")) {
            NSURL *anchorsPlistURL = [[NSBundle mainBundle] URLForResource:[self anchorsPlistFilename] withExtension:@"plist" subdirectory:helpFolder];
            NSDictionary *anchorsDictionary = [NSDictionary dictionaryWithContentsOfURL:anchorsPlistURL];
            NSString *anchorURLString = [anchorsDictionary objectForKey:helpURLString];
            if (anchorURLString == nil) {
                return nil;
            }

            targetURL = [NSURL URLWithString:anchorURLString relativeToURL:indexPageURL];
        }
        
        return targetURL;
    }
    
    return nil;
}

- (IBAction)showHelp:(id)sender;
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *infoDict = [mainBundle infoDictionary];
    NSString *helpFolder = [infoDict objectForKey:@"OAHelpFolder"];
    if (helpFolder != nil) { // Display our help internally
        [self showHelpURL:@""];
    } else {
        [super showHelp:nil];
    }
}

#pragma mark -
#pragma mark Application Support directory

- (NSString *)applicationSupportDirectoryName;
{
    NSString *appSupportDirectory = nil;
    
    id appDelegate = [self delegate];
    if (appDelegate != nil && [appDelegate respondsToSelector:@selector(applicationSupportDirectoryName)])
        appSupportDirectory = [appDelegate applicationSupportDirectoryName];
    
    // TODO: Would it be better to use [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"] here ?
    if (appSupportDirectory == nil)
        appSupportDirectory = [[NSProcessInfo processInfo] processName];
    
    OBASSERT(appSupportDirectory != nil);

    return appSupportDirectory;
}

- (NSArray *)supportDirectoriesInDomain:(NSSearchPathDomainMask)domains;
{
    NSArray *appSupp = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, domains, YES);
    if (appSupp == nil) {
        NSArray *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, domains, YES);
        if (library == nil)
            return nil;
        appSupp = [library arrayByPerformingSelector:@selector(stringByAppendingPathComponent:) withObject:@"Application Support"];
    }
        
    return [appSupp arrayByPerformingSelector:@selector(stringByAppendingPathComponent:) withObject:[self applicationSupportDirectoryName]];
}

- (NSArray *)readableSupportDirectoriesInDomain:(NSSearchPathDomainMask)domains withComponents:(NSString *)subdir, ...;
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSMutableArray *result = [NSMutableArray array];
    
    for (NSString *path in [self supportDirectoriesInDomain:domains]) {
        va_list varg;
        va_start(varg, subdir);
        NSString *component = subdir;
        while (component != nil) {
            path = [path stringByAppendingPathComponent:component];
            component = va_arg(varg, NSString *);
        }
        va_end(varg);
        
        BOOL isDir;
        if ([filemgr fileExistsAtPath:path isDirectory:&isDir] && isDir)
            [result addObject:path];
    }
    return result;
}

- (NSString *)writableSupportDirectoryInDomain:(NSSearchPathDomainMask)domains withComponents:(NSString *)subdir, ...;
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    
    for (NSString *path in [self supportDirectoriesInDomain:domains]) {
        va_list varg;
        va_start(varg, subdir);
        NSString *component = subdir;
        while (component != nil) {
            path = [path stringByAppendingPathComponent:component];
            component = va_arg(varg, NSString *);
        }
        va_end(varg);
        
        BOOL isDir;
        if ([filemgr fileExistsAtPath:path isDirectory:&isDir]) {
            if(isDir && [filemgr isWritableFileAtPath:path])
                return path;
        } else {
            NSError *error = nil;
            if ([filemgr createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) // only return if there is no error creating the directory
                return path;
        }
    }
    return nil;
}

#pragma mark -
#pragma mark Actions

- (IBAction)closeAllMainWindows:(id)sender;
{
    for (NSWindow *window in [NSArray arrayWithArray:[self orderedWindows]]) {
        if ([window canBecomeMainWindow])
            [window performClose:nil];
    }
}

- (IBAction)cycleToNextMainWindow:(id)sender;
{
    NSWindow *mainWindow = [[NSApplication sharedApplication] mainWindow];
    
    for (NSWindow *window in [[NSApplication sharedApplication] orderedWindows]) {
        if (window != mainWindow && [window canBecomeMainWindow] && ![NSStringFromClass([window class]) isEqualToString:@"NSDrawerWindow"]) {
            [window makeKeyAndOrderFront:nil];
            [mainWindow orderBack:nil];
            return;
        }
    }
    // There's one (or less) window which can potentially be main, make it key and bring it forward.
    [mainWindow makeKeyAndOrderFront:nil];
}

- (IBAction)cycleToPreviousMainWindow:(id)sender;
{
    NSWindow *mainWindow = [[NSApplication sharedApplication] mainWindow];
    
    for (NSWindow *window in [[[NSApplication sharedApplication] orderedWindows] reverseObjectEnumerator]) {
        if (window != mainWindow && [window canBecomeMainWindow] && ![NSStringFromClass([window class]) isEqualToString:@"NSDrawerWindow"]) {
            [window makeKeyAndOrderFront:nil];
            return;
        }
    }
    // There's one (or less) window which can potentially be main, make it key and bring it forward.
    [mainWindow makeKeyAndOrderFront:nil];
}

- (IBAction)showPreferencesPanel:(id)sender;
{
    [[OAPreferenceController sharedPreferenceController] showPreferencesPanel:nil];
}

- (void)miniaturizeWindows:(NSArray *)windows;
{
    overrideWindows = windows;
    @try {
        [super miniaturizeAll:nil];
    } @finally {
        overrideWindows = nil;
    }
}

#pragma mark - AppleScript

- (NSArray <OFPreference *> *)scriptPreferences;
{
    NSMutableArray *scriptPreferences = [NSMutableArray array];
    NSArray *registeredKeys = [[[OFPreference registeredKeys] allObjects] sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *key in registeredKeys) {
        OFPreference *preference = [OFPreference preferenceForKey:key];
        OBASSERT(preference);
        if (preference != nil) {
            [scriptPreferences addObject:preference];
        }
    }

    return scriptPreferences;
}

- (OFPreference *)valueInScriptPreferencesWithUniqueID:(NSString *)identifier;
{
    // Only return OFPreference objects, by unique ID, that exist.
    // (That is, you shouldn't be able to access a preference by ID that doesn't exist in `every preference`.)
    
    if (![[OFPreference registeredKeys] containsObject:identifier]) {
        return nil;
    }
    
    return [OFPreference preferenceForKey:identifier];
}

- (BOOL)_shouldFilterWindowFromOrderedWindows:(NSWindow *)window;
{
    static BOOL hasComputedSignatures = NO;
    static NSData *fullScreenToolbarWindowSignature = nil;
    static NSData *fullScreenBackdropWindowSignature = nil;

    // We have to filter these windows by private classname. Since the private classname cannot appear in our App Store binary, we do it by sha1 hash.

    if (!hasComputedSignatures) {
        hasComputedSignatures = YES;
    
        unsigned char toolbarSignatureBytes[] = {0x69, 0x20, 0xef, 0xa7, 0x58, 0xa2, 0x8c, 0xc3, 0x20, 0xa1, 0xb8, 0xcd, 0x75, 0x46, 0x40, 0xfc, 0x05, 0xae, 0x61, 0x0a};
        fullScreenToolbarWindowSignature = [[NSData alloc] initWithBytes:toolbarSignatureBytes length:sizeof(toolbarSignatureBytes) / sizeof(unsigned char)];

        unsigned char backdropSignatureBytes[] = {0x35, 0xc2, 0x5e, 0x22, 0xd0, 0x4b, 0x59, 0x4a, 0xfe, 0xc7, 0xb2, 0x0c, 0xb5, 0x8d, 0x07, 0x4b, 0xee, 0x4a, 0x35, 0x52};
        fullScreenBackdropWindowSignature = [[NSData alloc] initWithBytes:backdropSignatureBytes length:sizeof(backdropSignatureBytes) / sizeof(unsigned char)];

#ifdef DEBUG
        // Make sure we didn't botch the static sha1 signatures above
        NSData *signature = nil;
        
        signature = [[@"NSToolbarFullScreenWindow" dataUsingEncoding:NSUTF8StringEncoding] sha1Signature];
        OBASSERT([signature isEqualToData:fullScreenToolbarWindowSignature]);

        signature = [[@"_NSFullScreenUnbufferedWindow" dataUsingEncoding:NSUTF8StringEncoding] sha1Signature];
        OBASSERT([signature isEqualToData:fullScreenBackdropWindowSignature]);
#endif
    }

    NSData *signature = [[NSStringFromClass([window class]) dataUsingEncoding:NSUTF8StringEncoding] sha1Signature];
    
    if ([signature isEqualToData:fullScreenToolbarWindowSignature])
        return YES;

    if ([signature isEqualToData:fullScreenBackdropWindowSignature])
        return YES;
        
    return NO;
}

- (NSArray *)orderedWindows;
{
    NSArray *orderedWindows = [super orderedWindows];

    {
        // Workaround for rdar://problem/10262921
        //
        // In full-screen mode, the window's toolbar gets hosted in it's own window, and there is a full-screen backdrop window.
        // These are returned as window 1 and window N.
        // Both are unexpected, and uninteresting to scripters. 
        // Worse, it breaks the idiom that the first window is the interesting one to target.
        // Fixes <bug:///74072> (10.7 / Lion :  Full screened apps don't return the full screened window as window 1, breaking scripts [applescript])

        NSMutableArray *filteredOrderedWindows = [NSMutableArray array];
        NSEnumerator *enumerator = [orderedWindows objectEnumerator];
        NSWindow *window = nil;
        
        while (nil != (window = [enumerator nextObject])) {
            // Exclude NSToolbarFullScreenWindow and _NSFullScreenUnbufferedWindow
            // We must test by hash of the classname so that we don't trigger SPI detection on the Mac App Store
            if ([self _shouldFilterWindowFromOrderedWindows:window])
                continue;
                       
            [filteredOrderedWindows addObject:window];
        }
        
        orderedWindows = filteredOrderedWindows;
    }

    return orderedWindows;
}

- (id)valueInOrderedDocumentsWithUniqueID:(NSString *)identifier ignoringDocument:(OADocument *)ignoringDocument;
{
    // Probably not worth building a hash table for the (likely) low number of documents.
    for (OADocument *document in [self orderedDocuments]) {
        // Needed so that -identifier on OADocument(Scriptability) doesn't recurse infinitely
        if (document == ignoringDocument)
            continue;
        
        // -scriptIdentifierIfSet so that if there are two documents w/o identifiers we don't ping/pong between them infinitely.
        if ([document.scriptIdentifierIfSet isEqual:identifier])
            return document;
    }
    return nil;
}

- (id)valueInOrderedDocumentsWithUniqueID:(NSString *)identifier;
{
    return [self valueInOrderedDocumentsWithUniqueID:identifier ignoringDocument:nil];
}

- (id)valueInOrderedDocumentsWithName:(NSString *)name;
{
    // The "name" property maps to -displayName
    // Name lookups are supposed to be case-insensitive. We could prefer exact matches, but then 'every document whose name is "foo"' might return objects a first object that is different than 'document "foo"'...
    
    for (OADocument *document in [[NSApplication sharedApplication] orderedDocuments]) {
        if ([name localizedCaseInsensitiveCompare:document.displayName] == NSOrderedSame)
	    return document;
    }
    
    return nil;
}

#pragma mark -
#pragma mark Private

+ (void)_setupOmniApplication;
{
    [OBObject self]; // Trigger OBInvokeRegisteredLoadActions()
    
    // Wait until defaults are registered via OBInvokeRegisteredLoadActions() to look this up.
    OATargetSelection = [[NSUserDefaults standardUserDefaults] boolForKey:@"OATargetSelection"];

    // make these images available to client nibs and whatnot (retaining them so they stick around in cache).
    // Store them in ivars to avoid clang scan-build warnings.
    CautionIcon = [[NSImage imageNamed:@"OACautionIcon" inBundle:OMNI_BUNDLE] retain];
}

- (void)processMouseButtonsChangedEvent:(NSEvent *)event;
{
    mouseButtonState = [event data2];
}

@end

#pragma mark -
#pragma mark OATargetSelection

@implementation NSObject (OATargetSelection)

- (BOOL)applyToResponderChain:(OAResponderChainApplier)applier;
{
    return applier(self);
}

- (BOOL)_stubValidatorMethodJustForItsTypeSignature:(id)sender;
{
    return YES;
}

static BOOL _validates(id self, SEL validateSelector, id sender)
{
#ifdef DEBUG
    static const char *expectedValidatorMethodType = NULL;
    if (!expectedValidatorMethodType) {
        expectedValidatorMethodType = method_getTypeEncoding(class_getInstanceMethod([NSObject class], @selector(_stubValidatorMethodJustForItsTypeSignature:)));
    }
#endif

    Method validatorMethod = class_getInstanceMethod([self class], validateSelector);
    if (!validatorMethod) {
        OBASSERT_NOT_REACHED("validator method not implemented");
        return NO;
    }
        
#ifdef DEBUG
    const char *validatorMethodType = method_getTypeEncoding(validatorMethod);
    if(strcmp(validatorMethodType, expectedValidatorMethodType)) {
        OBASSERT_NOT_REACHED("implemented validator method is of the wrong type");
        return NO;
    }
#endif

    IMP validatorImplementation = method_getImplementation(validatorMethod);
    BOOL (*validator)(id self, SEL selector, id sender) = (typeof(validator))validatorImplementation;
    return validator(self, validateSelector, sender);
}

static id _selfIfValidElseNil(id self, SEL validateSelector, id sender)
{
    if (_validates(self, validateSelector, sender))
        return self;
    else
        return nil;
}

- (id)responsibleTargetForAction:(SEL)action sender:(id)sender;
{
    if (![self respondsToSelector:action])
        return nil;
    
    SEL validateSpecificItemSelector = NULL;
    if ([sender isKindOfClass:[NSMenuItem class]])
        validateSpecificItemSelector = @selector(validateMenuItem:);
    else if ([sender isKindOfClass:[NSToolbarItem class]])
        validateSpecificItemSelector = @selector(validateToolbarItem:);
    
    if (validateSpecificItemSelector != NULL)
        return _selfIfValidElseNil(self, validateSpecificItemSelector, sender);
    else if ([sender conformsToProtocol:@protocol(NSValidatedUserInterfaceItem)])
        return _selfIfValidElseNil(self, @selector(validateUserInterfaceItem:), sender);

    return self;
}

@end

@interface NSResponder (OATargetSelection)
@end
@implementation NSResponder (OATargetSelection)

- (BOOL)applyToResponderChain:(OAResponderChainApplier)applier;
{
    if (![super applyToResponderChain:applier])
        return NO;
    
    NSResponder *next = self.nextResponder;
    if (next)
        DEBUG_TARGET_SELECTION(@"---> checking nextResponder ");
    if (next && ![next applyToResponderChain:applier])
        return NO;

    return YES;
}

@end

@interface NSWindow (OATargetSelection)
@end
@implementation NSWindow (OATargetSelection)

- (BOOL)_objectIsInResponderChainPriorToWindow:(id)obj;
{
    NSResponder *nomad = self.firstResponder;
    while (nomad != nil) {
        if (nomad == obj) {
            return YES;
        }
        if (![nomad respondsToSelector:@selector(nextResponder)]) {
            break;
        }
        nomad = nomad.nextResponder;
    }
    return NO;
}

- (BOOL)_appearsInResponderChainAfterResponder:(NSResponder *)responder
{
    NSResponder *nomad = responder;
    while (nomad) {
        if (nomad == self) {
            return YES;
        }
        nomad = nomad.nextResponder;
    }
    return NO;
}

- (BOOL)_isInResponderChainLoop
{
    return [self _appearsInResponderChainAfterResponder:self.nextResponder];
}

- (BOOL)applyToResponderChain:(OAResponderChainApplier)applier;
{
    // <bug:///116560> (Crasher: Crash [needs repro]: OATargetSelection loop)
    // At this writing (26 June 2015) this is the second-most-common crash in OmniOutliner. Unfortunately we don't have a reproducible case (though it seems to happen — sometimes — when looking up a word).
    if ([self _isInResponderChainLoop]) {
        DEBUG_TARGET_SELECTION(@"---> NOT applying to NSWindow because of a responder chain loop");
       return NO;
    }
    if (![super applyToResponderChain:applier])
        return NO;
    
    // Beginning in 10.7, as a first approximation, the delegate is returned via supplementalTargetForAction:sender:. However, if the delegate is an NSResponder, then NSWindow seems to chase the responder chain and return the first object that implements the action. We apply our mechanism here. It's redundant in some cases, but lets us run the applier against the full chain.
    id delegate = (id)self.delegate;
    if (delegate)
        DEBUG_TARGET_SELECTION(@"---> checking NSWindow delegate ");

    //PBS 4/3/15: if the window's delegate is also in the responder chain (between the window's first responder and the window itself), and the window's delegate responds to nextResponder with something other than nil, then we'll end up in an infinite loop. This happens specifically with the system's dictionary popover, which has a hierarchy like this: NSLayerCentricRemoteView - LULookupRemoteViewController - NSPopover - _NSPopoverWindow. _NSPopoverWindow's delegate is LULookupRemoteViewController.
    BOOL shouldCheckDelegate = YES;
    if ([delegate respondsToSelector:@selector(nextResponder)] && [delegate nextResponder]) {
        shouldCheckDelegate = ![self _objectIsInResponderChainPriorToWindow:delegate];
        if (!shouldCheckDelegate) {
            DEBUG_TARGET_SELECTION(@"---> NOT checking NSWindow delegate because it appears in the responder chain before now and it has a nextResponder");
        } else {
            shouldCheckDelegate = ![self _appearsInResponderChainAfterResponder:delegate];
            if (!shouldCheckDelegate) {
                DEBUG_TARGET_SELECTION(@"---> NOT checking NSWindow delegate because of a responder chain loop");
            }
        }
    }

    if (shouldCheckDelegate && delegate && ![delegate applyToResponderChain:applier])
        return NO;
    
    id windowController = self.windowController;
    if (windowController)
        DEBUG_TARGET_SELECTION(@"---> checking NSWindow windowController ");
    if (windowController && windowController != delegate && ![windowController applyToResponderChain:applier])
        return NO;
    
    return YES;
}

@end

@interface NSWindowController (OATargetSelection)
@end
@implementation NSWindowController (OATargetSelection)

- (BOOL)applyToResponderChain:(OAResponderChainApplier)applier;
{
    if (![super applyToResponderChain:applier])
        return NO;

    NSDocument *document = self.document;
    if (document)
        DEBUG_TARGET_SELECTION(@"---> checking NSWindowController document ");
    if (document && ![document applyToResponderChain:applier])
        return NO;
    
    return YES;
}

@end


#pragma mark -
#pragma mark OATargetSelectionValidation

@interface NSObject (OATargetSelectionValidation)
/* 
 Allows replacing monolithic validateMenuItem:, validateToolbarItem:, and validateUserInterfaceItem: methods with action-specific methods. For example, a toggleRulerView: action can be validated using:
 
        - (BOOL)validateToggleRulerViewMenuItem:(NSMenuItem *)item;
        - (BOOL)validateToggleRulerViewToolbarItem:(NSToolbarItem *)item;

 depending on the type of the sender. If the sender-type-specific method is missing, then we validate the action using:
 
        - (BOOL)validateToggleRulerView:(id <NSValidatedUserInterfaceItem>)item;
 
 which is useful when the toolbar item and menu item for an action have the same validation logic.
 
 Note well: if the monolithic validateMenuItem:, validateToolbarItem:, and validateUserInterfaceItem: methods exist, they will be used rather than using the action-specific methods. This approach allows us to migrate on a class-by-class basis to using action-specific valiation, since it retains the previous validation behavior for a class until we eliminate the monolithic methods.
*/

- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)item;
@end

@implementation NSObject (OATargetSelectionValidation)

typedef enum {
    OAMenuItemValidatorType,
    OAToolbarItemValidatorType,
    OAUserInterfaceItemValidatorType,
    OAValidatorTypeCount
} OAValidationType;

static NSMapTable *OAValidatorMaps[OAValidatorTypeCount]; // One SEL --> SEL map for each validator type.

- (SEL)_validatorSelectorFromAction:(SEL)action type:(OAValidationType)type;
{
    OBPRECONDITION(action);
    OBPRECONDITION(type < OAValidatorTypeCount);
    OBPRECONDITION([NSThread isMainThread]); // Our validator map mutation is not thread safe.
    
    static NSString * const OAMenuItemValidatorSuffix = @"MenuItem";
    static NSString * const OAToolbarItemValidatorSuffix = @"ToolbarItem";
    static NSString * const OAUserInterfaceItemValidatorSuffix = nil;
    static BOOL initialized = NO;
    
    if (!initialized) {
        NSPointerFunctionsOptions options = NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality;
        int defaultCapacity = 0; // Pointer collections will pick an appropriate small capacity on their own
        for (int i=0; i < OAValidatorTypeCount; i++) {
            NSMapTable *map = [[NSMapTable alloc] initWithKeyOptions:options valueOptions:options capacity:defaultCapacity];
            OAValidatorMaps[i] = map;
        }
        initialized = YES;
    }

    NSMapTable *validators = OAValidatorMaps[type];
    SEL validator = NSMapGet(validators, action);
    if (validator != NULL)
        return validator;

    NSString *suffix;
    switch (type) {
        case OAMenuItemValidatorType:
            suffix = OAMenuItemValidatorSuffix;
            break;
        case OAToolbarItemValidatorType:
            suffix = OAToolbarItemValidatorSuffix;
            break;
        default:
            suffix = OAUserInterfaceItemValidatorSuffix;
            break;
    }
    
    // e.g., @selector(toggleStatusCheckbox:) --> @"ToggleStatusCheckbox"
    NSString *selectorString = NSStringFromSelector(action);
#ifdef OMNI_ASSERTIONS_ON
    OBASSERT(selectorString.length > 0, @"Must have a non-empty selector string");
    NSRange firstColon = [selectorString rangeOfString:@":"];
    OBASSERT(firstColon.length == 1 && firstColon.location == [selectorString length] - 1); // sanity check for unary selector
#endif
    unichar *buffer = alloca(selectorString.length * sizeof(unichar));
    [selectorString getCharacters:buffer];
    NSUInteger actionNameLength = selectorString.length - 1; // -1 for trailing ':'
    BOOL leadingUnderscore = *buffer == '_';
    if (leadingUnderscore) {
        // skip leading underscore
        buffer++;
        actionNameLength--;
    }    
    if (*buffer >= 'a' && *buffer <= 'z')
        *buffer += 'A' - 'a';

    NSString *actionName = [[NSString alloc] initWithCharacters:buffer length:actionNameLength];
    NSString *validatorString = [[NSString alloc] initWithFormat:@"%@validate%@%@:", leadingUnderscore ? @"_" : @"", actionName, suffix ? suffix : @""];
    validator = NSSelectorFromString(validatorString);
    [validatorString release];
    [actionName release];

    NSMapInsert(validators, action, validator);
    
    return validator;
}

- (BOOL)_invokeValidatorForType:(OAValidationType)type item:(NSObject <NSValidatedUserInterfaceItem> *)item;
{
    if ([item action] == nil) {
#ifdef OMNI_ASSERTIONS_ON
        NSString *itemIdentifier = nil;
        NSString *label = nil;
        if ([item respondsToSelector:@selector(itemIdentifier)])
            itemIdentifier = [(id)item itemIdentifier];
        if ([item respondsToSelector:@selector(label)])
            label = [(id)item label];
        OBASSERT_NOT_REACHED(@"Don't expect to hit OATargetSelectionValidation without an action, but here we are with item: %@, itemIdentifier: %@, label: %@", item, itemIdentifier, label);
#endif
        // With no action, we can't make a downcall to any validate<Action> methods, but neither can the action be invoked. So…
        return NO;
    }
    
    SEL validator = [self _validatorSelectorFromAction:[item action] type:type];
    
    if ([self respondsToSelector:validator])
        return _validates(self, validator, item);
    
    if (type == OAMenuItemValidatorType || type == OAToolbarItemValidatorType) {
        // We checked for a menu item or toolbar item above and didn't find it, so check for generic user interface item
        validator = [self _validatorSelectorFromAction:[item action] type:OAUserInterfaceItemValidatorType];
        if ([self respondsToSelector:validator])
            return _validates(self, validator, item);
    }
    
    // Validator invocation happens twice. Once during the search for the target object and again for the actual validation decision. We reach this point in the code only when self implements the desired action but does not implement any validation. In that case, self should be the target and should validate the action.
    return YES;
}

static BOOL _overridesNSObjectCategoryMethod(id self, SEL validateSelector)
{
    Method categoryMethod = class_getInstanceMethod([NSObject class], validateSelector);
    OBASSERT_NOTNULL(categoryMethod);
    Method possiblyOverridingMethod = class_getInstanceMethod([self class], validateSelector);
    OBASSERT_NOTNULL(possiblyOverridingMethod);
    
    return possiblyOverridingMethod != categoryMethod;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    // Give priority to subclass overrides of validateUserInterfaceItem. (Already gave priorty to subclass overrides of validateMenuItem, since we wouldn't have gotten here in that case.)
    if ([item conformsToProtocol:@protocol(NSValidatedUserInterfaceItem)] && _overridesNSObjectCategoryMethod(self, @selector(validateUserInterfaceItem:)))
        return [self validateUserInterfaceItem:item];
    return [self _invokeValidatorForType:OAMenuItemValidatorType item:item];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
{
    // Give priority to subclass overrides of validateUserInterfaceItem. (Already gave priorty to subclass overrides of validateToolbarItem, since we wouldn't have gotten here in that case.)
    if ([item conformsToProtocol:@protocol(NSValidatedUserInterfaceItem)] && _overridesNSObjectCategoryMethod(self, @selector(validateUserInterfaceItem:)))
        return [self validateUserInterfaceItem:item];
    return [self _invokeValidatorForType:OAToolbarItemValidatorType item:item];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)item;
{
    return [self _invokeValidatorForType:OAUserInterfaceItemValidatorType item:(NSObject <NSValidatedUserInterfaceItem> *)item];
}

@end
