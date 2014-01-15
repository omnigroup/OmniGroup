// Copyright 1998-2008, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFController.h>

#import <ExceptionHandling/NSExceptionHandler.h>
#import <OmniBase/system.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSThread-OFExtensions.h>
#import <OmniFoundation/OFBacktrace.h>
#import <OmniFoundation/OFInvocation.h>
#import <OmniFoundation/OFObject-Queue.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFWeakReference.h>

RCS_ID("$Id$")

@interface OFController ()
@property (nonatomic, assign) OFControllerStatus status;
@end

/*" OFController is used to represent the current state of the application and to receive notifications about changes in that state. "*/
@implementation OFController
{
    OFControllerStatus _status;
    NSLock *observerLock;
    NSMutableArray *_observerReferences; // OFWeakReferences holding the observers
    NSMutableSet *postponingObservers;
    NSMutableDictionary *queues;
}

static OFController *sharedController = nil;
static BOOL CrashOnAssertionOrUnhandledException = NO; // Cached so we can get this w/in the handler w/o calling into ObjC (since it might be unsafe)

#ifdef OMNI_ASSERTIONS_ON
static void _OFControllerCheckTerminated(void)
{
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    
    // Make sure that applications that use OFController actually call its -willTerminate.
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    if ([[[environment objectForKey:@"XCInjectBundle"] pathExtension] isEqualToString:@"octest"] &&
        [[environment objectForKey:@"XCInjectBundleInto"] hasPrefix:[[NSBundle mainBundle] bundlePath]]) {
        // We need to skip this check for otest host apps since +[SenTestProbe runTests:] just calls exit() rather than -terminate:.        
    } else {
        OBASSERT(!sharedController || sharedController->_status == OFControllerTerminatingStatus || sharedController->_status == OFControllerNotInitializedStatus);
    }
    
    [p drain];
}
#endif

// If we are running a bundled app, this will return the main bundle.  Otherwise, if we are running unit tests, this will return the unit test bundle.
+ (NSBundle *)controllingBundle;
{
    static NSBundle *controllingBundle = nil;
    
    if (!controllingBundle) {
        if (NSClassFromString(@"SenTestCase")) {
            // There should be exactly one bundle with an extension of either 'otest' (the old extension) or 'octest' (what Xcode 3 uses).
            NSBundle *candidateBundle = nil;
            for (NSBundle *bundle in [NSBundle allBundles]) {
                NSString *extension = [[bundle bundlePath] pathExtension];
                if ([extension isEqualToString:@"otest"] || [extension isEqualToString:@"octest"]) {
                    if (candidateBundle) {
                        NSLog(@"found extra possible unit test bundle %@", bundle);
                    } else
                        candidateBundle = bundle;
                }
            }
            
            if (candidateBundle)
                controllingBundle = [candidateBundle retain];
        }

        if (!controllingBundle)
            controllingBundle = [[NSBundle mainBundle] retain];
        
        // If the controlling bundle specifies a minimum OS revision, make sure it is at least 10.8 (since that is our global minimum on the trunk right now).  Only really applies for LaunchServices-started bundles (applications).
#ifdef OMNI_ASSERTIONS_ON
        {
            NSString *requiredVersionString = [[controllingBundle infoDictionary] objectForKey:@"LSMinimumSystemVersion"];
            if (requiredVersionString) {
                OFVersionNumber *requiredVersion = [[OFVersionNumber alloc] initWithVersionString:requiredVersionString];
                OBASSERT(requiredVersion);
                
                OFVersionNumber *globalRequiredVersion = [[OFVersionNumber alloc] initWithVersionString:@"10.8"];
                OBASSERT([globalRequiredVersion compareToVersionNumber:requiredVersion] != NSOrderedDescending);
                [requiredVersion release];
                [globalRequiredVersion release];
            }
        }
#endif
    }
    
    OBPOSTCONDITION(controllingBundle);
    return controllingBundle;
}

+ (instancetype)sharedController;
{
    // Don't set up the shared controller in +initialize.  The issue is that the superclass +initialize will always get called first and the fallback code to use the receiving class will always get OFController.  In a command line tool you don't have a bundle plist, but you can subclass OFController and make sure +sharedController is called on it first.
    if (sharedController == nil) {
        static BOOL _stillSettingUpSharedController = YES;
        assert(_stillSettingUpSharedController == YES);

        NSBundle *controllingBundle = [self controllingBundle];
        NSDictionary *infoDictionary = [controllingBundle infoDictionary];
        NSString *controllerClassName = [infoDictionary objectForKey:@"OFControllerClass"];
        
        if ([NSString isEmptyString:controllerClassName]) {
            // When running unit tests, the main bundle won't be the test bundle.
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
    }
    
    OBASSERT([sharedController isKindOfClass:self]);
    if (![sharedController isKindOfClass:self])
        return nil;
    
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
    
    CrashOnAssertionOrUnhandledException = [self crashOnAssertionOrUnhandledException];
    
    NSExceptionHandler *handler = [NSExceptionHandler defaultExceptionHandler];
    [handler setDelegate:self];
    [handler setExceptionHandlingMask:[self exceptionHandlingMask]];
    
    // NSAssertionHandler's documentation says this is the way to customize assertion handling
    [[[NSThread currentThread] threadDictionary] setObject:self forKey:@"NSAssertionHandler"];
    
    observerLock = [[NSLock alloc] init];
    _status = OFControllerNotInitializedStatus;
    _observerReferences = [[NSMutableArray alloc] init];
    postponingObservers = [[NSMutableSet alloc] init];
    
#ifdef OMNI_ASSERTIONS_ON
    atexit(_OFControllerCheckTerminated);
#endif
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION([NSThread isMainThread]);

    [_observerReferences release];
    [postponingObservers release];
    [queues release];
    
    [super dealloc];
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

- (NSUInteger)_locked_indexOfObserver:(id)observer;
{
    return [_observerReferences indexOfObjectPassingTest:^BOOL(OFWeakReference *ref, NSUInteger idx, BOOL *stop) {
        return [ref referencesObject:observer];
    }];
}

/*" Subscribes the observer to a set of notifications based on the methods that it implements in the OFControllerObserver informal protocol.  Classes can register for these notifications in their +didLoad methods (and those +didLoad methods probably shouldn't do much else, since defaults aren't yet registered during +didLoad). "*/
- (void)addObserver:(id)observer;
{
    OBPRECONDITION(observer != nil);
    
    [observerLock lock];
    
    OBASSERT([self _locked_indexOfObserver:observer] == NSNotFound, "Adding the same observer twice is very likely a bug");
    
    OFWeakReference *ref = [[OFWeakReference alloc] initWithObject:observer];
    [_observerReferences addObject:ref];
    [ref release];
        
    [observerLock unlock];
}


/*" Unsubscribes the observer to a set of notifications based on the methods that it implements in the OFControllerObserver informal protocol. "*/
- (void)removeObserver:(id)observer;
{
    [observerLock lock];
    
    NSUInteger observerIndex = [self _locked_indexOfObserver:observer];
    
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
        [receiver performSelector:message];
    } else {
        OFInvocation *queueEntry = [[OFInvocation alloc] initForObject:receiver selector:message];
        [self queueInvocation:queueEntry whenStatus:state];
        [queueEntry release];
    }
}

/*" Enqueues an invocation to occur when the controller enters a specific state. If the controller is already in that state (or a later state), then the action will happen immediately. Unlike the observer protocol, this method retains the receiver (via the invocation) until the message is sent. "*/
- (void)queueInvocation:(OFInvocation *)action whenStatus:(OFControllerStatus)state;
{
    if (!action)
        return;
    
    [observerLock lock];
    if (state <= _status) {
        [observerLock unlock];
        [action invoke];
    } else {
        NSNumber *key = [NSNumber numberWithInt:state];
        NSMutableArray *queue = [queues objectForKey:key];
        if (!queue) {
            if (!queues)
                queues = [[NSMutableDictionary alloc] init];
            queue = [NSMutableArray array];
            [queues setObject:queue forKey:key];
        }

        [queue addObject:action];
        
        [observerLock unlock];
    }
}

/*" The application should call this once after it is initialized.  In AppKit applications, this should be called from -applicationWillFinishLaunching:. "*/
- (void)didInitialize;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_status == OFControllerNotInitializedStatus);
    
    self.status = OFControllerInitializedStatus;
    [self _makeObserversPerformSelector:@selector(controllerDidInitialize:)];
}

/*" The application should call this once after calling -didInitialize.  In AppKit applications, this should be called from -applicationDidFinishLaunching:. "*/
- (void)startedRunning;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_status == OFControllerInitializedStatus);
    
    self.status = OFControllerRunningStatus;
    [self _makeObserversPerformSelector:@selector(controllerStartedRunning:)];
}
    
/*" The application should call this when a termination request has been received.  If YES is returned, the termination can proceed (i.e., the caller should call -willTerminate) next. "*/
- (OFControllerTerminateReply)requestTermination;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_status == OFControllerRunningStatus);
    
    self.status = OFControllerRequestingTerminateStatus;
    
    for (id anObserver in [self _observersSnapshot]) {
        if ([anObserver respondsToSelector:@selector(controllerRequestsTerminate:)]) {
            @try {
                [anObserver controllerRequestsTerminate:self];
            } @catch (NSException *exc) {
                NSLog(@"Ignoring exception raised during %s[%@ controllerRequestsTerminate:]: %@", OBPointerIsClass(anObserver) ? "+" : "-", OBShortObjectDescription(anObserver), [exc reason]);
            }
        }
        
        // Break if the termination was cancelled
        if (_status == OFControllerRunningStatus)
            break;
    }

    if (_status != OFControllerRunningStatus && [postponingObservers count] > 0)
        self.status = OFControllerPostponingTerminateStatus;

    switch (_status) {
        case OFControllerRunningStatus:
            return OFControllerTerminateCancel;
        case OFControllerRequestingTerminateStatus:
            self.status = OFControllerTerminatingStatus;
            return OFControllerTerminateNow;
        case OFControllerPostponingTerminateStatus:
            return OFControllerTerminateLater;
        default:
            OBASSERT_NOT_REACHED("Can't return from OFControllerRunningStatus to an earlier state");
            return OFControllerTerminateNow;
    }
}

/*" This method can be called during a -controllerRequestsTerminate: method when an object wishes to cancel the termination (typically in response to a user pressing the "Cancel" button on a Save panel). "*/
- (void)cancelTermination;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    switch (_status) {
        case OFControllerRequestingTerminateStatus:
            self.status = OFControllerRunningStatus;
            break;
        case OFControllerPostponingTerminateStatus:
            [self gotPostponedTerminateResult:NO];
            self.status = OFControllerRunningStatus;
            break;
        default:
            break;
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
        [self gotPostponedTerminateResult:(_status != OFControllerRunningStatus)];
    } else if ((_status == OFControllerRequestingTerminateStatus || _status == OFControllerPostponingTerminateStatus || _status == OFControllerTerminatingStatus)) {
        [self _makeObserversPerformSelector:@selector(controllerRequestsTerminate:)];
    }
}

- (void)willTerminate;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_status == OFControllerTerminatingStatus); // We should have requested termination and not had it cancelled or postponed.
    
    [self _makeObserversPerformSelector:@selector(controllerWillTerminate:)];
}

- (void)gotPostponedTerminateResult:(BOOL)isReadyToTerminate;
{
    if (isReadyToTerminate)
        self.status = OFControllerTerminatingStatus;
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

- (BOOL)crashOnAssertionOrUnhandledException;
{
    // This acts as a global throttle on the 'crash on exeception' support.  If this is off, we assume the app doesn't want the behavior at all.
    // Some applications, like OmniFocus, are in a constantly saved state.  In this case, there is little to lose by crashing and lots to gain (avoid corrupting data, get reports from users so we can fix them, etc.).  Other applications aren't always saved, so crashing at the first sign of trouble would lead to data loss.  Each application can pick their behavior by setting this key in their Info.plist in the defaults registration area.
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"OFCrashOnAssertionOrUnhandledException"];
}

static void OFCrashImmediately(void)
{
    unsigned int *bad = (unsigned int *)sizeof(unsigned int);
    bad[-1] = 0; // Crash immediately; crazy approach is to defeat the clang error about dereferencing NULL, which is the point!
}

- (void)crashWithReport:(NSString *)report;
{
    // OmniCrashCatcher overrides this method to do something more useful
    NSLog(@"Crashing with report:\n%@", report);
    
    OFCrashImmediately();
}

- (void)crashWithException:(NSException *)exception mask:(NSUInteger)mask;
{
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
    
    if (!symbolicBacktrace)
        symbolicBacktrace = @"No numeric backtrace found";
    
    NSString *report = [NSString stringWithFormat:@"Exception raised:\n---------------------------\nMask: 0x%08lx\nName: %@\nReason: %@\nInfo:\n%@\nBacktrace:\n%@\n---------------------------",
                        mask, [exception name], [exception reason], [exception userInfo], symbolicBacktrace];

    [self crashWithReport:report];
}

- (void)handleUncaughtException:(NSException *)exception;
{
    OBRecordBacktrace(NULL, OBBacktraceBuffer_NSException);
    [self crashWithException:exception mask:NSLogUncaughtExceptionMask];
}

- (BOOL)shouldLogException:(NSException *)exception mask:(NSUInteger)aMask;
{
    if ([exception.name isEqual:@"SenTestFailureException"])
        return NO;
    
    return YES;
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
	[description release];
	[symbolicTrace release];
#if defined(OMNI_ASSERTIONS_ON)
        OBAssertFailed(); // In case there is a breakpoint in the debugger for assertion failures.
#endif
    } else {
        NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
        NSString *report = [NSString stringWithFormat:@"Assertion Failed:\n---------------------------\nObject: %@\nSelector: %@\nFile: %@\nLine: %d\nDescription: %@\n---------------------------",
                            OBShortObjectDescription(object), NSStringFromSelector(selector), fileName, line, description];
        [description release];
        
        BOOL crash = YES;
        
        // NSRemoteSavePanel sometimes fails an assertion when it turns on the "hide extension" checkbox on by itself. Seems harmless?
        if (selector == @selector(connection:didReceiveRequest:) && [NSStringFromClass([object class]) isEqualToString:@"NSRemoteSavePanel"])
            crash = NO;

        // Save as PDF (maybe just when the suggested name has 'foo.ext' and you confirm the alert asking to switch to just '.pdf'.
        if (selector == @selector(updateWindowEdgeResizingRegion) && [NSStringFromClass([object class]) isEqualToString:@"NSRemoteView"])
            crash = NO;

        // Bringing up security options for print-to-pdf in a sandboxed app causes a harmless failure. <bug:///87161>
        if (selector == @selector(sendEvent:) && [NSStringFromClass([object class]) isEqualToString:@"NSAccessoryWindow"])
            crash = NO;
        
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
	[description release];
	[symbolicTrace release];
#if defined(OMNI_ASSERTIONS_ON)
        OBAssertFailed(); // In case there is a breakpoint in the debugger for assertion failures.
#endif
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
    OBRecordBacktrace(NULL, OBBacktraceBuffer_NSException);

    /*
     At some point (10.9?) CFRelease(NULL) (and possibly all such NULL dereferences) started hitting this path:
     
     0x7fff93f5fc71 -- 0   ExceptionHandling                   0x00007fff93f5fc71 NSExceptionHandlerUncaughtSignalHandler + 35
     0x7fff9277d5aa -- 1   libsystem_platform.dylib            0x00007fff9277d5aa _sigtramp + 26
     0x6080000bb780 -- 2   ???                                 0x00006080000bb780 0x0 + 106102872848256

     and sending us NSLogUncaughtSystemExceptionMask. It seems very odd that they are calling into ObjC from a signal handler.
     Without checking for all the 'log uncaught' masks, our process would simply exit instead of bringing up the crash catcher.
     */
    
    if (CrashOnAssertionOrUnhandledException && (aMask & (NSLogUncaughtExceptionMask|NSLogUncaughtSystemExceptionMask|NSLogUncaughtRuntimeErrorMask))) {
        if (aMask & (NSLogUncaughtSystemExceptionMask|NSLogUncaughtRuntimeErrorMask)) {
            // Radar 15415081: ExceptionHandling framework calls into ObjC from a signal handler.
            // It is unclear which hits on this will come from w/in a signal handler, so let's crash immediately w/o calling any ObjC (and hope that NSExceptionHandler really is caching the IMP of the delegate callbacks rather than going through dispatch and possibly deadlocking...)
            OFCrashImmediately();
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

#pragma mark - Private

- (void)_makeObserversPerformSelector:(SEL)aSelector;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    for (id anObserver in [self _observersSnapshot]) {
        if ([anObserver respondsToSelector:aSelector]) {
            // NSLog(@"Calling %s[%@ %s]", OBPointerIsClass(anObserver) ? "+" : "-", OBShortObjectDescription(anObserver), aSelector);
            @try {
                [anObserver performSelector:aSelector withObject:self];
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
                [anObserver performSelector:aSelector withObject:self withObject:object];
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
        for (OFWeakReference *ref in _observerReferences) {
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
    for(;;) {
        NSMutableArray *toRun = nil;
        [observerLock lock];
        for (NSNumber *targetState in [queues keyEnumerator]) {
            if ([targetState intValue] <= (int)_status) {
                toRun = [[queues objectForKey:targetState] retain];
                [queues removeObjectForKey:targetState];
                break;
            }
        }
        [observerLock unlock];
        
        if (toRun) {
            for (OFInvocation *anAction in toRun) {
                @try {
                    [anAction invoke];
                } @catch (NSException *exc) {
                    NSLog(@"Ignoring exception raised during %@: %@", [anAction shortDescription], [exc reason]);
                };
            }
            [toRun release];
        } else
            break;
    }
}

@end

