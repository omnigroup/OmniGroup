// Copyright 1998-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFController.h>

#import <ExceptionHandling/NSExceptionHandler.h>
#import <OmniBase/system.h>
#import <OmniBase/OBBacktraceBuffer.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFBacktrace.h>
#import <OmniFoundation/OFInvocation.h>
#import <OmniFoundation/OFObject-Queue.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFWeakReference.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$")

@interface OFController ()
@property (nonatomic, assign) OFControllerStatus status;
@end

typedef OFWeakReference <id <OFControllerStatusObserver>> *OFControllerStatusObserverReference;

/*" OFController is used to represent the current state of the application and to receive notifications about changes in that state. "*/
@implementation OFController
{
    OFControllerStatus _status;
    NSLock *observerLock;
    NSMutableArray <OFControllerStatusObserverReference> *_observerReferences; // OFWeakReferences holding the observers
    NSMutableSet *postponingObservers;
    NSMutableDictionary *_queues;
    
    OFPreference *_crashOnAssertionOrUnhandledExceptionPreference;

#if USE_NOTIFICATION_CENTER
    NSLock *_notificationOwnersLock;
    NSMutableArray *_locked_notificationOwnerReferences;
#endif
}

static OFController *sharedController = nil;
static BOOL CrashOnAssertionOrUnhandledException = NO; // Cached so we can get this w/in the handler w/o calling into ObjC (since it might be unsafe)
static BOOL LogExceptionHandlerShouldLogException = NO;
static int CrashShouldExitWithCode = 0; // If this is set, OFCrashImmediately will exit with this code.
static BOOL UseAbortToCrash = NO;


#ifdef OMNI_ASSERTIONS_ON
static void _OFControllerCheckTerminated(void)
{
    @autoreleasepool {
        // Make sure that applications that use OFController actually call its -willTerminate.
        if (OFIsRunningUnitTests()) {
            // We need to skip this check for xctest host apps since +[XCTestProbe runTests:] just calls exit() rather than -terminate:.
        } else {
            OBASSERT(!sharedController || sharedController->_status == OFControllerStatusTerminating || sharedController->_status == OFControllerStatusNotInitialized);
        }
    }
}
#endif

// If we are running a bundled app, this will return the main bundle.  Otherwise, if we are running unit tests, this will return the unit test bundle.
+ (NSBundle *)controllingBundle;
{
    return OFControllingBundle();
}

+ (BOOL)isRunningUnitTests;
{
    return OFIsRunningUnitTests();
}

static NSString *ControllerClassName(NSBundle *bundle)
{
    return [[bundle infoDictionary] objectForKey:@"OFControllerClass"];
}

+ (instancetype)sharedController;
{
    // Don't set up the shared controller in +initialize.  The issue is that the superclass +initialize will always get called first and the fallback code to use the receiving class will always get OFController.  In a command line tool you don't have a bundle plist, but you can subclass OFController and make sure +sharedController is called on it first.
    if (sharedController == nil) {
        static BOOL _stillSettingUpSharedController = YES;
        assert(_stillSettingUpSharedController == YES);

        // When running unit tests, the main bundle won't be the test bundle.
        NSString *controllerClassName = ControllerClassName([self controllingBundle]);
        
        if ([NSString isEmptyString:controllerClassName]) {
            // This can happen, for example, when the unit test bundle doesn't specify a controller class, but is using a host app rather than plain xctest.
            controllerClassName = ControllerClassName([NSBundle mainBundle]);
        }
        
        Class controllerClass;
        if ([NSString isEmptyString:controllerClassName])
            controllerClass = self;
        else {
            controllerClass = NSClassFromString(controllerClassName);
            if (controllerClass == Nil) {
                NSLog(@"OFController: no such class \"%@\"", controllerClassName);
                controllerClass = self;
            }
        }
        
        OFController *allocatedController = [controllerClass alloc]; // Special case; make sure assignment happens before call to -init so that it will actually initialize this instance
        if (sharedController == nil) {
            sharedController = allocatedController;
            OFController *initializedController = [allocatedController init];
            assert(sharedController == initializedController);
        } else {
            // Allocating a controller can recursively reenter this code (because it triggers class initialization which can register with OFController).  That means that by the time the first +alloc finishes, we may have already completely set up a different shared controller which we should continue to use instead of blindly replacing it.
            [allocatedController release];
            return sharedController;
        }

        assert(_stillSettingUpSharedController == YES);
        _stillSettingUpSharedController = NO;
        
        // For one-time setup that we don't want to do in -init if we are going to be a losing instance.
        [sharedController becameSharedController];
    }

    assert([sharedController isKindOfClass:self]);
    
    return sharedController;
}

- (id)init;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Ensure that +sharedController and nib loading produce a single instance
    OBPRECONDITION(!sharedController || [self class] == [sharedController class]); // Need to set OFControllerClass otherwise
    
    if (self != sharedController) {
        // Nib loading calls +alloc/-init directly.  Make sure that it gets the shared instance.
        //
        // N.B. Create the shared instance before releasing ourselves. This ensures that the address isn't re-used. Subclasses rely in detecting whether self has been reassigned in order to determine if they should do their own init. If we release first, the allocator may (and does!) reuse that block, and we end up re-initializing the shared instance.
        //
        // An alternate solution would be to ensure that subclasses do not override init, and provide an overridable method such as -initializeSharedInstance where they can set up their private state.  
        
        OBAnalyzerNotReached(); // clang-sa from Xcode 4.6 warns about this pattern.
        
        id sharedInstance = [OFController sharedController];
	[self release];
	return [sharedInstance retain];
    }
        
    // We are setting up the shared instance in +sharedController
    if (!(self = [super init]))
        return nil;

    // Illegal instructions/memory accesses with NSExceptionHandler enabled cause an infinite spin on Big Sur, but abort works. In earlier OSes, abort *didn't* work.
    UseAbortToCrash = [OFVersionNumber isOperatingSystemBigSurOrLater];

    // We can't depend on the default being registered here since we are early in startup. Default to on, but then cache the actual value in -didInitialize, once things get registered.
    CrashOnAssertionOrUnhandledException = YES;
    CrashShouldExitWithCode = [[[NSProcessInfo processInfo] environment][@"OFCrashShouldExitWithCode"] intValue];

    // Debugging support which is expected to be a defaults write, not a OFPreference registered default
    LogExceptionHandlerShouldLogException = [[NSUserDefaults standardUserDefaults] boolForKey:@"LogExceptionHandlerShouldLogException"];
    
    NSExceptionHandler *handler = [NSExceptionHandler defaultExceptionHandler];
    [handler setDelegate:self];
    [handler setExceptionHandlingMask:[self exceptionHandlingMask]];
    
    // NSAssertionHandler's documentation says this is the way to customize assertion handling
    [[[NSThread currentThread] threadDictionary] setObject:self forKey:@"NSAssertionHandler"];
    
    observerLock = [[NSLock alloc] init];
    _status = OFControllerStatusNotInitialized;
    _observerReferences = [[NSMutableArray alloc] init];
    postponingObservers = [[NSMutableSet alloc] init];
    
#if USE_NOTIFICATION_CENTER
    _notificationOwnersLock = [[NSLock alloc] init];
    _locked_notificationOwnerReferences = [[NSMutableArray alloc] init];
#endif
    
#ifdef OMNI_ASSERTIONS_ON
    atexit(_OFControllerCheckTerminated);
#endif
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (_crashOnAssertionOrUnhandledExceptionPreference) {
        [OFPreference removeObserver:self forPreference:_crashOnAssertionOrUnhandledExceptionPreference];
        [_crashOnAssertionOrUnhandledExceptionPreference release];
    }
    
    [_observerReferences release];
    [postponingObservers release];
    [_queues release];
    
#if USE_NOTIFICATION_CENTER
    [_locked_notificationOwnerReferences release];
    [_notificationOwnersLock release];
#endif
    
    [super dealloc];
}

#if USE_NOTIFICATION_CENTER
#ifdef OMNI_ASSERTIONS_ON
static void (*originalUserNotificationCenterSetDelegate)(id self, SEL _cmd, id object) = NULL;

static void _replacement_userNotificationCenterSetDelegate(id self, SEL _cmd, id object)
{
    OBASSERT_NOT_REACHED("The OAController instance should be the delgate of NSUserNotificationCenter. Use -[OAController addNotificationOwner:] instead.");
}
#endif
#endif

- (void)becameSharedController;
{
#if USE_NOTIFICATION_CENTER
    OBASSERT([NSUserNotificationCenter defaultUserNotificationCenter].delegate == nil, "NSUserNotificationCenter delegate was already set to %@, but will be clobbered by %@", [NSUserNotificationCenter defaultUserNotificationCenter].delegate, self);
    
    NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
    center.delegate = self;
    
    // Once we've set the delegate to us, replace the method with one that will assert if other code tries to mess it up.
#ifdef OMNI_ASSERTIONS_ON
    // The returned instance is of a concrete subclass; the superclass doesn't even implement -setDelegate:.
    originalUserNotificationCenterSetDelegate = (typeof(originalUserNotificationCenterSetDelegate))OBReplaceMethodImplementation([center class], @selector(setDelegate:), (IMP)_replacement_userNotificationCenterSetDelegate);
#endif
#endif
}

- (OFControllerStatus)status;
{
    OBPRECONDITION([NSThread isMainThread]);

    return _status;
}

- (void)setStatus:(OFControllerStatus)newStatus;
{
    OBPRECONDITION([NSThread isMainThread]);

    _status = newStatus;
    [self _runQueues];
}

- (NSUInteger)_locked_indexOfObserver:(id)observer possiblyDealloced:(BOOL)isPossiblyDealloced;
{
    return [_observerReferences indexOfObjectPassingTest:^BOOL(OFControllerStatusObserverReference ref, NSUInteger idx, BOOL *stop) {
        return [ref referencesObject:(OB_BRIDGE void *)observer] || (isPossiblyDealloced && [ref referencesDeallocatingObjectPointer:observer]);
    }];
}

/*" Subscribes the observer to a set of notifications based on the methods that it implements in the OFControllerStatusObserver informal protocol.  Classes can register for these notifications in their OBDidLoad actions (and those actions probably shouldn't do much else, since defaults aren't yet registered). "*/
- (void)addStatusObserver:(id <OFControllerStatusObserver>)observer;
{
    OBPRECONDITION(observer != nil);
    
    [observerLock lock];
    
    OBASSERT([self _locked_indexOfObserver:observer possiblyDealloced:NO] == NSNotFound, "Adding the same observer twice is very likely a bug");
    
    OFControllerStatusObserverReference ref = [[OFWeakReference alloc] initWithObject:observer];
    [_observerReferences addObject:ref];
    [ref release];
        
    [observerLock unlock];
}


/*" Unsubscribes the observer to a set of notifications based on the methods that it implements in the OFControllerStatusObserver informal protocol. "*/
- (void)removeStatusObserver:(id <OFControllerStatusObserver>)observer;
{
    [observerLock lock];
    
    NSUInteger observerIndex = [self _locked_indexOfObserver:observer possiblyDealloced:YES];
    OBASSERT(observerIndex != NSNotFound, "Removing an observer that wasn't added is very likely a bug");
    if (observerIndex != NSNotFound)
        [_observerReferences removeObjectAtIndex:observerIndex];
    
    [observerLock unlock];
}

/*" Enqueues a message to be sent to an object when the controller enters a specific state. If the controller is already in that state (or a later state), then the message will be sent immediately. Unlike the observer protocol, this method retains the receiver until the message is sent. "*/
- (void)queueSelector:(SEL)message forObject:(NSObject *)receiver whenStatus:(OFControllerStatus)state;
{
    if (!receiver)
        return;
    
    if (state <= _status) {
        OBSendVoidMessage(receiver, message);
    } else {
        OFInvocation *queueEntry = [[OFInvocation alloc] initForObject:receiver selector:message];
        [self queueInvocation:queueEntry whenStatus:state];
        [queueEntry release];
    }
}

/*" Enqueues an invocation to occur when the controller enters a specific state. If the controller is already in that state (or a later state), then the action will happen immediately. Unlike the observer protocol, this method retains the receiver (via the invocation) until the message is sent. "*/
- (void)queueInvocation:(OFInvocation *)action whenStatus:(OFControllerStatus)state;
{
    if (action == nil)
        return;

    [self performBlock:^{ [action invoke]; } whenStatus:state];
}

- (void)performBlock:(void (^)(void))block whenStatus:(OFControllerStatus)state;
{
    if (block == NULL)
        return;
    
    [observerLock lock];
    if (state <= _status) {
        [observerLock unlock];
        block();
    } else {
        NSNumber *key = [NSNumber numberWithInteger:state];
        NSMutableArray *queue = [_queues objectForKey:key];
        if (queue == nil) {
            if (_queues == nil)
                _queues = [[NSMutableDictionary alloc] init];
            queue = [NSMutableArray array];
            [_queues setObject:queue forKey:key];
        }

        id copiedBlock = [block copy];
        [queue addObject:copiedBlock];
        [copiedBlock release];
        
        [observerLock unlock];
    }
}

/*" The application should call this once after it is initialized.  In AppKit applications, this should be called from -applicationWillFinishLaunching:. "*/
- (void)didInitialize;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_status == OFControllerStatusNotInitialized);
    
    // See -init for why we delay this work
    {
        static NSString * const CrashOnAssertionOrUnhandledExceptionKey = @"OFCrashOnAssertionOrUnhandledException";
        OBPRECONDITION([[OFPreference registeredKeys] member:CrashOnAssertionOrUnhandledExceptionKey]);
        
        _crashOnAssertionOrUnhandledExceptionPreference = [[OFPreference preferenceForKey:CrashOnAssertionOrUnhandledExceptionKey] retain];
        [OFPreference addObserver:self selector:@selector(_crashOnAssertionPreferenceChanged:) forPreference:_crashOnAssertionOrUnhandledExceptionPreference];
        [self _crashOnAssertionPreferenceChanged:nil];
    }

    self.status = OFControllerStatusInitialized;
    [self _makeObserversPerformSelector:@selector(controllerDidInitialize:)];
}

/*" The application should call this once after calling -didInitialize.  In AppKit applications, this should be called from -applicationDidFinishLaunching:. "*/
- (void)startedRunning;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_status == OFControllerStatusInitialized);
    
    self.status = OFControllerStatusRunning;
    [self _makeObserversPerformSelector:@selector(controllerStartedRunning:)];
}
    
/*" The application should call this when a termination request has been received.  If YES is returned, the termination can proceed (i.e., the caller should call -willTerminate) next. "*/
- (OFControllerTerminateReply)requestTermination;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_status <= OFControllerStatusRunning);
    
    self.status = OFControllerStatusRequestingTerminate;
    
    for (id anObserver in [self _observersSnapshot]) {
        if ([anObserver respondsToSelector:@selector(controllerRequestsTerminate:)]) {
            @try {
                [anObserver controllerRequestsTerminate:self];
            } @catch (NSException *exc) {
                NSLog(@"Ignoring exception raised during %s[%@ controllerRequestsTerminate:]: %@", OBPointerIsClass(anObserver) ? "+" : "-", OBShortObjectDescription(anObserver), [exc reason]);
            }
        }
        
        // Break if the termination was cancelled
        if (_status == OFControllerStatusRunning)
            break;
    }

    if (_status != OFControllerStatusRunning && [postponingObservers count] > 0)
        self.status = OFControllerStatusPostponingTerminate;

    switch (_status) {
        case OFControllerStatusRunning:
            return OFControllerTerminateCancel;
        case OFControllerStatusRequestingTerminate:
            self.status = OFControllerStatusTerminating;
            return OFControllerTerminateNow;
        case OFControllerStatusPostponingTerminate:
            return OFControllerTerminateLater;
        default:
            OBASSERT_NOT_REACHED("Can't return from OFControllerStatusRunning to an earlier state");
            return OFControllerTerminateNow;
    }
}

/*" This method can be called during a -controllerRequestsTerminate: method when an object wishes to cancel the termination (typically in response to a user pressing the "Cancel" button on a Save panel). "*/
- (void)cancelTermination;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    switch (_status) {
        case OFControllerStatusRequestingTerminate:
            self.status = OFControllerStatusRunning;
            break;
        case OFControllerStatusPostponingTerminate:
            [self gotPostponedTerminateResult:NO];
            self.status = OFControllerStatusRunning;
            break;
        default:
            break;
    }
    
    if (self.status == OFControllerStatusRunning) {
        [self _makeObserversPerformSelector:@selector(controllerCancelledTermnation:)];
    }
}

- (void)postponeTermination:(id)observer;
{
    OBPRECONDITION([NSThread isMainThread]);

    [postponingObservers addObject:observer];
}

- (void)continuePostponedTermination:(id)observer;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION([postponingObservers containsObject:observer]);
    
    [postponingObservers removeObject:observer];
    if ([postponingObservers count] == 0) {
        [self gotPostponedTerminateResult:(_status != OFControllerStatusRunning)];
    } else if ((_status == OFControllerStatusRequestingTerminate || _status == OFControllerStatusPostponingTerminate || _status == OFControllerStatusTerminating)) {
        [self _makeObserversPerformSelector:@selector(controllerRequestsTerminate:)];
    }
}

- (void)willTerminate;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_status == OFControllerStatusTerminating); // We should have requested termination and not had it cancelled or postponed.
    
    [self _makeObserversPerformSelector:@selector(controllerWillTerminate:)];
}

- (void)gotPostponedTerminateResult:(BOOL)isReadyToTerminate;
{
    if (isReadyToTerminate)
        self.status = OFControllerStatusTerminating;
}

// Allow subclasses to override this
- (unsigned int)exceptionHandlingMask;
{
#ifdef DEBUG
    return NSLogUncaughtExceptionMask|NSLogUncaughtSystemExceptionMask|NSLogUncaughtRuntimeErrorMask|NSLogTopLevelExceptionMask|NSLogOtherExceptionMask;
#else
    return NSLogUncaughtExceptionMask|NSLogUncaughtSystemExceptionMask|NSLogUncaughtRuntimeErrorMask|NSLogTopLevelExceptionMask;
#endif
}

static void OFCrashImmediately(void)
{
    if (OFIsRunningUnitTests()) {
        // When running unit tests on our build server, with a loopback ssh connection to allow opening keychains, xctest can hang on a crash of a unit test (it's trying to connect to Xcode it seems).
        exit(1);
    }
    if (CrashShouldExitWithCode != 0) {
        exit(CrashShouldExitWithCode);
    }

    OBAnalyzerNotReached();

    if (UseAbortToCrash) {
        abort();
    }

    unsigned int *bad = (unsigned int *)sizeof(unsigned int);
    bad[-1] = 0; // Crash immediately; crazy approach is to defeat the clang error about dereferencing NULL, which is the point!
}

- (void)crashWithReport:(NSString *)report;
{
    // OmniCrashCatcher overrides this method to do something more useful
    NSLog(@"Crashing with report:\n%@", report);
    
    OFCrashImmediately();
}

static NSString *OFSymbolicBacktrace(NSException *exception) {

    NSString *symbolicBacktrace = nil;

    // Try the system method
    NSArray *symbols = [exception callStackSymbols];
    if ([symbols count] > 0) {
        symbolicBacktrace = [symbols componentsJoinedByString:@"\n"];
    }

    // Otherwise, look for the info key and do it ourselves...
    if (!symbolicBacktrace) {
        NSString *numericBacktrace = [[exception userInfo] objectForKey:NSStackTraceKey];
        if (![NSString isEmptyString:numericBacktrace])
            symbolicBacktrace = [OFCopySymbolicBacktraceForNumericBacktrace(numericBacktrace) autorelease];
    }

    if (!symbolicBacktrace) {
        symbolicBacktrace = @"No numeric backtrace found";
    }

    return symbolicBacktrace;
}

- (void)crashWithException:(NSException *)exception mask:(NSUInteger)mask;
{
    NSString *symbolicBacktrace = OFSymbolicBacktrace(exception);
    NSString *report = [NSString stringWithFormat:@"Exception raised:\n---------------------------\nMask: 0x%08lx\nName: %@\nReason: %@\nInfo:\n%@\nBacktrace:\n%@\n---------------------------",
                        mask, [exception name], [exception reason], [exception userInfo], symbolicBacktrace];

    [self crashWithReport:report];
}

- (BOOL)shouldLogException:(NSException *)exception mask:(NSUInteger)aMask;
{
    if ([exception.name isEqual:@"_XCTSkipFailureException"]) {
        return NO;
    }
    
    if ([self _isDictionaryDefinitionException:exception]) {
        return NO;
    }

    return YES;
}

- (BOOL)_isDictionaryDefinitionException:(NSException *)exception;
{
    // <omnicrashsorter:///ticket/1321506> (Crash in OmniOutliner 4.1.4 reported by Chenjie Gu)
    // Apple's show-definition feature (ctrl-cmd-D) throws an exception in some cases. Those exceptions should be ignored. It's Apple’s bug.
    // One way to reproduce:
    //   1. Create a new empty headline in Outliner, Focus, or Plan.
    //   2. Type a single space.
    //   3. Move the mouse pointer over the space. Leave the insertion point where it is.
    //   4. Type ctrl-cmd-D.
    // You get an NSRangeException, and the backtrace includes specific methods in either NSTextView or LUAccessibility (part of the Lookup module).
    // Filed as <rdar://19942655>

    if (![exception.name isEqualToString:NSRangeException]) {
        return NO;
    }

    NSString *symbolicBacktrace = OFSymbolicBacktrace(exception);
    NSArray *matchStrings = @[@"-[NSTextView _showDefinitionForAttributedString:characterIndex:range:options:baselineOriginProvider:]", @"-[NSTextView showDefinitionForAttributedString:range:options:baselineOriginProvider:]", @"-[LUAccessibilityTextAccessor termForRange:textOrigin:language:partOfSpeech:]"];
    for (NSString *oneMatchString in matchStrings) {
        if ([symbolicBacktrace containsString:oneMatchString]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark -
#pragma mark NSAssertionHandler replacement

- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,...;
{
    va_list args;
    va_start(args, format);
    [self handleFailureInMethod:selector object:object file:fileName lineNumber:line format:format arguments:args];
    va_end(args);
}

- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,...;
{
    va_list args;
    va_start(args, format);
    [self handleFailureInFunction:functionName file:fileName lineNumber:line format:format arguments:args];
    va_end(args);
}

// The real stuff is here so that subclassers can override these points instead of the '...' versions (which make it impossible to call super w/o silly contortions).
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line format:(NSString *)format arguments:(va_list)args;
{
    static BOOL handlingAssertion = NO;
    if (handlingAssertion)
	return; // Skip since we apparently screwed up
    handlingAssertion = YES;

    OBRecordBacktrace(NULL, OBBacktraceBuffer_NSAssertionFailure);
    
    if (!CrashOnAssertionOrUnhandledException) {
	NSString *numericTrace = OFCopyNumericBacktraceString(0);
	NSString *symbolicTrace = OFCopySymbolicBacktraceForNumericBacktrace(numericTrace);
	[numericTrace release];
        
	NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
	
	NSLog(@"Assertion Failed:\n---------------------------\nObject: %@\nSelector: %@\nFile: %@\nLine: %d\nDescription: %@\nStack Trace:\n%@\n---------------------------",
	      OBShortObjectDescription(object), NSStringFromSelector(selector), fileName, line, description, symbolicTrace);
#if defined(OMNI_ASSERTIONS_ON)
        OBAssertFailed([description UTF8String]); // In case there is a breakpoint in the debugger for assertion failures.
#endif
	[description release];
	[symbolicTrace release];
    } else {
        NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
        NSString *report = [NSString stringWithFormat:@"Assertion Failed:\n---------------------------\nObject: %@\nSelector: %@\nFile: %@\nLine: %d\nDescription: %@\n---------------------------",
                            OBShortObjectDescription(object), NSStringFromSelector(selector), fileName, line, description];
        [description release];
        
        BOOL crash = YES;
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define IGNORE_CRASH(clsName, sel) if (selector == (sel) && [NSStringFromClass([object class]) isEqualToString:(clsName)]) crash = NO;
        // On the WWDC beta of High Sierra, opening the print panel on a system with a Touch Bar raises an exception because PMPrintWindowController is returning an NSPopoverTouchBarItem with an identifier of "com.apple.print.touchbar.printerButtons" when asked to create an item with identifier "com.apple.print.touchbar.printerPopoverItem". See bug:///145271 (Frameworks-Mac Regression: [macOS High Sierra] Crash when opening the print dialog).
        IGNORE_CRASH(@"NSTouchBar", @selector(itemForIdentifier:))

        // NSRemoteSavePanel sometimes fails an assertion when it turns on the "hide extension" checkbox on by itself. Seems harmless?
        IGNORE_CRASH(@"NSRemoteSavePanel", @selector(connection:didReceiveRequest:))

        // Save as PDF (maybe just when the suggested name has 'foo.ext' and you confirm the alert asking to switch to just '.pdf'.
        IGNORE_CRASH(@"NSRemoteView", @selector(updateWindowEdgeResizingRegion))

        // Bringing up security options for print-to-pdf in a sandboxed app causes a harmless failure. <bug:///87161>
        IGNORE_CRASH(@"NSAccessoryWindow", @selector(sendEvent:))

        IGNORE_CRASH(@"NSVBSavePanel", @selector(_attachSandboxExtensions:toURL:orURLS:))
        IGNORE_CRASH(@"NSVBSavePanel", @selector(_attachSandboxExtension:toURL:)) // saving a stencil? <bug:///135373>

        IGNORE_CRASH(@"NSRemoteView", @selector(_evaluateKeyness:forWindow:))

        // <bug:///142474> (Mac-OmniGraffle Crasher: [needs repro] [7.11.1] -[NSDocument(NSDocumentSaving) _runModalSavePanelForSaveOperation:delegate:didSaveSelector:contextInfo:])
        IGNORE_CRASH(@"NSRemoteViewMarshal", @selector(dealloc))

        // bug:///139696 (Mac-OmniOutliner Crasher: Crash typing multibyte characters into save panel name field on touch bar MBP)
        IGNORE_CRASH(@"NSRemoteView", @selector(_showTouchBarPopover:fromItem:wthOverlayIdentifier:withCloseButton:withControlStrip:));

        IGNORE_CRASH(@"NSLayerCentricRemoteView", @selector(maintainFirstResponder:inDirection:)) // unknown, <bug:///135373>


        // The next two selectors are brought to you by bug:///130794 (Mac-OmniPlan Crasher: Force Click Related Crash: crash_info (AppKit): "Performing @selector(_forceClickMonitorDidChange:) from sender NSForceClickMonitor 0xdeaddead")
        IGNORE_CRASH(@"LULookupDefinitionModule", @selector(_termWithOrigin:options:forRange:inString:withOptions:originProvider:inView:))
        IGNORE_CRASH(@"LUTextAccessor", @selector(rangeOfTermInString:containingOffset:language:partOfSpeech:))

        /*
         bug reporter #35995767
         <bug:///151468> (Mac-OmniGraffle Crasher: -[NSView(NSInternal) _enableNeedsDisplayInRectNotifications] (in AppKit))
         
         Assertion Failed:
         ---------------------------
         Object: <GraphicView:0x1053c4a00>
         Selector: _enableNeedsDisplayInRectNotifications
         File: /BuildRoot/Library/Caches/com.apple.xbs/Sources/AppKit/AppKit-1561.10.101/AppKit.subproj/NSView.m
         Line: 18288
         Description: Unbalanced needs display in rect posting count.
         ---------------------------
         */
        IGNORE_CRASH(@"GraphicView", @selector(_enableNeedsDisplayInRectNotifications))
        IGNORE_CRASH(@"GraphicView", @selector(_disableNeedsDisplayInRectNotifications))
        
        /*
         bug reporter #37711145
         <bug:///154713> (Mac-OmniFocus Crasher: Crash resizing the attachments window)
         <bug:///157567> (Mac-OmniFocus Crasher: High Sierra: Crash resizing OmniOutliner document column mapping import window)
         Same as above, but in NSTableView/NSOutlineView instead of our own view class
         Seems fixed on Mojave
         */
        if (![OFVersionNumber isOperatingSystemMojaveOrLater]) {
            IGNORE_CRASH(@"NSOutlineView", @selector(_enableNeedsDisplayInRectNotifications))
            IGNORE_CRASH(@"NSOutlineView", @selector(_disableNeedsDisplayInRectNotifications))
            IGNORE_CRASH(@"NSTableView", @selector(_enableNeedsDisplayInRectNotifications))
            IGNORE_CRASH(@"NSTableView", @selector(_disableNeedsDisplayInRectNotifications))
        }
        
        /* bug reporter #37539192 <bug:///155090> (Mac-OmniGraffle Crasher: Crash trying to Add People to a file recently saved to iCloud on a Touchbar Mac) */
        IGNORE_CRASH(@"SHKRemoteView", @selector(_mapPerProcessIdentifiers:of:))

        // <bug:///154432> (Mac-OmniGraffle Crasher: High Sierra: Crash contacting Omni from a full screen window)
        IGNORE_CRASH(@"NSToolbarFullScreenWindow", @selector(startRectForSheet:))

        // <bug:///159503> (Mac-OmniGraffle Crasher: [needs repro] [7.7.1] -[GraphicView(NSTouchBar) _colorPickerTouchBarItemChanged:] (in OmniGraffle) (GraphicView-TouchBar.m:797))
        IGNORE_CRASH(@"NSScrollingBehaviorLegacy", @selector(scrollView:panGestureRecognizerEndedOrFailed:))

        // <bug:///154165> (Mac-OmniGraffle Crasher: [needs repro] [7.9.2] +[NSXPCSharedListener connectionForListenerNamed:fromServiceNamed:] (in ViewBridge))

        /*
         Assertion Failed:
         ---------------------------
         Object: <NSVBOpenPanel:0x7fc740d81ec0>
         Selector: viewWillInvalidate:
         File: /BuildRoot/Library/Caches/com.apple.xbs/Sources/AppKit/AppKit-1671/Nav.subproj/OpenAndSavePanelRemote/NSVBOpenAndSavePanels.m
         Line: 374
         Description: bridge absent
         ---------------------------
         */
        IGNORE_CRASH(@"NSVBOpenPanel", @selector(viewWillInvalidate:))
        
        // the following are being captured by <bug:///137535> (Mac-OmniGraffle Crasher: [7.9.2] crash_info (ViewBridge): "ViewBridge hint(s))
        /*
         Assertion Failed:
         ---------------------------
         Object: <NSVBSavePanel:0x7f9e9730ffa0>
         Selector: viewWillInvalidate:
         File:
         /BuildRoot/Library/Caches/com.apple.xbs/Sources/AppKit/AppKit-1561.60.100/Nav.subproj/OpenAndSavePanelRemote/NSVBOpenAndSavePanels.m
         Line: 387
         Description: bridge absent
         ---------------------------
         */
        IGNORE_CRASH(@"NSVBSavePanel", @selector(viewWillInvalidate:))
        /*
         Assertion Failed:
         ---------------------------
         Object: <NSViewServiceMarshal:0x7fffcbc571f0>
         Selector: informHostsOfConnectionToService:
         File: /Library/Caches/com.apple.xbs/Sources/ViewBridge/ViewBridge-283/NSViewServiceMarshal.m
         Line: 997
         Description: Invalid parameter not satisfying: pid
         ---------------------------
         */
        IGNORE_CRASH(@"NSViewServiceMarshal", @selector(informHostsOfConnectionToService:))
        /*
         Assertion Failed:
         ---------------------------
         Object: <NSVBSavePanel:0x7fddd60a1e80>
         Selector: _attachSandboxExtensions:toURL:orURLs:
         File: /Library/Caches/com.apple.xbs/Sources/AppKit/AppKit-1504.83.101/Nav.subproj/OpenAndSavePanelRemote/NSVBOpenAndSavePanels.m
         Line: 449
         Description: unexpected class type for sandbox extension string!
         ---------------------------
         */
        IGNORE_CRASH(@"NSViewServiceMarshal", @selector(_attachSandboxExtensions:toURL:orURLs:))
        /*
         Assertion Failed:
         ---------------------------
         Object: <NSRemoteView:0x600002924280>
         Selector: synchronizeAnimationsInActions:
         File: /BuildRoot/Library/Caches/com.apple.xbs/Sources/ViewBridge/ViewBridge-401.1/NSRemoteView.m
         Line: 6384
         Description: {
         "01_frame" = "{{0, 0}, {1189, 621}}";
         "__self__" = "<NSRemoteView:0x600002924280>";
         } unable to wrap fence
         ---------------------------
         */
        IGNORE_CRASH(@"NSRemoteView", @selector(synchronizeAnimationsInActions:))

        
#undef IGNORE_CRASH

        // XPC services (like the 'define' service) sometimes time out:
        // Object: <NSXPCSharedListener:0x7fff7a5e67a8>
        // Selector: connectionForListenerNamed:fromServiceNamed:
        // File: /SourceCache/ViewBridge/ViewBridge-99/NSXPCSharedListener.m
        // Line: 394
        // Description: NSXPCSharedListener unable to create endpoint for listener named com.apple.view-bridge
        if (selector == @selector(connectionForListenerNamed:fromServiceNamed:) && (!object || [NSStringFromClass([object class]) isEqualToString:@"NSXPCSharedListener"])) {
            crash = NO;
        }

        // An assertion failure originates from this method on 10.2.2. Seems harmless?
        // rdar://problem/30105831
        if (selector == @selector(informAuxServiceOfSelf) && (!object || [NSStringFromClass([object class]) isEqualToString:@"NSRemoteView"])) {
            crash = NO;
        }
        
#pragma clang diagnostic pop
        
        if (crash)
            [self crashWithReport:report];
    }

    handlingAssertion = NO;
}

- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line format:(NSString *)format arguments:(va_list)args;
{
    static BOOL handlingAssertion = NO;
    if (handlingAssertion)
	return; // Skip since we apparently screwed up
    handlingAssertion = YES;
    
    OBRecordBacktrace(NULL, OBBacktraceBuffer_NSAssertionFailure);

    if (!CrashOnAssertionOrUnhandledException) {
	NSString *symbolicTrace = OFCopySymbolicBacktrace();
	
	NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
	
	NSLog(@"Assertion Failed:\n---------------------------\nFunction: %@\nFile: %@\nLine: %d\nDescription: %@\nStack Trace:\n%@\n---------------------------",
	      functionName, fileName, line, description, symbolicTrace);
#if defined(OMNI_ASSERTIONS_ON)
        OBAssertFailed([description UTF8String]); // In case there is a breakpoint in the debugger for assertion failures.
#endif
	[description release];
	[symbolicTrace release];
    } else {
        NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
        NSString *report = [NSString stringWithFormat:@"Assertion Failed:\n---------------------------\nFunction: %@\nFile: %@\nLine: %d\nDescription: %@\n---------------------------",
                            functionName, fileName, line, description];
        [description release];
        [self crashWithReport:report];
    }
    
    handlingAssertion = NO;
}

#pragma mark -
#pragma mark NSExceptionHandler delegate

static NSString * const OFControllerAssertionHandlerException = @"OFControllerAssertionHandlerException";

- (BOOL)exceptionHandler:(NSExceptionHandler *)sender shouldLogException:(NSException *)exception mask:(NSUInteger)aMask;
{
    // This makes the assumption that NSException names are using static strings, which is a very good bet.
    OBRecordBacktrace([[exception name] UTF8String], OBBacktraceBuffer_NSException);

    /*
     
     NOTE: This is no longer the case on 10.14b7
     
     At some point (10.9?) CFRelease(NULL) (and possibly all such NULL dereferences) started hitting this path:
     
     0x7fff93f5fc71 -- 0   ExceptionHandling                   0x00007fff93f5fc71 NSExceptionHandlerUncaughtSignalHandler + 35
     0x7fff9277d5aa -- 1   libsystem_platform.dylib            0x00007fff9277d5aa _sigtramp + 26
     0x6080000bb780 -- 2   ???                                 0x00006080000bb780 0x0 + 106102872848256

     and sending us NSLogUncaughtSystemExceptionMask. It seems very odd that they are calling into ObjC from a signal handler.
     Without checking for all the 'log uncaught' masks, our process would simply exit instead of bringing up the crash catcher.
     */
    
    if (LogExceptionHandlerShouldLogException) {
        // 10.13.6 and 10.14 b7: uncaught exception mask is still 0x100 (NSLogOtherExceptionMask) since AppKit seems to have a top-level handler.
        NSLog(@"-exceptionHandler:shouldLogException: %@ mask: 0x%lx", exception, aMask);
    }
    
    if (CrashOnAssertionOrUnhandledException && (aMask & (NSLogUncaughtExceptionMask|NSLogUncaughtSystemExceptionMask|NSLogUncaughtRuntimeErrorMask))) {
        if (aMask & (NSLogUncaughtSystemExceptionMask|NSLogUncaughtRuntimeErrorMask)) {
            // Radar 15415081: ExceptionHandling framework calls into ObjC from a signal handler.
            // It is unclear which hits on this will come from w/in a signal handler, so let's crash immediately w/o calling any ObjC (and hope that NSExceptionHandler really is caching the IMP of the delegate callbacks rather than going through dispatch and possibly deadlocking...)
            OFCrashImmediately();
        }

        if ([self _isDictionaryDefinitionException:exception]) {
            return NO;
        }
        
        [self crashWithException:exception mask:aMask];
        
        return YES; // normal handler; we shouldn't get here, though.
    }

    if (([sender exceptionHandlingMask] & aMask) == 0)
	return NO;
    
    // We might invoke OmniCrashCatcher later, but in a mode where it just dumps the info and doesn't reap us.  If we did we would get a list of all the Mach-O files loaded, for example.  This can be important when the exception is due to some system hack installed.  But, for now we'll do something fairly simple.  For now, we don't present this to the user, but at least it gets in the log file.  Once we have that level of reporting working well, we can start presenting to the user.
    
    static BOOL handlingException = NO;
    if (handlingException) {
	NSLog(@"Exception handler delegate called recursively!");
	return YES; // Let the normal handler do it since we apparently screwed up
    }
    
    if ([[exception name] isEqualToString:OFControllerAssertionHandlerException])
	return NO; // We are collecting the backtrace for some random purpose
    // (note on the above: we now use backtrace() instead of raising a OFControllerAssertionHandlerException to collect stack traces, so this test is presumably not needed any more)
    
    if (![self shouldLogException:exception mask:aMask])
        return NO;
    
    NSString *numericTrace = [[exception userInfo] objectForKey:NSStackTraceKey];
    if ([NSString isEmptyString:numericTrace])
	return YES; // huh?
    
    handlingException = YES;
    {
	NSString *symbolicTrace = OFCopySymbolicBacktraceForNumericBacktrace(numericTrace);
	NSLog(@"Exception raised:\n---------------------------\nMask: 0x%lx\nName: %@\nReason: %@\nStack Trace:\n%@\n---------------------------",
	      aMask, [exception name], [exception reason], symbolicTrace);
	[symbolicTrace release];
    }
    handlingException = NO;
    return NO; // we already did
}

#if USE_NOTIFICATION_CENTER
#pragma mark - Notification owner registration

- (void)addNotificationOwner:(id <OFNotificationOwner>)notificationOwner;
{
    OBPRECONDITION(notificationOwner != nil);
    OBPRECONDITION(_notificationOwnersLock);
    
    [_notificationOwnersLock lock];
    
    OBASSERT([self _locked_indexOfNotificationOwner:notificationOwner] == NSNotFound, "Adding the same notification owner twice is very likely a bug");
    
    OFControllerStatusObserverReference ref = [[OFWeakReference alloc] initWithObject:notificationOwner];
    [_locked_notificationOwnerReferences addObject:ref];
    [ref release];
    
    [_notificationOwnersLock unlock];
}

- (void)removeNotificationOwner:(id <OFNotificationOwner>)notificationOwner;
{
    OBPRECONDITION(notificationOwner != nil);
    OBPRECONDITION(_notificationOwnersLock);
    
    [_notificationOwnersLock lock];
    
    NSUInteger ownerIndex = [self _locked_indexOfNotificationOwner:notificationOwner];
    
    OBASSERT(ownerIndex != NSNotFound, "Removing a notification owner that wasn't added is very likely a bug");
    if (ownerIndex != NSNotFound)
        [_locked_notificationOwnerReferences removeObjectAtIndex:ownerIndex];
    
    [_notificationOwnersLock unlock];
}


#pragma mark - NSUserNotificationCenterDelegate

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification;
{
    id <OFNotificationOwner> owner = [self _ownerForUserNotification:notification];
    
    if (owner == (id)self) {
        // The subclass should have implemented this method if it wanted to do something, and is just calling super to satisfy NS_REQUIRES_SUPER
    } else if ([owner respondsToSelector:_cmd]) {
        OBSendVoidMessageWithObjectObject(owner, _cmd, center, notification);
    } else if (owner == nil) {
        OBASSERT_NOT_REACHED("No owner for user notification %@ %@", notification.identifier, notification);
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification;
{
    id <OFNotificationOwner> owner = [self _ownerForUserNotification:notification];
    
    if (owner == (id)self) {
        // The subclass should have implemented this method if it wanted to do something, and is just calling super to satisfy NS_REQUIRES_SUPER
    } else if ([owner respondsToSelector:_cmd]) {
        OBSendVoidMessageWithObjectObject(owner, _cmd, center, notification);
    } else if (owner == nil) {
        OBASSERT_NOT_REACHED("No owner for user notification %@ %@", notification.identifier, notification);
    }
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification;
{
    id <OFNotificationOwner> owner = [self _ownerForUserNotification:notification];
    
    if (owner == (id)self) {
        // The subclass should have implemented this method if it wanted to do something, and is just calling super to satisfy NS_REQUIRES_SUPER.
        // Though this will result in weird code if the subclass wants to return YES; it will need to call super, ignore the result and then return YES.
        return NO;
    } else if ([owner respondsToSelector:_cmd]) {
        return OBSendBoolReturnMessageWithObjectObject(owner, _cmd, center, notification);
    } else if (owner == nil) {
        OBASSERT_NOT_REACHED("No owner for user notification %@ %@", notification.identifier, notification);
        return NO;
    }
    return NO;
}
#endif

#pragma mark - Private

- (void)_crashOnAssertionPreferenceChanged:(NSNotification *)note;
{
    OBPRECONDITION(!note || note.object == _crashOnAssertionOrUnhandledExceptionPreference);
    
    CrashOnAssertionOrUnhandledException = [_crashOnAssertionOrUnhandledExceptionPreference boolValue];
}

- (void)_makeObserversPerformSelector:(SEL)aSelector;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    for (id anObserver in [self _observersSnapshot]) {
        if ([anObserver respondsToSelector:aSelector]) {
            // NSLog(@"Calling %s[%@ %s]", OBPointerIsClass(anObserver) ? "+" : "-", OBShortObjectDescription(anObserver), aSelector);
            @try {
                OBSendVoidMessageWithObject(anObserver, aSelector, self);
            } @catch (NSException *exc) {
                NSLog(@"Ignoring exception raised during %s[%@ %@]: %@", OBPointerIsClass(anObserver) ? "+" : "-", OBShortObjectDescription(anObserver), NSStringFromSelector(aSelector), [exc reason]);
            };
        }
    }
}

- (void)_makeObserversPerformSelector:(SEL)aSelector withObject:(id)object;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    for (id anObserver in [self _observersSnapshot]) {
        if ([anObserver respondsToSelector:aSelector]) {
            @try {
                OBSendVoidMessageWithObjectObject(anObserver, aSelector, self, object);
            } @catch (NSException *exc) {
                NSLog(@"Ignoring exception raised during %s[%@ %@]: %@", OBPointerIsClass(anObserver) ? "+" : "-", OBShortObjectDescription(anObserver), NSStringFromSelector(aSelector), [exc reason]);
            };
        }
    }
}

- (NSArray *)_observersSnapshot;
{
    OBPRECONDITION([NSThread isMainThread]);

    NSMutableArray *observers = [[NSMutableArray alloc] init];

    [observerLock lock];
    {
        for (OFControllerStatusObserverReference ref in _observerReferences) {
            id object = ref.object;
            if (object)
                [observers addObject:object];
        }
    }
    [observerLock unlock];

    return [observers autorelease];
}

- (void)_runQueues
{
    for (;;) {
        NSMutableArray *toRun = nil;
        [observerLock lock];
        for (NSNumber *targetState in [_queues keyEnumerator]) {
            if ([targetState intValue] <= (int)_status) {
                toRun = [[_queues objectForKey:targetState] retain];
                [_queues removeObjectForKey:targetState];
                break;
            }
        }
        [observerLock unlock];
        
        if (toRun) {
            for (void (^block)(void) in toRun) {
                @try {
                    block();
                } @catch (NSException *exc) {
                    NSLog(@"Ignoring exception raised during controller initialization block: %@", exc.reason);
                };
            }
            [toRun release];
        } else
            break;
    }
}

#if USE_NOTIFICATION_CENTER
- (NSUInteger)_locked_indexOfNotificationOwner:(id)owner;
{
    OBPRECONDITION(_locked_notificationOwnerReferences);
    
    return [_locked_notificationOwnerReferences indexOfObjectPassingTest:^BOOL(OFControllerStatusObserverReference ref, NSUInteger idx, BOOL *stop) {
        return [ref referencesObject:(OB_BRIDGE void *)owner];
    }];
}

- (NSArray *)_notificationOwnersSnapshot;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    NSMutableArray *owners = [[NSMutableArray alloc] init];
    
    [_notificationOwnersLock lock];
    {
        for (OFControllerStatusObserverReference ref in _locked_notificationOwnerReferences) {
            id object = ref.object;
            if (object)
                [owners addObject:object];
        }
    }
    [_notificationOwnersLock unlock];
    
    return [owners autorelease];
}

- (id <OFNotificationOwner>)_ownerForUserNotification:(NSUserNotification *)userNotification;
{
    NSArray *owners = [self _notificationOwnersSnapshot];
    
    for (id <OFNotificationOwner> owner in owners) {
        if ([owner ownsNotification:userNotification])
            return owner;
    }
    
    return nil;
}
#endif

@end

