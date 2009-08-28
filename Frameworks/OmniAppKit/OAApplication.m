// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAApplication.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <Carbon/Carbon.h>
#import <ExceptionHandling/NSExceptionHandler.h>

#import "NSView-OAExtensions.h"
#import "NSWindow-OAExtensions.h"
#import "NSImage-OAExtensions.h"
#import "OAAppKitQueueProcessor.h"
#import "OAPreferenceController.h"
#import "OASheetRequest.h"

RCS_ID("$Id$")

NSString * const OAFlagsChangedNotification = @"OAFlagsChangedNotification";
NSString * const OAFlagsChangedQueuedNotification = @"OAFlagsChangedNotification (Queued)";

@interface OAApplication (Private)
+ (unsigned int)_currentModifierFlags;
- (void)processMouseButtonsChangedEvent:(NSEvent *)event;
+ (void)_activateFontsFromAppWrapper;
- (void)_scheduleModalPanelWithInvocation:(NSInvocation *)modalInvocation;
- (void)_rescheduleModalPanel:(NSTimer *)timer;
@end

static unsigned int launchModifierFlags;

@implementation OAApplication

+ (void)initialize;
{
    OBINITIALIZE;

    launchModifierFlags = [self _currentModifierFlags];
}

static NSImage *HelpIcon = nil;
static NSImage *CautionIcon = nil;

+ (void)setupOmniApplication;
{
    [OBObject self]; // Trigger +[OBPostLoader processClasses]
    
    // make these images available to client nibs and whatnot (retaining them so they stick around in cache).
    // Store them in ivars to avoid clang scan-build warnings.
    HelpIcon = [[NSImage imageNamed:@"OAHelpIcon" inBundleForClass:[OAApplication class]] retain];
    CautionIcon = [[NSImage imageNamed:@"OACautionIcon" inBundleForClass:[OAApplication class]] retain];
}

+ (NSApplication *)sharedApplication;
{
    static OAApplication *omniApplication = nil;

    if (omniApplication)
        return omniApplication;

    omniApplication = (id)[super sharedApplication];
    [self setupOmniApplication];
    return omniApplication;
}

- (void)dealloc;
{
    [exceptionCheckpointDate release];
    [windowsForSheets release];
    [sheetQueue release];
    [super dealloc];
}

- (void)finishLaunching;
{
    windowsForSheets = NSCreateMapTable(NSObjectMapKeyCallBacks, NSObjectMapValueCallBacks, 0);
    sheetQueue = [[NSMutableArray alloc] init];

    [[OFController sharedController] addObserver:(id)[OAApplication class]];
    [super finishLaunching];
}

- (void)run;
{
    exceptionCount = 0;
    exceptionCheckpointDate = [[NSDate alloc] init];
    do {
        NS_DURING {
            [super run];
            NS_VOIDRETURN;
        } NS_HANDLER {
            if (++exceptionCount >= 300) {
                if ([exceptionCheckpointDate timeIntervalSinceNow] >= -3.0) {
                    // 300 unhandled exceptions in 3 seconds: abort
                    fprintf(stderr, "Caught 300 unhandled exceptions in 3 seconds, aborting\n");
                    return;
                }
                [exceptionCheckpointDate release];
                exceptionCheckpointDate = [[NSDate alloc] init];
                exceptionCount = 0;
            }
            if (localException) {
                if (_appFlags._hasBeenRun)
                    [self handleRunException:localException];
                else
                    [self handleInitException:localException];
            }
        } NS_ENDHANDLER;
    } while (_appFlags._hasBeenRun);
}

- (void)beginSheet:(NSWindow *)sheet modalForWindow:(NSWindow *)docWindow modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;
{
    if ([NSAllMapTableValues(windowsForSheets) indexOfObjectIdenticalTo:docWindow] != NSNotFound) {
        // This window already has a sheet, we need to wait for it to finish
        [sheetQueue addObject:[OASheetRequest sheetRequestWithSheet:sheet modalForWindow:docWindow modalDelegate:modalDelegate didEndSelector:didEndSelector contextInfo:contextInfo]];
    } else {
        if (docWindow != nil)
            NSMapInsertKnownAbsent(windowsForSheets, sheet, docWindow);
        [super beginSheet:sheet modalForWindow:docWindow modalDelegate:modalDelegate didEndSelector:didEndSelector contextInfo:contextInfo];
    }
}

- (void)endSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode;
{
    NSWindow *docWindow;
    OASheetRequest *queuedSheet = nil;
    unsigned int requestIndex, requestCount;

    // Find the document window associated with the sheet we just ended
    docWindow = [[(NSWindow *)NSMapGet(windowsForSheets, sheet) retain] autorelease];
    NSMapRemove(windowsForSheets, sheet);
    
    // End this sheet
    [super endSheet:sheet returnCode:returnCode]; // Note: This runs the event queue itself until the sheet finishes retracting

    // See if we have another sheet queued for this document window
    requestCount = [sheetQueue count];
    for (requestIndex = 0; requestIndex < requestCount; requestIndex++) {
        OASheetRequest *request;

        request = [sheetQueue objectAtIndex:requestIndex];
        if ([request docWindow] == docWindow) {
            queuedSheet = [request retain];
            [sheetQueue removeObjectAtIndex:requestIndex];
            break;
        }
    }

    // Start the queued sheet
    [queuedSheet beginSheet];
    [queuedSheet release];
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

    NS_DURING {
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
                unsigned int modifierFlags = [event modifierFlags];
                BOOL justControlDown = (modifierFlags & NSControlKeyMask) && !(modifierFlags & NSShiftKeyMask) && !(modifierFlags & NSCommandKeyMask) && !(modifierFlags & NSAlternateKeyMask);
                
                if (justControlDown) {
                    NSView *contentView = [[event window] contentView];
                    NSView *viewUnderMouse = [contentView hitTest:[event locationInWindow]];
                    
                    if (viewUnderMouse != nil && [viewUnderMouse respondsToSelector:@selector(controlMouseDown:)]) {
                        [viewUnderMouse controlMouseDown:event];
                        NS_VOIDRETURN;
                    }
                }
                [super sendEvent:event];
                    
                break;
            }
                        
            default:
                [super sendEvent:event];
                break;
        }
    } NS_HANDLER {
        if ([[localException name] isEqualToString:NSAbortModalException] || [[localException name] isEqualToString:NSAbortPrintingException])
            [localException raise];
        [self handleRunException:localException];
    } NS_ENDHANDLER;

    [[OFScheduler mainScheduler] scheduleEvents]; // Ping the scheduler, in case the system clock changed
}

- (void)handleInitException:(NSException *)anException;
{
    id delegate;

    delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(handleInitException:)]) {
        [delegate handleInitException:anException];
    } else {
        NSLog(@"%@", [anException reason]);
    }
}

- (void)handleRunException:(NSException *)anException;
{
    // Redirect exceptions that get raised all the way out to -run back to -reportException:.  AppKit doesn't do this normally.  For example, if cmd-z (to undo) hits an exception, it will get re-raised all the way up to the top level w/o -reportException: getting called.  
    [self reportException:anException];
}

- (void)reportException:(NSException *)anException;
{
    if (currentRunExceptionPanel) {
        // Already handling an exception!
        NSLog(@"Ignoring exception raised while displaying previous exception: %@", anException);
        return;
    }

    @try {
        // Let OFController have a crack at this.  It may decide it wants to up and crash to report uncaught exceptions back to home base.  Strange, but we'll cover our bases here.  Do our alert regardless of the result, which is intended to control whether AppKit logs the message (but we are displaying UI, not just spewing to Console).
        // Pass NSLogUncaughtExceptionMask to simulate a totally uncaught exception, even though AppKit has a top-level handler.  This will cause OFController to get the exception two times; once with NSLogOtherExceptionMask (ignored, since it might be caught) and here with NSLogUncaughtExceptionMask (it turned out to not get caught).  One bonus is that since it is the same exception, the NSStackTraceKey is in place and has the location of the original exception raise point.
        [[OFController sharedController] exceptionHandler:[NSExceptionHandler defaultExceptionHandler] shouldLogException:anException mask:NSLogUncaughtExceptionMask];

        id delegate = [self delegate];
        if ([delegate respondsToSelector:@selector(handleRunException:)]) {
            [delegate handleRunException:anException];
        } else {
            NSLog(@"%@", [anException reason]);

            // Do NOT use NSRunAlertPanel.  If another exception happens while NSRunAlertPanel is going, the alert will be removed from the screen and the user will not be able to report the original exception!
            // NSGetAlertPanel will not have a default button if we pass nil.
            NSString *okString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniAppKit", [OAApplication bundle], "unhandled exception panel button");
            currentRunExceptionPanel = NSGetAlertPanel(nil, @"%@", okString, nil, nil, [anException reason]);
            [currentRunExceptionPanel center];
            [currentRunExceptionPanel makeKeyAndOrderFront:self];

            // The documentation for this method says that -endModalSession: must be before the NS_ENDHANDLER.
            NSModalSession modalSession = [self beginModalSessionForWindow:currentRunExceptionPanel];

            int ret = NSAlertErrorReturn;
            while (ret != NSAlertDefaultReturn) {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                @try {
                    // Might be NSAlertErrorReturn or NSRunContinuesResponse experimental evidence shows that it returns NSRunContinuesResponse if an exception was raised inside calling it (and it doesn't re-raise the exception since it returns).  We'll not assume this, though and we'll put this in a handler.
                    ret = [self runModalSession:modalSession];
                } @catch (NSException *localException) {
                    // Exception might get caught and passed to us by some other code (since this method is public).  So, our nesting avoidance is at the top of the method instead of in this handler block.
                    [self reportException:localException];
                    ret = NSAlertErrorReturn;
                }

                // Since we keep looping until the user clicks the button (rather than hiding the error panel at the first sign of trouble), we don't want to eat all the CPU needlessly.
                [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                [pool release];
            }
            
            [self endModalSession:modalSession];
            [currentRunExceptionPanel orderOut:nil];
            NSReleaseAlertPanel(currentRunExceptionPanel);
            currentRunExceptionPanel = nil;
        }
    } @catch (NSException *exc) {
        // Exception might get caught and passed to us by some other code (since this method is public).  So, our nesting avoidance is at the top of the method instead of in this handler block.
        [self reportException:exc];
    }
}

- (NSPanel *)currentRunExceptionPanel;
{
    return currentRunExceptionPanel;
}

- (NSWindow *)frontWindowForMouseLocation;
{
    NSArray *windows = [NSWindow windowsInZOrder];
    unsigned windowIndex, windowCount = [windows count];
    for (windowIndex = 0; windowIndex <  windowCount; windowIndex++) {
        NSWindow *window = [windows objectAtIndex:windowIndex];
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

- (unsigned int)currentModifierFlags;
{
    return [isa _currentModifierFlags];
}

- (BOOL)checkForModifierFlags:(unsigned int)flags;
{
    return ([self currentModifierFlags] & flags) != 0;
}

- (unsigned int)launchModifierFlags;
{
    return launchModifierFlags;
}

- (void)scheduleModalPanelForTarget:(id)modalController selector:(SEL)modalSelector userInfo:(id)userInfo;
{
    OBPRECONDITION(modalController != nil);
    OBPRECONDITION([modalController respondsToSelector:modalSelector]);
    
    // Create an invocation out of this request
    NSMethodSignature *modalSignature = [modalController methodSignatureForSelector:modalSelector];
    if (modalSignature == nil)
        return;
    NSInvocation *modalInvocation = [NSInvocation invocationWithMethodSignature:modalSignature];
    [modalInvocation setTarget:modalController];
    [modalInvocation setSelector:modalSelector];
    
    // Pass userInfo if modalSelector takes it
    if ([modalSignature numberOfArguments] > 2) // self, _cmd
        [modalInvocation setArgument:&userInfo atIndex:2];

    [self _scheduleModalPanelWithInvocation:modalInvocation];
}

// Prefix the URL string with "anchor:" if the string is the name of an anchor in the help files. Prefix it with "search:" to search for the string in the help book.
- (void)showHelpURL:(NSString *)helpURL;
{
    id applicationDelegate = [NSApp delegate];
    if ([applicationDelegate respondsToSelector:@selector(openAddressWithString:)]) {
        // We're presumably in OmniWeb, in which case we display our help internally
        NSString *omniwebHelpBaseURL = @"omniweb:/Help/";
        if([helpURL isEqualToString:@"anchor:SoftwareUpdatePreferences_Help"])
            helpURL = @"reference/preferences/Update.html";
        [applicationDelegate performSelector:@selector(openAddressWithString:) withObject:[omniwebHelpBaseURL stringByAppendingString:helpURL]];
    } else {
	NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *bookName = [mainBundle localizedStringForKey:@"CFBundleHelpBookName" value:@"" table:@"InfoPlist"];
        if (![bookName isEqualToString:@"CFBundleHelpBookName"]) {
            // We've got Apple Help.  First, make sure the help book is registered.  NSHelpManager would do this for us, but we use AHGotoPage, which it doesn't cover.
	    static BOOL helpBookRegistered = NO;
	    if (!helpBookRegistered) {
		helpBookRegistered = YES;
		NSURL *appBundleURL = [NSURL fileURLWithPath:[mainBundle bundlePath]];
		FSRef appBundleRef;
		if (!CFURLGetFSRef((CFURLRef)appBundleURL, &appBundleRef))
		    NSLog(@"Unable to get FSRef for app bundle URL of '%@' for bundle '%@'", appBundleURL, mainBundle);
		else
		    AHRegisterHelpBook(&appBundleRef);
	    }
	    
	    
            OSStatus err;
            NSRange range = [helpURL rangeOfString:@"search:"];
            if ((range.length != 0) || (range.location == 0))
                err = AHSearch((CFStringRef)bookName, (CFStringRef)[helpURL substringFromIndex:NSMaxRange(range)]);
            else {
                range = [helpURL rangeOfString:@"anchor:"];
                if ((range.length != 0) || (range.location == 0))
                    err = AHLookupAnchor((CFStringRef)bookName, (CFStringRef)[helpURL substringFromIndex:NSMaxRange(range)]);
                else
                    err = AHGotoPage((CFStringRef)bookName, (CFStringRef)helpURL, NULL);
            }
            
            if (err != noErr)	
                NSLog(@"Apple Help error: %d", err);
        } else {
            // We can let the system decide who to open the URL with
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:helpURL]];
        }
    }
}

// Application Support directory

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
    NSArray *paths = [self supportDirectoriesInDomain:domains];
    unsigned int pathCount = [paths count], pathIndex;
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:pathCount];
    for(pathIndex = 0; pathIndex < pathCount; pathIndex ++) {
        va_list varg;
        BOOL isDir;
        va_start(varg, subdir);
        NSString *component = subdir;
        NSString *path = [paths objectAtIndex:pathIndex];
        while(component != nil) {
            path = [path stringByAppendingPathComponent:component];
            component = va_arg(varg, NSString *);
        }
        va_end(varg);
        if ([filemgr fileExistsAtPath:path isDirectory:&isDir] && isDir)
            [result addObject:path];
    }
    return result;
}

- (NSString *)writableSupportDirectoryInDomain:(NSSearchPathDomainMask)domains withComponents:(NSString *)subdir, ...;
{
    NSArray *paths = [self supportDirectoriesInDomain:domains];
    unsigned int pathIndex, pathCount = [paths count];
    NSFileManager *filemgr = [NSFileManager defaultManager];
    
    for(pathIndex = 0; pathIndex < pathCount; pathIndex++) {
        va_list varg;
        va_start(varg, subdir);
        NSString *component = subdir;
        NSString *path = [paths objectAtIndex:pathIndex];
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

// Actions

- (IBAction)closeAllMainWindows:(id)sender;
{
    NSArray *windows;
    unsigned int windowIndex, windowCount;
    
    windows = [[NSArray alloc] initWithArray:[self orderedWindows]];
    windowCount = [windows count];
    for (windowIndex = 0; windowIndex < windowCount; windowIndex++) {
        NSWindow *window;

        window = [windows objectAtIndex:windowIndex];
        if ([window canBecomeMainWindow])
            [window performClose:nil];
    }
    [windows release];
}

- (IBAction)cycleToNextMainWindow:(id)sender;
{
    NSWindow *mainWindow;
    NSArray *orderedWindows;
    unsigned int windowIndex, windowCount;
    
    mainWindow = [NSApp mainWindow];
    orderedWindows = [NSApp orderedWindows];
    windowCount = [orderedWindows count];
    for (windowIndex = 0; windowIndex < windowCount; windowIndex++) {
        NSWindow *window;

        window = [orderedWindows objectAtIndex:windowIndex];
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
    NSWindow *mainWindow;
    NSArray *orderedWindows;
    unsigned int windowIndex;
    
    mainWindow = [NSApp mainWindow];
    orderedWindows = [NSApp orderedWindows];
    windowIndex = [orderedWindows count];
    while (windowIndex--) {
        NSWindow *window;

        window = [orderedWindows objectAtIndex:windowIndex];
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

static NSArray *overrideWindows = nil;

- (NSArray *)windows;
{
    if (overrideWindows)
        return overrideWindows;
    return [super windows];
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

// OFController observer informal protocol

+ (void)controllerStartedRunning:(OFController *)controller;
{
    [self _activateFontsFromAppWrapper];
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

#pragma mark AppleScript

static void _addPreferenceForKey(const void *value, void *context)
{
    NSString *key = (NSString *)value;
    NSMutableArray *prefs = (NSMutableArray *)context;
    
    OFPreference *pref = [OFPreference preferenceForKey:key];
    OBASSERT(pref);
    if (pref)
        [prefs addObject:pref];
}

static NSComparisonResult _compareByKey(id obj1, id obj2, void *context)
{
    return [[obj1 key] compare:[obj2 key]];
}

- (NSArray *)scriptPreferences;
{
    NSMutableArray *prefs = [NSMutableArray array];
    [[OFPreference registeredKeys] applyFunction:_addPreferenceForKey context:prefs];
    [prefs sortUsingFunction:_compareByKey context:NULL];
    return prefs;
}

- (OFPreference *)valueInScriptPreferencesWithUniqueID:(NSString *)identifier;
{
    return [OFPreference preferenceForKey:identifier];
}

@end

@implementation OAApplication (Private)

+ (unsigned int)_currentModifierFlags;
{
    unsigned int flags = 0;
    UInt32 currentKeyModifiers = GetCurrentKeyModifiers();
    if (currentKeyModifiers & cmdKey)
        flags |= NSCommandKeyMask;
    if (currentKeyModifiers & shiftKey)
        flags |= NSShiftKeyMask;
    if (currentKeyModifiers & optionKey)
        flags |= NSAlternateKeyMask;
    if (currentKeyModifiers & controlKey)
        flags |= NSControlKeyMask;
    
    return flags;
}

- (void)processMouseButtonsChangedEvent:(NSEvent *)event;
{
    mouseButtonState = [event data2];
}

+ (void)_activateFontsFromAppWrapper;
{
    FSRef myFSRef;
    
    NSString *fontsDirectory = [[[[NSBundle mainBundle] resourcePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Fonts"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:fontsDirectory])
        if (FSPathMakeRef((UInt8 *)[fontsDirectory fileSystemRepresentation], &myFSRef, NULL) == noErr) {
            ATSFontActivateFromFileReference(&myFSRef, kATSFontContextLocal, kATSFontFormatUnspecified, NULL, kATSOptionFlagsDefault, NULL);
        }
}

- (void)_scheduleModalPanelWithInvocation:(NSInvocation *)modalInvocation;
{
    OBPRECONDITION(modalInvocation != nil);
    
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    if ([[runLoop currentMode] isEqualToString:NSModalPanelRunLoopMode]) {
        NSTimer *timer = [NSTimer timerWithTimeInterval:0.0 target:self selector:@selector(_rescheduleModalPanel:) userInfo:modalInvocation repeats:NO];
        [runLoop addTimer:timer forMode:NSDefaultRunLoopMode];
    } else {
        [modalInvocation invoke];
    }
}

- (void)_rescheduleModalPanel:(NSTimer *)timer;
{
    OBPRECONDITION(timer != nil);
    
    NSInvocation *invocation = [timer userInfo];
    OBASSERT(invocation != nil);
    
    [self _scheduleModalPanelWithInvocation:invocation];
}

@end
