// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController.h>

@import StoreKit; // For SKErrorDomain
@import OmniDAV; // For ODAVHTTPErrorDomain

#import <MessageUI/MFMailComposeViewController.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniAppKit/OAStrings.h>
#import <OmniBase/OBRuntimeCheck.h>
#import <OmniBase/system.h>
#import <OmniFoundation/NSString-OFURLEncoding.h>
#import <OmniFoundation/OFBundleRegistry.h>
#import <OmniFoundation/OFPointerStack.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFBacktrace.h>
#import <OmniUI/OmniUI-Swift.h>
#import <OmniUI/OUIAppController+SpecialURLHandling.h>
#import <OmniUI/OUIAppControllerSceneHelper.h>
#import <OmniUI/OUIAttentionSeekingButton.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIChangePreferenceURLCommand.h>
#import <OmniUI/OUIDebugURLCommand.h>
#import <OmniUI/OUIErrors.h>
#import <OmniUI/OUIHelpURLCommand.h>
#import <OmniUI/OUIKeyboardNotifier.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/OUIPurchaseURLCommand.h>
#import <OmniUI/OUISendFeedbackURLCommand.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/UIViewController-OUIExtensions.h>
#import <OmniAppKit/NSString-OAExtensions.h>
#import <sys/sysctl.h>

#import "OUIChangeAppIconURLCommand.h"
#import "OUIParameters.h"

OFDeclareDebugLogLevel(OUIApplicationStateDebug);
#define DEBUG_STATE(level, format, ...) do { \
    if (OUIApplicationStateDebug >= (level)) \
        NSLog(@"APP STATE: " format, ## __VA_ARGS__); \
    } while (0)


#if 0 && defined(DEBUG_bungi)

static void TrackBackgroundTasks(void) __attribute__((constructor));

static NSLock *BackgroundTasksLock;
static NSMutableDictionary *RegisteredBackgroundTaskIdentifierToStartingBacktrace;

static UIBackgroundTaskIdentifier (*original_beginBackgroundTaskWithName)(UIApplication *self, SEL _cmd, NSString *taskName, void (^handler)(void));
static void (*original_endBackgroundTask)(UIApplication *self, SEL _cmd, UIBackgroundTaskIdentifier taskIdentifier);

static UIBackgroundTaskIdentifier replacement_beginBackgroundTaskWithName(UIApplication *self, SEL _cmd, NSString *taskName, void (^handler)(void))
{
    __block UIBackgroundTaskIdentifier taskIdentifier = UIBackgroundTaskInvalid;

    void (^expirationWrapper)(void) = ^{
        NSNumber *identifier = @(taskIdentifier);

        [BackgroundTasksLock lock];
        NSString *backtrace = RegisteredBackgroundTaskIdentifierToStartingBacktrace[identifier];
        RegisteredBackgroundTaskIdentifierToStartingBacktrace[identifier] = nil; // Not sure if UIKit will actually reuse the identifier after this?
        [BackgroundTasksLock unlock];

        NSLog(@"BACKGROUND: Task expired %ld, created from:\n%@", taskIdentifier, backtrace);

        if (handler) {
            handler();
        }
    };

    taskIdentifier = original_beginBackgroundTaskWithName(self, _cmd, taskName, expirationWrapper);

    NSUInteger count;
    NSNumber *identifier = @(taskIdentifier);
    NSString *backtrace = OFCopySymbolicBacktrace();
    [BackgroundTasksLock lock];
    {
        OBASSERT(RegisteredBackgroundTaskIdentifierToStartingBacktrace[identifier] == nil);
        RegisteredBackgroundTaskIdentifierToStartingBacktrace[identifier] = backtrace;
        count = [RegisteredBackgroundTaskIdentifierToStartingBacktrace count];
    }
    [BackgroundTasksLock unlock];

    NSLog(@"BACKGROUND: Begin task: %@ -> %ld (%ld)", taskName, taskIdentifier, count);
    return taskIdentifier;
}

static void replacement_endBackgroundTask(UIApplication *self, SEL _cmd, UIBackgroundTaskIdentifier taskIdentifier)
{
    NSUInteger count;
    NSNumber *identifier = @(taskIdentifier);

    [BackgroundTasksLock lock];
    {
        OBASSERT(RegisteredBackgroundTaskIdentifierToStartingBacktrace[identifier] != nil);
        [RegisteredBackgroundTaskIdentifierToStartingBacktrace removeObjectForKey:identifier];
        count = [RegisteredBackgroundTaskIdentifierToStartingBacktrace count];
    }
    [BackgroundTasksLock unlock];

    NSLog(@"BACKGROUND: End task: %ld (%ld)", taskIdentifier, count);

    original_endBackgroundTask(self, _cmd, taskIdentifier);
}

static void TrackBackgroundTasks(void)
{
    Class cls = objc_getClass("UIApplication");

    BackgroundTasksLock = [[NSLock alloc] init];
    RegisteredBackgroundTaskIdentifierToStartingBacktrace = [[NSMutableDictionary alloc] init];

    original_beginBackgroundTaskWithName = (typeof(original_beginBackgroundTaskWithName))OBReplaceMethodImplementation(cls, @selector(beginBackgroundTaskWithName:expirationHandler:), (IMP)replacement_beginBackgroundTaskWithName);
    original_endBackgroundTask = (typeof(original_endBackgroundTask))OBReplaceMethodImplementation(cls, @selector(endBackgroundTask:), (IMP)replacement_endBackgroundTask);
}

#endif

// Private storage class used to manage enqueued controllers
@interface OUIEnqueueableInteractionControllerContext: NSObject
- (instancetype)initWithInteractionController:(UIViewController<ExtendedInteractionDefining> *)controller parentExtendedAction:(nullable OUIExtendedAlertAction *)parentAction requiredScene:(nullable UIScene *)scene activityContextTitle:(NSString *)activityContextTitle activityContinuationButtonTitle:(NSString *)activityContinuationButtonTitle postponeActivityButtonTitle:(NSString *)postponeActivityButtonTitle presentationCompletionHandler:(void (^ __nullable)(void))presentationCompletionHandler;;
+ (OUIEnqueueableInteractionControllerContext *)contextWithInteractionController:(UIViewController<ExtendedInteractionDefining> *)alert parentExtendedAction:(nullable OUIExtendedAlertAction *)parentAction presentationCompletionHandler:(void (^ __nullable)(void))presentationCompletionHandler; // Calls the above initializer with nil for the other arguments
@property (nonatomic, strong, nonnull) UIViewController<ExtendedInteractionDefining> *controller;
@property (nonatomic, strong, nullable) OUIExtendedAlertAction *parentExtendedAction;
@property (nonatomic, strong, nullable) UIScene *requiredScene;
@property (nonatomic, strong, nullable) NSString *activityContextTitle;
@property (nonatomic, strong, nullable) NSString *activityContinuationButtonTitle;
@property (nonatomic, strong, nullable) NSString *postponeActivityButtonTitle;
@property (nonatomic, copy, nullable) void (^presentationCompletionHandler)(void);
@end

static OFPreference *NeedToShowURLPreference;
static OFPreference *PreviouslyShownURLsPreference;

NSNotificationName const OUIAttentionSeekingNotification = @"OUIAttentionSeekingNotification";
NSString * const OUIAttentionSeekingForNewsKey = @"OUIAttentionSeekingForNewsKey";

@interface OUIAppController ()
@property(strong, nonatomic) NSTimer *timerForSnapshots;

@property (strong, nonatomic) OFPointerStack<UIScene *> *connectedSceneStack;

@property (strong, nonatomic) NSMutableArray<OUIEnqueueableInteractionControllerContext *> *enqueuedInteractionControllerContexts;
@property (strong, nonatomic) NSMutableArray<UIViewController<ExtendedInteractionDefining> *> *currentlyPresentedInteractionControllers;

@property (nonatomic, strong, nonnull) NSMapTable<UIScene *, void (^)(void)> *mailInteractionCompletionHandlersByScene;
@end

@implementation OUIAppController
{
    NSMutableArray *_launchActions;
    NSOperationQueue *_backgroundPromptQueue;
    BOOL _canDequeueQueuedInteractions;
}

static NSString *_defaultReportErrorActionTitle;
static void (^_defaultReportErrorActionBlock)(UIViewController *viewController, NSError *error, void (^interactionCompletion)(void));


BOOL OUIShouldLogPerformanceMetrics = NO;


// This should be called right at the top of main() to meausre the time spent in the kernel, dyld, C++ constructors, etc.
// Since we don't have iOS kernel source, we don't know exactly when p_starttime gets set, so this may miss/include extra stuff.
NSTimeInterval OUIElapsedTimeSinceProcessCreation(void)
{
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    if (sysctl(mib, 4, &kp, &len, NULL, 0) < 0) {
        perror("sysctl");
        return 1;
    }
    
    struct timeval start_time = kp.kp_proc.p_starttime;
    
    struct timeval now;
    if (gettimeofday(&now, NULL) < 0) {
        perror("gettimeofday");
        return 0;
    }
    
    //fprintf(stderr, "start_time.tv_sec:%lu, start_time.tv_usec:%d\n", start_time.tv_sec, start_time.tv_usec);
    //fprintf(stderr, "now.tv_sec:%lu, now.tv_usec:%d\n", now.tv_sec, now.tv_usec);
    
    NSTimeInterval sec = ((now.tv_sec - start_time.tv_sec) * 1e6 + (now.tv_usec - start_time.tv_usec)) / 1e6;
    //NSLog(@"sec = %f", sec);
    
    return sec;
}

static NSTimeInterval OUIAppStartTime;

NSTimeInterval OUIElapsedTimeSinceApplicationStarted(void)
{
    return CFAbsoluteTimeGetCurrent() - OUIAppStartTime;
}

#ifdef DEBUG
typedef int (*PYStdWriter)(void *, const char *, int);

static PYStdWriter _oldStdWrite;

int __pyStderrWrite(void *inFD, const char *buffer, int size);
int __pyStderrWrite(void *inFD, const char *buffer, int size)
{
    if ( strncmp(buffer, "AssertMacros:", 13) == 0 ) {
        return size;
    }
    return _oldStdWrite(inFD, buffer, size);
}

static void __iOS7B5CleanConsoleOutput(void)
{
    _oldStdWrite = stderr->_write;
    stderr->_write = __pyStderrWrite;
}
#endif

+ (void)initialize;
{
    OBINITIALIZE;

    OUIAppStartTime = CFAbsoluteTimeGetCurrent();
    
#ifdef DEBUG
    __iOS7B5CleanConsoleOutput();
#endif
    
    OBPRECONDITION(OBClassImplementingMethod(self, @selector(applicationWillEnterForeground:)) == Nil, "Multi-scene applications don't get these lifecycle messages");
    OBPRECONDITION(OBClassImplementingMethod(self, @selector(applicationDidEnterBackground:)) == Nil, "Multi-scene applications don't get these lifecycle messages");

    @autoreleasepool {
        
        // Poke OFPreference to get default values registered
        NeedToShowURLPreference = [OFPreference preferenceForKey:@"OSU_need_to_show_URL" defaultValue:@""];
        PreviouslyShownURLsPreference = [OFPreference preferenceForKey:@"OSU_previously_shown_URLs" defaultValue:@[]];

        // Ensure that OUIKeyboardNotifier instantiates the shared notifier before the keyboard is shown for the first time, otherwise `lastKnownKeyboardHeight` and `keyboardVisible` may be incorrect.
        [OUIKeyboardNotifier sharedNotifier];
        
        OUIShouldLogPerformanceMetrics = [[OFPreference preferenceForKey:@"LogPerformanceMetrics" defaultValue:@(NO)] boolValue];
        
        if (OUIShouldLogPerformanceMetrics)
            NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
        
#ifdef OMNI_ASSERTIONS_ON
        OBRequestRuntimeChecks();
#endif
    }
}

+ (nonnull instancetype)controller;
{
    static id controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[UIApplication sharedApplication] delegate];
        OBASSERT([controller isKindOfClass:self]);
    });
    return controller;
}

+ (nonnull instancetype)sharedController;
{
    return [self controller];
}

+ (void)registerDefaultReportErrorAction NS_EXTENSION_UNAVAILABLE_IOS("Cannot register the default report error action from extensions as it uses API which extensions can't use");
{
    _defaultReportErrorActionTitle = NSLocalizedStringFromTableInBundle(@"Contact Omni", @"OmniUI", OMNI_BUNDLE, @"When displaying a generic error, this is the option to report the error.");
    _defaultReportErrorActionBlock = ^(UIViewController *viewController, NSError *error, void (^interactionCompletion)(void)) {
        UIDevice *currentDevice = UIDevice.currentDevice;
        NSString *body = [NSString stringWithFormat:@"\n%@ — %@ %@\n\n%@\n", [OUIAppController.controller fullReleaseString], currentDevice.systemName, currentDevice.systemVersion, [error toPropertyList]];
        [OUIAppController.sharedController sendFeedbackWithSubject:[NSString stringWithFormat:@"Error encountered: %@", [error localizedDescription]] body:body inScene:viewController.view.window.windowScene completion:interactionCompletion];
    };
}

+ (NSString *)applicationName;
{
    // The kCFBundleNameKey is often in the format "AppName-iPad".  If so, define an OUIApplicationName key in Info.plist and provide a better human-readable name, such as "AppName" or "AppName for iPad".
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [infoDictionary objectForKey:@"OUIApplicationName"];
    if (!appName) {
        appName = [infoDictionary objectForKey:(NSString *)kCFBundleNameKey];
    }
    return appName;
}

+ (nullable NSString *)applicationEdition;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

+ (NSString *)appStoreApplicationId;
{
    OBRequestConcreteImplementation(self, _cmd);
    return @"";
}

+ (NSString *)appStoreReviewLink;
{
    return [NSString stringWithFormat:@"<a href=\"itms-apps://itunes.apple.com/app/%@?action=write-review\">%@</a>", [self appStoreApplicationId], NSLocalizedStringFromTableInBundle(@"Write a Review", @"OmniUI", OMNI_BUNDLE, @"about page app store review link text")];
}

+ (nullable NSString *)majorVersionNumberString;
{
    NSString *versionString = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSArray *components = [versionString componentsSeparatedByString:@"."];
    return components.firstObject;
}

+ (nullable NSString *)helpEdition;
{
    return nil;
}

NSString * const OUIHelpBookNameKey = @"OUIHelpBookName";

+ (nullable NSString *)helpTitle;
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *helpBookName = [mainBundle objectForInfoDictionaryKey:OUIHelpBookNameKey];
    if ([NSString isEmptyString:helpBookName])
        return nil;

    return [mainBundle localizedStringForKey:OUIHelpBookNameKey value:helpBookName table:@"InfoPlist"];
}

+ (BOOL)inSandboxStore;
{
#if TARGET_IPHONE_SIMULATOR
    return YES;
#else
    static BOOL inSandboxStore;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *receiptName = [[[NSBundle mainBundle] appStoreReceiptURL] lastPathComponent];
        inSandboxStore = OFISEQUAL(receiptName, @"sandboxReceipt");
    });
    return inSandboxStore;
#endif
}

+ (BOOL)canHandleURLScheme:(NSString *)urlScheme;
{
    // Treat URL schemes as case insensitive
    urlScheme = [urlScheme lowercaseString];
    
    NSArray *urlTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];
    for (NSDictionary *urlType in urlTypes) {
        NSArray *urlSchemes = [urlType objectForKey:@"CFBundleURLSchemes"];
        for (NSString *supportedScheme in urlSchemes) {
            if ([urlScheme isEqualToString:supportedScheme.lowercaseString]) {
                return YES;
            }
        }
    }
    return NO;
}

+ (void)openURL:(NSURL*)url options:(NSDictionary<NSString *, id> *)options completionHandler:(void (^ __nullable)(BOOL success))completion NS_EXTENSION_UNAVAILABLE_IOS("") NS_DEPRECATED_IOS(13_0, 13_0, "The singleton app controller cannot know the correct presentation source in a multi-scene context.");
{
    UIApplication *sharedApplication = [UIApplication sharedApplication];
    NSString *scheme = [[url scheme] lowercaseString];

    // +canHandleURLScheme: is for special URLs; check for file URLs too, but should maybe just remove this check.
    if ([url isFileURL] || [self canHandleURLScheme:scheme]) {
        id <UIApplicationDelegate> appDelegate = [sharedApplication delegate];
        if ([appDelegate respondsToSelector:@selector(application:openURL:options:)]) {
            BOOL success = [appDelegate application:sharedApplication openURL:url options:@{
                UIApplicationOpenURLOptionsOpenInPlaceKey: @([url isFileURL]),
                UIApplicationOpenURLOptionsSourceApplicationKey: [[NSBundle mainBundle] bundleIdentifier],
            }];
            if (completion != NULL)
                completion(success);
            return;
        }
    }

    [sharedApplication openURL:url options:options completionHandler:completion];
}

NSErrorUserInfoKey const OUIShouldOfferToReportErrorUserInfoKey = @"OUIShouldOfferToReport";

+ (BOOL)shouldOfferToReportError:(NSError *)error;
{
    if (error == nil)
        return NO; // There isn't an error, so don't report one

    if ([error causedByUnreachableHost])
        return NO; // Unreachable hosts cannot be solved by the app

    NSError *storeError = [error underlyingErrorWithDomain:SKErrorDomain];
    if (storeError != nil) {
        switch (storeError.code) {
            case SKErrorStoreProductNotAvailable: // Product is not available in the current storefront
                return YES; // We do want to hear about this
            default:
                return NO; // But everything else in StoreKit is stuff we have no control over
        }
    }

    id value = error.userInfo[OUIShouldOfferToReportErrorUserInfoKey];
    if (value && ![value boolValue]) {
        return NO;
    }
    
    NSError *DAVError = [error underlyingErrorWithDomain:ODAVHTTPErrorDomain];
    if (DAVError != nil && !ODAVShouldOfferToReportError(DAVError)) {
        return NO;
    }

    return YES;
}

// Very basic.
+ (void)presentError:(NSError *)error;
{
    // Passing a nil view controller causes a lookup
    [self presentError:error fromViewController:nil file:NULL line:0];
}

+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController;
{
    OBASSERT(viewController.presentedViewController == nil);
    [self presentError:error fromViewController:viewController file:NULL line:0];
}

// Prefer passing a scene; will attempt to pick a sensible scene when nil
+ (void)presentError:(NSError *)error inScene:(nullable UIScene *)scene file:(const char * _Nullable)file line:(int)line;
{
    UIWindow *window = [self windowForScene:scene options:OUIWindowForSceneOptionsNone];
    UIViewController *rootViewController = window.rootViewController;
    [self presentError:error fromViewController:rootViewController file:file line:line];
}

+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActionTitle:(nullable NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalActionHandler;
{
    [self presentError:error fromViewController:viewController cancelButtonTitle:cancelButtonTitle optionalActionTitle:optionalActionTitle isDestructive:NO optionalAction:optionalActionHandler];
}

+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActionTitle:(nullable NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalActionHandler completionHandler:(void (^ _Nullable)(void))handler;
{
    [self presentError:error fromViewController:viewController cancelButtonTitle:cancelButtonTitle optionalActionTitle:optionalActionTitle isDestructive:NO optionalAction:optionalActionHandler completionHandler:handler];
}

+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActionTitle:(nullable NSString *)optionalActionTitle isDestructive:(BOOL)isDestructive optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalAction;
{
    [self presentError:error fromViewController:viewController cancelButtonTitle:cancelButtonTitle optionalActionTitle:optionalActionTitle isDestructive:isDestructive optionalAction:optionalAction completionHandler:nil];
}

+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActionTitle:(nullable NSString *)optionalActionTitle isDestructive:(BOOL)isDestructive optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalAction completionHandler:(void (^ _Nullable)(void))handler;
{
    NSArray <OUIExtendedAlertAction *> *optionalActions;
    if (optionalActionTitle != nil && optionalAction != nil) {
        UIAlertActionStyle style = isDestructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault;
        OUIExtendedAlertAction *action = [OUIExtendedAlertAction extendedActionWithTitle:optionalActionTitle style:style handler:optionalAction];
        optionalActions = @[action];
    }

    [self _presentError:error fromViewController:viewController file:nil line:0 cancelButtonTitle:cancelButtonTitle optionalActions:optionalActions parentExtendedAction:nil completionHandler:handler];
}

+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController file:(const char * _Nullable)file line:(int)line cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActions:(nullable NSArray <OUIExtendedAlertAction *> *)optionalActions completionHandler:(void (^ _Nullable)(void))handler;
{
    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:cancelButtonTitle optionalActions:optionalActions parentExtendedAction:nil completionHandler:handler];
}

+ (void)_presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController file:(const char * _Nullable)file line:(int)line cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActions:(nullable NSArray <OUIExtendedAlertAction *> *)optionalActions parentExtendedAction:(nullable OUIExtendedAlertAction *)parentExtendedAction completionHandler:(void (^ _Nullable)(void))handler NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    OBPRECONDITION([NSThread isMainThread]);
    if (error == nil || [error causedByUserCancelling])
        return;

    if (file)
        NSLog(@"Error reported from %s:%d", file, line);
    NSLog(@"%@", [error toPropertyList]);

    if (cancelButtonTitle == nil) {
        cancelButtonTitle = OACancel();
    }

    NSMutableArray *messages = [NSMutableArray array];

    NSString *reason = [error localizedFailureReason];
    if (![NSString isEmptyString:reason])
        [messages addObject:reason];

    NSString *suggestion = [error localizedRecoverySuggestion];
    if (![NSString isEmptyString:suggestion])
        [messages addObject:suggestion];

    NSString *message = [messages componentsJoinedByString:@"\n"];

    OUIEnqueueableAlertController *alertController = [OUIEnqueueableAlertController alertControllerWithTitle:[error localizedDescription] message:message preferredStyle:UIAlertControllerStyleAlert];

    id recoveryAttempter = error.recoveryAttempter;
    __block BOOL addedCancelRecovery = NO;

    if (recoveryAttempter) {
        NSArray *recoveryOptions = [error localizedRecoveryOptions];
        NSIndexSet *recoveryOptionIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [recoveryOptions count])];
        NSArray<NSNumber *> *recoveryTypes = error.userInfo[OFErrorRecoveryTypesErrorKey];

        [recoveryOptionIndexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger recoveryOptionIndex, BOOL * _Nonnull stop) {
            NSString *recoveryOption = recoveryOptions[recoveryOptionIndex];

            UIAlertActionStyle alertStyle = UIAlertActionStyleDefault;
            if (recoveryOptionIndex < [recoveryTypes count]) {
                alertStyle = UIAlertActionStyleForRecoveryType([recoveryTypes[recoveryOptionIndex] unsignedLongValue]);
            }

            if ([recoveryOption isEqualToString:cancelButtonTitle] || alertStyle == UIAlertActionStyleCancel) {
                alertStyle = UIAlertActionStyleCancel;
            }

            if (alertStyle == UIAlertActionStyleCancel) {
                addedCancelRecovery = YES;
            }

            [alertController addActionWithTitle:recoveryOption style:alertStyle handler:^(UIAlertAction *action) {
                NSInteger index = [recoveryOptions indexOfObject:recoveryOption];
                [recoveryAttempter attemptRecoveryFromError:error optionIndex:index delegate:nil didRecoverSelector:NULL contextInfo:NULL];
            }];
        }];
    }

    if (!addedCancelRecovery) {
        [alertController addActionWithTitle:cancelButtonTitle style:UIAlertActionStyleCancel handler:nil];
    }
    for (OUIExtendedAlertAction *optionalAction in optionalActions) {
        [alertController addExtendedAction:optionalAction];
    }

    UIScene *scene = viewController.containingScene;
    if (viewController != nil && scene.activationState == UISceneActivationStateForegroundActive) {
        // This delayed presentation avoids the "wait_fences: failed to receive reply: 10004003" lag/timeout which can happen depending on the context we start the reporting from.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            UIViewController *topViewController = viewController;
            UIViewController *vc;
            while ((vc = topViewController.presentedViewController)) {
                if (vc.isBeingDismissed) {
                    // This can happen when topViewController is presenting a OUIMenuController using a popover presentation. This check seems goofy though.
                    break;
                }
                topViewController = vc;
            }
            
            [self _prepareInteraction:alertController forImmediatePresentationOnScene:scene parentAction:parentExtendedAction interactionCompletionHandler:handler];

            [topViewController presentViewController:alertController animated:YES completion:nil];
        }];
    } else {
        if (handler != nil) {
            [alertController addInteractionCompletion:handler];
        }
        // We'll present this when a scene becomes active
        [self _enqueueInteractionControllerPresentationForAnyForegroundScene:alertController parentExtendedAction:parentExtendedAction presentationCompletionHandler:nil];
    }
}

+ (void)_presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line cancelButtonTitle:(nullable NSString *)cancelButtonTitle parentExtendedAction:(nullable OUIExtendedAlertAction *)parentAction;
{
    void (^optionalActionHandler)(OUIExtendedAlertAction *action);
    if (_defaultReportErrorActionBlock != NULL && [self shouldOfferToReportError:error]) {
        optionalActionHandler = ^(OUIExtendedAlertAction * __nonnull action) {
            _defaultReportErrorActionBlock(viewController, error, ^{ [action extendedActionComplete]; });
        };
    }

    NSArray <OUIExtendedAlertAction *> *optionalActions;
    if (_defaultReportErrorActionTitle != nil && optionalActionHandler != nil) {
        OUIExtendedAlertAction *optionalAction = [OUIExtendedAlertAction extendedActionWithTitle:_defaultReportErrorActionTitle style:UIAlertActionStyleDefault handler:optionalActionHandler];
        optionalActions = @[optionalAction];
    }

    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:cancelButtonTitle optionalActions:optionalActions parentExtendedAction:parentAction completionHandler:nil];
}

+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char *)file line:(int)line optionalActionTitle:(NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalActionHandler;
{
    NSArray <OUIExtendedAlertAction *> *optionalActions;
    if (optionalActionTitle != nil && optionalActionHandler != nil) {
        OUIExtendedAlertAction *optionalAction = [OUIExtendedAlertAction extendedActionWithTitle:optionalActionTitle style:UIAlertActionStyleDefault handler:optionalActionHandler];
        optionalActions = @[optionalAction];
    }

    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:nil optionalActions:optionalActions parentExtendedAction:nil  completionHandler:nil];
}

+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController file:(const char *)file line:(int)line;
{
    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:nil parentExtendedAction:nil];
}

// Prefer passing a scene; will attempt to pick a sensible scene when nil
+ (void)presentAlert:(NSError *)error inScene:(nullable UIScene *)scene file:(const char * _Nullable)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title
{

    UIWindow *window = [self windowForScene:scene options:OUIWindowForSceneOptionsNone];
    UIViewController *rootViewController = window.rootViewController;
    [self presentAlert:error fromViewController:rootViewController file:file line:line];
}

+ (void)presentAlert:(NSError *)error file:(const char * _Nullable)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title
{
    [self _presentError:error fromViewController:nil file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title") parentExtendedAction:nil];
}

+ (void)presentAlert:(NSError *)error fromViewController:(nullable UIViewController *)viewController file:(const char * _Nullable)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title
{
    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title") parentExtendedAction:nil];
}

+ (void)presentError:(NSError *)error fromViewController:(nonnull UIViewController *)viewController completingExtendedAction:(OUIExtendedAlertAction *)action;
{
    [self _presentError:error fromViewController:viewController file:nil line:0 cancelButtonTitle:nil parentExtendedAction:action];
}

- (id)init NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    if (!(self = [super init])) {
        return nil;
    }
    
    Class myClass = [self class];
    [myClass registerCommandClass:[OUIChangeAppIconURLCommand class] forSpecialURLPath:@"/change-app-icon"];
    [myClass registerCommandClass:[OUIChangePreferenceURLCommand class] forSpecialURLPath:@"/change-preference"];
    [myClass registerCommandClass:[OUIChangeGroupBundleIdentifierPreferenceURLCommand class] forSpecialURLPath:@"/change-group-preference"];
    [myClass registerCommandClass:[OUIDebugURLCommand class] forSpecialURLPath:@"/debug"];
    [myClass registerCommandClass:[OUIHelpURLCommand class] forSpecialURLPath:@"/help"];
    [myClass registerCommandClass:[OUIPurchaseURLCommand class] forSpecialURLPath:@"/purchase"];
    [myClass registerCommandClass:[OUISendFeedbackURLCommand class] forSpecialURLPath:@"/send-feedback"];
    [myClass registerCommandClass:[OUILicensingAuthenticationCommand class] forSpecialURLPath:@"/omni-account-authenticate"];
    [myClass registerCommandClass:[OUILicensingAuthenticationCommand class] forSpecialURLPath:@"/site-license-authenticate"];
    [myClass registerDefaultReportErrorAction];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_oui_applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(_oui_applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(_oui_applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [center addObserver:self selector:@selector(_oui_applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    _connectedSceneStack = [[OFPointerStack alloc] init];
    // Filter unattached scenes
    [_connectedSceneStack addAdditionalCompactionCondition:^BOOL(UIScene * _Nonnull scene) {
        return scene.activationState != UISceneActivationStateUnattached;
    }];
    [center addObserver:self selector:@selector(_sceneDidBecomeActive:) name:UISceneDidActivateNotification object:nil];
    [center addObserver:self selector:@selector(_windowDidBecomeKey:) name:UIWindowDidBecomeKeyNotification object:nil];

    _currentlyPresentedInteractionControllers = [NSMutableArray array];
    _canDequeueQueuedInteractions = YES;
    
    return self;
}

#if 1 && defined(DEBUG_correia)
    // UIKit calls the getter fairly frequently, so asserting on that is way to noisy to be of practical use.
    #define WINDOW_DEPRECATION_GETTER_ASSERTIONS_ON 0
    #define WINDOW_DEPRECATION_SETTER_ASSERTIONS_ON 1
#else
    #define WINDOW_DEPRECATION_GETTER_ASSERTIONS_ON 0
    #define WINDOW_DEPRECATION_SETTER_ASSERTIONS_ON 0
#endif

- (UIWindow *)window;
{
#if WINDOW_DEPRECATION_GETTER_ASSERTIONS_ON
    OBASSERT_NOT_REACHED("The `window` property is deprecated.");
#endif

    return nil;
}

- (void)setWindow:(UIWindow *)window;
{
#if WINDOW_DEPRECATION_SETTER_ASSERTIONS_ON
    OBASSERT_NOT_REACHED("The `window` property is deprecated.");
#endif
}

+ (nullable UIWindow *)windowForScene:(nullable UIScene *)scene options:(OUIWindowForSceneOptions)options;
{
    BOOL allowCascadingLookup = (options & OUIWindowForSceneOptionsAllowFallbackLookup) != 0;
    BOOL requireForegroundActiveScene = (options & OUIWindowForSceneOptionsRequireForegroundActiveScene) != 0;
    BOOL requireForegroundScene = (options & OUIWindowForSceneOptionsRequireForegroundScene) != 0;

    UIScene *resolvedScene = scene;

    if (resolvedScene == nil && allowCascadingLookup) {
        resolvedScene = [[self controller] mostRecentlyActiveSceneSatisfyingCondition:^BOOL(UIScene * _Nonnull proposedScene) {
            if (requireForegroundActiveScene && proposedScene.activationState != UISceneActivationStateForegroundActive) {
                return NO;
            } else if (requireForegroundScene) {
                switch (proposedScene.activationState) {
                    case UISceneActivationStateUnattached: {
                        return NO;
                    }
                    case UISceneActivationStateForegroundActive:
                    case UISceneActivationStateForegroundInactive: {
                        return YES;
                    }

                    case UISceneActivationStateBackground: {
                        return NO;
                    }
                }
            }
            
            return YES;
        }];
    }

    UIWindow *window = nil;

    if (resolvedScene != nil && [resolvedScene isKindOfClass:[UIWindowScene class]]) {
        UIWindowScene *windowScene = OB_CHECKED_CAST(UIWindowScene, resolvedScene);
        id delegate = windowScene.delegate;
        if (delegate != nil && [delegate conformsToProtocol:@protocol(UIWindowSceneDelegate)]) {
            id <UIWindowSceneDelegate> windowSceneDelegate = delegate;
            window = windowSceneDelegate.window;
        }
        
        if (window == nil) {
            window = windowScene.windows.firstObject;
        }
    }

    return window;
}

+ (UIViewController *)_viewControllerForPresentationInWindow:(UIWindow *)window
{
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController != nil) {
        controller = controller.presentedViewController;
    }
    return controller;
}

+ (void)_enqueueInteractionControllerPresentationForAnyForegroundScene:(UIViewController<ExtendedInteractionDefining> *)alert parentExtendedAction:(nullable OUIExtendedAlertAction *)parentAction presentationCompletionHandler:(void (^ __nullable)(void))presentationCompletionHandler NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    OBPRECONDITION([NSThread isMainThread]);

    // Check for an active scene, and present on it if there is one.
    UIScene *mostRecentlyActiveScene = [[self controller] mostRecentlyActiveScene];
    BOOL hasInteractionUpAlready = [[[self controller] currentlyPresentedInteractionControllers] anyObjectSatisfiesPredicate:^BOOL(UIViewController<ExtendedInteractionDefining> * _Nonnull controller) {
        return [controller containingScene] == mostRecentlyActiveScene;
    }];
    if (mostRecentlyActiveScene.activationState == UISceneActivationStateForegroundActive && !hasInteractionUpAlready && [self.controller canDequeueQueuedInteractions]) {
        [OUIAppController _prepareInteraction:alert forImmediatePresentationOnScene:mostRecentlyActiveScene parentAction:parentAction interactionCompletionHandler:nil];

        UIWindow *window = [self windowForScene:mostRecentlyActiveScene options:OUIWindowForSceneOptionsNone];
        UIViewController *controller = [self _viewControllerForPresentationInWindow:window];
        [controller presentViewController:alert animated:YES completion:presentationCompletionHandler];
    } else {
        if ([self.controller enqueuedInteractionControllerContexts] == nil) {
            [self.controller setEnqueuedInteractionControllerContexts:[NSMutableArray array]];
        }
        
        [[self.controller enqueuedInteractionControllerContexts] addObject:[OUIEnqueueableInteractionControllerContext contextWithInteractionController:alert parentExtendedAction:parentAction presentationCompletionHandler:presentationCompletionHandler]];
    }
}

+ (void)enqueueInteractionControllerPresentationForAnyForegroundScene:(UIViewController<ExtendedInteractionDefining> *)alert NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    [self enqueueInteractionControllerPresentationForAnyForegroundScene:alert presentationCompletionHandler:nil];
}

+ (void)enqueueInteractionControllerPresentationForAnyForegroundScene:(UIViewController<ExtendedInteractionDefining> *)alert presentationCompletionHandler:(void (^ __nullable)(void))presentationCompletionHandler NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    [self _enqueueInteractionControllerPresentationForAnyForegroundScene:alert parentExtendedAction:nil presentationCompletionHandler:presentationCompletionHandler];
}

+ (void)enqueueInteractionController:(UIViewController<ExtendedInteractionDefining> *)alert forPresentationInScene:(UIScene *)scene withActivityContextTitle:(NSString *)activityContextTitle activityContinuationButtonTitle:(NSString *)activityContinuationButtonTitle postponeActivityButtonTitle:(NSString *)postponeActivityButtonTitle NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    [self enqueueInteractionController:alert forPresentationInScene:scene withActivityContextTitle:activityContextTitle activityContinuationButtonTitle:activityContinuationButtonTitle postponeActivityButtonTitle:postponeActivityButtonTitle presentationCompletionHandler:nil];
}

+ (void)enqueueInteractionController:(UIViewController<ExtendedInteractionDefining> *)alert forPresentationInScene:(UIScene *)scene withActivityContextTitle:(NSString *)activityContextTitle activityContinuationButtonTitle:(NSString *)activityContinuationButtonTitle postponeActivityButtonTitle:(NSString *)postponeActivityButtonTitle presentationCompletionHandler:(void (^ __nullable)(void))presentationCompletionHandler NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    BOOL desiredSceneIsActive = scene.activationState == UISceneActivationStateForegroundActive;
    BOOL hasInteractionUpAlready = [[[self controller] currentlyPresentedInteractionControllers] anyObjectSatisfiesPredicate:^BOOL(UIViewController<ExtendedInteractionDefining> * _Nonnull controller) {
        return [controller containingScene] == scene;
    }];
    
    if (desiredSceneIsActive && !hasInteractionUpAlready && [self.controller canDequeueQueuedInteractions]) {
        [self _prepareInteraction:alert forImmediatePresentationOnScene:scene parentAction:nil interactionCompletionHandler:nil];
        
        UIWindow *window = [self windowForScene:scene options:OUIWindowForSceneOptionsNone];
        UIViewController *controller = [self _viewControllerForPresentationInWindow:window];
        [controller presentViewController:alert animated:YES completion:presentationCompletionHandler];
    } else {
        
        if ([self.controller enqueuedInteractionControllerContexts] == nil) {
            [self.controller setEnqueuedInteractionControllerContexts:[NSMutableArray array]];
        }
        
        // We're only explicitly passing nil for the parentExtendedAction because we don't need the parent action mechanism for anything but reporting errors that occur during app-level-defined extended actions. Those errors are reported via -presentError:fromViewController:completingExtendedAction: and that code path ends up calling the _enqueueInteractionControllerPresentationForAnyForegroundScene method of queuing its alerts. There is no explicit reason we can't have a parent action for interactions enqueued by this method, we just haven't needed it yet.
        OUIEnqueueableInteractionControllerContext *context = [[OUIEnqueueableInteractionControllerContext alloc] initWithInteractionController:alert parentExtendedAction:nil requiredScene:scene activityContextTitle:activityContextTitle activityContinuationButtonTitle:activityContinuationButtonTitle postponeActivityButtonTitle:postponeActivityButtonTitle presentationCompletionHandler:presentationCompletionHandler];
        
        UIScene *mostRecentlyActiveScene = [self.controller mostRecentlyActiveScene];
        if (mostRecentlyActiveScene.activationState == UISceneActivationStateForegroundActive && !hasInteractionUpAlready && [self.controller canDequeueQueuedInteractions]) {
            // Bump this context to the front of the queue and try to present it. We won't *actually* present it since the requiredScene is backgrounded. Instead, we will prompt the user with an alert saying that "<activityContextTitle> is active in another window" and give them the option to view whatever this is.
            // Scene-specific queued alerts are generally high-priority interactions, so we should prompt the user that something has happened immediately.
            [[self.controller enqueuedInteractionControllerContexts] insertObject:context atIndex:0];
            [self.controller _presentNextEnqueuedInteractionControllerOnScene:mostRecentlyActiveScene];
        } else {
            // Every scene is backgrounded, or an interaction is already up. Just add this to the queue.
            [[self.controller enqueuedInteractionControllerContexts] addObject:context];
        }
    }
}

+ (void)_prepareInteraction:(UIViewController<ExtendedInteractionDefining> *)alert forImmediatePresentationOnScene:(UIScene *)scene parentAction:(OUIExtendedAlertAction *)parentAction interactionCompletionHandler:(void (^ _Nullable)(void))interactionCompletionHandler;
{
    [[[self controller] currentlyPresentedInteractionControllers] addObject:alert];
    __weak UIViewController<ExtendedInteractionDefining> *weakAlert = alert;
    __weak UIScene *weakScene = scene;
    [alert addInteractionCompletion:^{
        [[[self controller] currentlyPresentedInteractionControllers] removeObject:weakAlert];
        if (interactionCompletionHandler != nil) {
            interactionCompletionHandler();
        }
        if (parentAction != nil) {
            [parentAction extendedActionComplete];
        } else {
            __strong UIScene *strongScene = weakScene;
            if (strongScene != nil) {
                [[self controller] _presentNextEnqueuedInteractionControllerOnScene:strongScene];
            }
        }
    }];
}

+ (BOOL)hasEnqueuedInteractionControllers;
{
    return [[self.controller enqueuedInteractionControllerContexts] count] > 0;
}

- (void)resetKeychain;
{
    OBFinishPortingWithNote("<bug:///147851> (iOS-OmniOutliner Engineering: Make resetKeychain public? Move the credential stuff into OmniFoundation instead of OmniFileStore?)");
//    OUIDeleteAllCredentials();
}

- (NSOperationQueue *)backgroundPromptQueue;
{
    @synchronized (self) {
        if (!_backgroundPromptQueue) {
            _backgroundPromptQueue = [[NSOperationQueue alloc] init];
            _backgroundPromptQueue.maxConcurrentOperationCount = 1;
            _backgroundPromptQueue.qualityOfService = NSQualityOfServiceUserInitiated;
            _backgroundPromptQueue.name = @"Serialized Queue for Background-Initiated Prompts";
        }
        return _backgroundPromptQueue;
    }
}

- (NSURL *)helpForwardURL;
{
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"https";
    components.host = @"www.omnigroup.com";

    NSString *path = @"/forward/documentation/html";

    // Deliberately use the app bundle, not OMNI_BUNDLE – we want to redirect to the running app's documentation
    path = [path stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];

    // Only use language codes we localize into, and when all else fails, fall back to English
    NSString *languageCode = [[[NSBundle mainBundle] preferredLocalizations] firstObject] ?: @"en";
    path = [path stringByAppendingPathComponent:languageCode];

    // Clean the version string through OFVersionNumber so that it doesn't include "private test" or other suffixes
    NSString *versionString = OB_CHECKED_CAST(NSString, [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
    OFVersionNumber *versionNumber = [[OFVersionNumber alloc] initWithVersionString:versionString];
    path = [path stringByAppendingPathComponent:[versionNumber cleanVersionString]];

    components.path = path;

    NSMutableArray <NSURLQueryItem *> *queryItems = [[NSMutableArray alloc] init];
    NSString *helpEdition = [[self class] helpEdition];
    if (helpEdition != nil) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"edition" value:helpEdition]];
    }
#if TARGET_OS_IOS
    [queryItems addObject:[NSURLQueryItem queryItemWithName:@"platform" value:@"iOS"]];
#endif
    if (queryItems.count > 0) {
        components.queryItems = queryItems;
    }
    return [components URL];
}

- (NSURL *)onlineHelpURL;
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *helpBookName = [mainBundle objectForInfoDictionaryKey:OUIHelpBookNameKey];
    if ([NSString isEmptyString:helpBookName])
        return nil;

    NSString *helpBookFolder = [mainBundle objectForInfoDictionaryKey:@"OUIHelpBookFolder"];
    if (helpBookFolder == nil) {
        return [self helpForwardURL];
    }

    NSString *helpEdition = [[self class] helpEdition];
    if (helpEdition != nil) {
        helpBookFolder = [helpBookFolder stringByAppendingPathComponent:helpEdition];
    }

    NSURL *helpIndexURL = [mainBundle URLForResource:@"index" withExtension:@"html" subdirectory:helpBookFolder];

    if (helpIndexURL == nil) {
        helpIndexURL = [mainBundle URLForResource:@"contents" withExtension:@"html" subdirectory:helpBookFolder];
    }

    if (helpIndexURL == nil) {
        helpIndexURL = [mainBundle URLForResource:@"top" withExtension:@"html" subdirectory:helpBookFolder];
    }

    OBASSERT(helpIndexURL != nil);
    return helpIndexURL;
}

- (BOOL)hasOnlineHelp;
{
    return [self onlineHelpURL] != nil;
}

- (void)setShouldPostponeLaunchActions:(BOOL)shouldPostpone;
{
    OBPRECONDITION(_shouldPostponeLaunchActions != shouldPostpone);
    
    _shouldPostponeLaunchActions = shouldPostpone;
    
    // Invoking actions might re-postpone.
    while (!_shouldPostponeLaunchActions && [_launchActions count] > 0) {
        void (^launchAction)(void) = [_launchActions objectAtIndex:0];
        [_launchActions removeObjectAtIndex:0];
        
        launchAction();
    }
}

- (void)addLaunchAction:(void (^)(void))launchAction;
{
    if (!_shouldPostponeLaunchActions) {
        launchAction();
        return;
    }

    if (!_launchActions)
        _launchActions = [NSMutableArray new];
    
    launchAction = [launchAction copy];
    [_launchActions addObject:launchAction];
}

- (void)setCanDequeueQueuedInteractions:(BOOL)canDequeueQueuedInteractions
{
    BOOL shouldDequeueInteractionImmediatelyIfPossible = !_canDequeueQueuedInteractions && canDequeueQueuedInteractions;
    UIScene *mostRecentlyActiveScene = [self mostRecentlyActiveScene];
    BOOL hasSomeForegroundScene = [mostRecentlyActiveScene activationState] == UISceneActivationStateForegroundActive;
    _canDequeueQueuedInteractions = canDequeueQueuedInteractions;
    // If we don't have a foreground scene, we'll dequeue this alert when some scene hits the foreground.
    if (shouldDequeueInteractionImmediatelyIfPossible && hasSomeForegroundScene) {
        [self _presentNextEnqueuedInteractionControllerOnScene:mostRecentlyActiveScene];
    }
}

- (BOOL)canDequeueQueuedInteractions
{
    return _canDequeueQueuedInteractions;
}

#pragma mark - UIApplication lifecycle subclassing points

- (void)applicationDidBecomeActive;
{
    DEBUG_STATE(1, "Did become active");
}

- (void)applicationWillResignActive;
{
    DEBUG_STATE(1, "Will resign active");
}

- (void)applicationWillEnterForeground;
{
    DEBUG_STATE(1, "Will enter foreground");
}

- (void)applicationDidEnterBackground;
{
    DEBUG_STATE(1, "Did enter background");

    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (UIResponder *)defaultFirstResponder;
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    return [UIApplication sharedApplication].keyWindow;

#pragma clang diagnostic pop
}

#pragma mark - Subclass responsibility

- (BOOL)supportsAppleWatch
{
    return NO;
}

- (NSString *)appSpecificDebugInfo
{
    return @"";
}

- (void)addFilesToAppDebugInfoWithHandler:(void (^ _Nonnull)(NSURL * _Nonnull))handler;
{

}

- (NSArray <OUIMenuOption *> *)additionalAppMenuOptionsAtPosition:(OUIAppMenuOptionPosition)position;
{
    return @[];
}

- (BOOL)isRunningRetailDemo;
{
    return [[OFPreference preferenceForKey:@"IPadRetailDemo"] boolValue];
}

- (BOOL)showFeatureDisabledForRetailDemoAlertFromViewController:(UIViewController *)presentingViewController;
{
    if ([self isRunningRetailDemo]) {
        NSString *alertString;
        NSString *alertMessage;
        UIViewController <OUIDisabledDemoFeatureAlerter>* alerter = (UIViewController <OUIDisabledDemoFeatureAlerter>*)presentingViewController;
        alertString = [alerter featureDisabledForDemoAlertTitle];
        if ([alerter respondsToSelector:@selector(featureDisabledForDemoAlertMessage)]) {
            alertMessage = [alerter featureDisabledForDemoAlertMessage];
        }
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:alertString message:alertMessage preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Done", @"OmniUI", OMNI_BUNDLE, @"Done") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {}]];

        [presentingViewController presentViewController:alertController animated:YES completion:NULL];

        return YES;
    }
    
    return NO;
}

- (NSString *)currentSKU
{
    return @"";
}

- (NSString *)purchaseDateString
{
    return @"";
}

- (NSString *)_versionString;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *testFlightString = [[self class] inSandboxStore] ? @" TestFlight" : @"";
    NSString *appEdition = [[self class] applicationEdition];
    NSString *editionString = [NSString isEmptyString:appEdition] ? @"" : [@" " stringByAppendingString:appEdition];
    return [NSString stringWithFormat:@"%@%@%@ (v%@)", [infoDictionary objectForKey:@"CFBundleShortVersionString"], editionString, testFlightString, [infoDictionary objectForKey:@"CFBundleVersion"]];
}

- (NSString *)fullReleaseString;
{
    NSString *baseString = [NSString stringWithFormat:@"%@ %@", [[self class] applicationName], self._versionString];
    
    NSString *currentSKU = [self currentSKU];
    if (![NSString isEmptyString:currentSKU]) {
        baseString = [baseString stringByAppendingString:[NSString stringWithFormat:@": %@", currentSKU]];
        NSString *purchaseDateString = [self purchaseDateString];
        if (![NSString isEmptyString:purchaseDateString]) {
            baseString = [baseString stringByAppendingString:[NSString stringWithFormat:@"/%@", purchaseDateString]];
        }
    }
    
    return baseString;
}

- (NSString *)_feedbackAddress;
{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIFeedbackAddress"];
}

- (NSURL *)_feedbackURLWithSubject:(NSString *)subject body:(nullable NSString *)body;
{
    NSString *feedbackAddress = [self _feedbackAddress];
    NSString *urlString = [NSString stringWithFormat:@"mailto:%@?subject=%@", feedbackAddress,
                           [NSString encodeURLString:subject asQuery:NO leaveSlashes:NO leaveColons:NO]];
    if (![NSString isEmptyString:body])
        urlString = [urlString stringByAppendingFormat:@"&body=%@", [NSString encodeURLString:body asQuery:NO leaveSlashes:NO leaveColons:NO]];
    return [NSURL URLWithString:urlString];
}

- (NSString *)_defaultFeedbackSubject;
{
    UIDevice *currentDevice = UIDevice.currentDevice;
    return [NSString stringWithFormat:@"%@ Feedback (%@ %@)", self.fullReleaseString, currentDevice.systemName, currentDevice.systemVersion];
}

- (NSURL *)_defaultFeedbackURL;
{
    return [self _feedbackURLWithSubject:[self _defaultFeedbackSubject] body:nil];
}

- (void)sendFeedbackWithSubject:(NSString * _Nullable)subject body:(NSString * _Nullable)body inScene:(nullable UIScene *)scene completion:(void (^ _Nullable)(void))mailInteractionCompletionHandler;
{
    // May need to allow the app delegate to provide this conditionally later (OmniFocus has a retail build, for example)
    NSString *feedbackAddress = [self _feedbackAddress];
    OBASSERT(feedbackAddress != nil);
    if (feedbackAddress == nil) {
        NSError *error = nil;
        OUIErrorWithInfo(&error, OUISendFeedbackError, NSLocalizedStringFromTableInBundle(@"Unable to send feedback", @"OmniUI", OMNI_BUNDLE, @"Feedback error description"), NSLocalizedStringFromTableInBundle(@"Internal error: this app has no feedback address configured.", @"OmniUI", OMNI_BUNDLE, @"Feedback error reason"), OUIShouldOfferToReportErrorUserInfoKey, @(NO), nil);
        OUI_PRESENT_ALERT_IN_SCENE(error, scene);
        if (mailInteractionCompletionHandler != nil) {
            mailInteractionCompletionHandler();
        }
        return;
    }

    MFMailComposeViewController *controller = [self newMailComposeController];
    if (controller == nil) {
        
        NSMutableString *mailtoURLString = [NSMutableString stringWithString:@"mailto:"];
        BOOL hasAppendedDelimeter = NO;
        
        #define APPEND_DELIMITER() do { \
            [mailtoURLString appendString:(hasAppendedDelimeter ? @"&" : @"?")]; \
            hasAppendedDelimeter = YES; \
        } while (NO)
        
        
        if (![NSString isEmptyString:feedbackAddress]) {
            NSArray *emailComponents = [feedbackAddress componentsSeparatedByString:@"@"];
            OBASSERT(emailComponents.count == 2); // No processing of email address performed. Will be up to the user to correct any issues from malformed mailto user/host.
            if (emailComponents.count == 2) {
                NSString *user = emailComponents.firstObject;
                user = [user stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLUserAllowedCharacterSet];

                NSString *host = emailComponents.lastObject;
                host = [host stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLHostAllowedCharacterSet];

                [mailtoURLString appendFormat:@"%@@%@", user, host];
            } else {
                [mailtoURLString appendString:feedbackAddress];
            }
            
        }
        
        if (![NSString isEmptyString:subject]) {
            APPEND_DELIMITER();
            [mailtoURLString appendFormat:@"subject=%@", [subject stringByAddingPercentEncodingWithURLQueryAllowedCharactersForQueryArgumentAssumingAmpersandDelimiter]];
        }
        
        if (![NSString isEmptyString:body]) {
            APPEND_DELIMITER();
            [mailtoURLString appendFormat:@"body=%@", [body stringByAddingPercentEncodingWithURLQueryAllowedCharactersForQueryArgumentAssumingAmpersandDelimiter]];
        }
        
        NSURL *mailtoURL = [NSURL URLWithString:mailtoURLString];
        [UIApplication.sharedApplication openURL:mailtoURL options:@{} completionHandler:nil];
        
        if (mailInteractionCompletionHandler != nil) {
            mailInteractionCompletionHandler();
        }
        return;
    }
    
    if (subject == nil)
        subject = [self _defaultFeedbackSubject];
    
    [controller setSubject:subject];
    
    // N.B. The static analyzer doesn't know that +isEmptyString: is also a null check, so we duplicate it here
    if (body != nil && ![NSString isEmptyString:body])
        [controller setMessageBody:body isHTML:NO];
    
    [self sendMailTo:[NSArray arrayWithObject:feedbackAddress] withComposeController:controller inScene:scene completion:mailInteractionCompletionHandler];
}

- (void)signUpForOmniNewsletterFromViewController:(UIViewController *)viewController NS_EXTENSION_UNAVAILABLE_IOS("Extensions cannot sign up for the Omni newsletter");
{
    OUIAppControllerSceneHelper *helper = [[OUIAppControllerSceneHelper alloc] init];
    helper.window = viewController.view.window;
    [helper signUpForOmniNewsletter:nil];
}

- (MFMailComposeViewController *)newMailComposeController {
    if (![MFMailComposeViewController canSendMail]) {
        return nil;
    }
    MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
    controller.navigationBar.barStyle = UIBarStyleDefault;
    controller.mailComposeDelegate = self;
    return controller;
}

- (void)sendMailTo:(NSArray<NSString *> *)recipients withComposeController:(MFMailComposeViewController *)mailComposeController inScene:(nullable UIScene *)scene
{
    [self sendMailTo:recipients withComposeController:mailComposeController inScene:scene completion:nil];
}

- (void)showSettingsFromViewController:(UIViewController *)viewController prefPaneToPush:(UIViewController *) paneToPush potentialDismissViewHandler:(void (^)(void))dismissHandler;
{
    // for subclasses
    return;
}

- (void)sendMailTo:(NSArray<NSString *> *)recipients withComposeController:(MFMailComposeViewController *)mailComposeController inScene:(nullable UIScene *)scene completion:(void (^ _Nullable)(void))mailInteractionCompletionHandler;
{
    UIWindow *window = [[self class] windowForScene:scene options:OUIWindowForSceneOptionsAllowFallbackLookup];

    OBASSERT(window.windowScene.activationState == UISceneActivationStateForegroundActive, "Presenting mail window on a background scene.");
    
    UIViewController *viewControllerToPresentFrom = [OUIAppController _viewControllerForPresentationInWindow:window];

    [mailComposeController setToRecipients:recipients];
    
    if (mailInteractionCompletionHandler != nil) {
        if (self.mailInteractionCompletionHandlersByScene == nil) {
            // Weakly hold the scenes, strongly hold the blocks
            self.mailInteractionCompletionHandlersByScene = [NSMapTable weakToStrongObjectsMapTable];
        }
        
        OBASSERT([self.mailInteractionCompletionHandlersByScene objectForKey:scene] == nil, "Did a completion handler not get run, or is there an existing mail interaction on this scene?");
        [self.mailInteractionCompletionHandlersByScene setObject:[mailInteractionCompletionHandler copy] forKey:scene];
    }
    
    [viewControllerToPresentFrom presentViewController:mailComposeController animated:YES completion:nil];
}

- (UIImage *)appMenuImage;
{
    NSString *imageName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIAppMenuImage"];
    if ([NSString isEmptyString:imageName]) {
        UIImage *gearImage = [UIImage systemImageNamed:@"gear"];
        if (gearImage != nil)
            return gearImage;

        imageName = @"OUIAppMenu.png";
    }
    return menuImage(imageName);
}

- (UIImage *)aboutMenuImage;
{
    return menuImage(@"OUIMenuItemAbout.png");
}

- (UIImage *)helpMenuImage;
{
    return menuImage(@"OUIMenuItemHelp.png");
}

- (UIImage *)sendFeedbackMenuImage;
{
    return menuImage(@"OUIMenuItemSendFeedback.png");
}

- (UIImage *)newsletterMenuImage;
{
    return menuImage(@"OUIMenuItemNewsletter.png");
}

- (UIImage *)announcementMenuImage;
{
    return menuImage(@"OUIMenuItemNews.png");
}

- (UIImage *)announcementBadgedMenuImage;
{
    return menuImage(@"OUIMenuItemNews-Badged.png");
}

- (UIImage *)releaseNotesMenuImage;
{
    return menuImage(@"OUIMenuItemReleaseNotes.png");
}

- (UIImage *)configureOmniPresenceMenuImage;
{
    return menuImage(@"OUIMenuItemOmniPresence.png");
}

- (UIImage *)settingsMenuImage;
{
    return menuImage(@"OUIMenuItemSettings.png");
}

- (UIImage *)omniAccountsMenuImage;
{
    return menuImage(@"OUIMenuItemOmniAccount.png");
}

- (UIImage *)inAppPurchasesMenuImage;
{
    return menuImage(@"OUIMenuItemPurchases.png");
}

- (UIImage *)registerMenuImage;
{
    return menuImage(@"OUIMenuItemRegister.png");
}

- (UIImage *)specialLicensingImage;
{
    return menuImage(@"OUIMenuItemLicensing");
}

- (UIImage *)quickStartMenuImage {
    return menuImage(@"OUIMenuItemQuickStart.png");
}

- (UIImage *)trialModeMenuImage {
    return menuImage(@"OUIMenuItemTrial.png");
}

- (UIImage *)introVideoMenuImage {
    return menuImage(@"OUIMenuItemVideo.png");
}

- (BOOL)useCompactBarButtonItemsIfApplicable;
{
    return NO;
}

- (UIImage *)exportBarButtonItemImageInViewController:(UIViewController *)viewController;
{
    UIImage *image = [UIImage systemImageNamed:@"square.and.arrow.up"];
    if (image != nil)
        return image;
    
    NSString *imageName = @"OUIExport";

    if (self.useCompactBarButtonItemsIfApplicable) {
        BOOL isHorizontallyCompact = viewController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
        BOOL isVerticallyCompact = viewController.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
        if (isHorizontallyCompact || isVerticallyCompact) {
            imageName = @"OUIExport-Compact";
        }
    }

    return [UIImage imageNamed:imageName inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

- (BOOL)canCreateNewDocument
{
    return YES;
}

- (BOOL)shouldEnableCreateNewDocument;
{
    return self.canCreateNewDocument;
}

- (void)unlockCreateNewDocumentInViewController:(UIViewController *)viewController withCompletionHandler:(void (^ __nonnull)(BOOL isUnlocked))completionBlock;
{
    completionBlock(self.canCreateNewDocument);
}

- (void)checkTemporaryLicensingStateInViewController:(UIViewController *)viewController withCompletionHandler:(void (^ __nullable)(void))completionHandler;
{
    if (completionHandler) {
        completionHandler();
    }
}

- (void)handleLicensingAuthenticationURL:(NSURL *)url presentationSource:(UIViewController *)presentationSource;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (BOOL)canHaveMultipleCrashReportScenes
{
    return YES;
}

#pragma mark - App menu support

- (NSString *)feedbackMenuTitle;
{
    OBASSERT_NOT_REACHED("Should be subclassed to provide something nicer.");
    return @"HALP ME!";
}

- (NSString *)omniAccountMenuTitle;
{
    NSString *title = NSLocalizedStringFromTableInBundle(@"Omni Account", @"OmniUI", OMNI_BUNDLE, @"Default title for the Omni Account menu item");
    return title;
}

- (NSString *)aboutMenuTitle;
{
    NSString *format = NSLocalizedStringFromTableInBundle(@"About %@", @"OmniUI", OMNI_BUNDLE, @"Default title for the About menu item");
    return [NSString stringWithFormat:format, [[self class] applicationName]];
}

- (NSString *)aboutScreenTitle;
{
    return [self aboutMenuTitle];
}

- (NSURL *)aboutScreenURL;
{
    OBRequestConcreteImplementation(self, _cmd);
}

NSString *const OUIAboutScreenBindingsDictionaryVersionStringKey = @"versionString";
NSString *const OUIAboutScreenBindingsDictionaryCopyrightStringKey = @"copyrightString";
NSString *const OUIAboutScreenBindingsDictionaryFeedbackAddressKey = @"feedbackAddress";

- (NSDictionary *)aboutScreenBindingsDictionary;
{
    // N.B.: specifically using mainBundle here rather than OMNI_BUNDLE because OmniUI will (hopefully) eventually become a framework.
    
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *versionString = self._versionString;
    NSString *copyrightString = infoDictionary[@"NSHumanReadableCopyright"];
    NSString *feedbackAddress = [self _feedbackAddress];
    
    return @{
             OUIAboutScreenBindingsDictionaryVersionStringKey : versionString,
             OUIAboutScreenBindingsDictionaryCopyrightStringKey : copyrightString,
             OUIAboutScreenBindingsDictionaryFeedbackAddressKey : feedbackAddress,
    };
}

#pragma mark App menu actions

- (void)setNewsURLStringToShowWhenReady:(NSString *)newsURLStringToShowWhenReady
{
    NeedToShowURLPreference.stringValue = newsURLStringToShowWhenReady != nil ? newsURLStringToShowWhenReady : @"";
    if (newsURLStringToShowWhenReady != nil) {
        // Post notification after saving the URL, so observers of the notification get correct property values when they query us.
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIAttentionSeekingNotification object:self userInfo:@{ OUIAttentionSeekingForNewsKey : @(YES) }];
    }
}

- (NSString *)newsURLStringToShowWhenReady
{
    NSString *stringValue = NeedToShowURLPreference.stringValue;
    return stringValue.length != 0 ? stringValue : nil;
}

- (BOOL)hasUnreadNews
{
    BOOL result = [self newsWantsAttention];
    return result;
}

- (BOOL)hasAnyNews
{
    BOOL result = !OFIsEmptyString([self mostRecentNewsURLString]);
    return result;
}

- (NSString *)mostRecentNewsURLString
{
    NSString *newsURLToShow = self.newsURLStringToShowWhenReady;
    if (newsURLToShow == nil) {
        NSArray<NSString *> *previouslyShown = PreviouslyShownURLsPreference.stringArrayValue;
        newsURLToShow = [previouslyShown lastObject];
    }
    return newsURLToShow;
}

- (BOOL)haveShownReleaseNotes:(NSString *)urlString
{
    NSArray<NSString *> *previouslyShown = PreviouslyShownURLsPreference.stringArrayValue;
    __block BOOL foundIt = NO;
    [previouslyShown enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj isEqualToString:urlString]) {
            foundIt = YES;
            *stop = YES;
        }
    }];
    return foundIt;
}

- (void)didShowReleaseNotes:(NSString *)urlString
{
    NSArray<NSString *> *previouslyShown = PreviouslyShownURLsPreference.stringArrayValue;
    if (!previouslyShown) {
        previouslyShown = @[];
    }
    if ([previouslyShown containsObject:urlString])
        return;

    previouslyShown = [previouslyShown arrayByAddingObject:urlString];
    PreviouslyShownURLsPreference.arrayValue = previouslyShown;
}

- (BOOL)newsWantsAttention
{
    return [self mostRecentNewsURLString].length > 0 && ![self haveShownReleaseNotes:self.mostRecentNewsURLString];
}

static UIImage *menuImage(NSString *name)
{
    UIImage *image = [[UIImage imageNamed:name inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!image)
        image = [UIImage imageNamed:name];
    
    OBASSERT(image);
    return image;
}

- (OUIMenuOption *)specialFirstAppMenuOption;
{
    // For subclass override
    return nil;
}

#pragma mark - UIResponder subclass

- (BOOL)canBecomeFirstResponder NS_EXTENSION_UNAVAILABLE_IOS("Not available in extensions.");
{
    // In some cases when the keyboard is dismissing (after editing a text view on a popover in one case), we'll lose first responder if we don't do something. UIKit normally seems to try to nominate the nearest nextResponder of the UITextView that is ending editing, but in the case of a popover it has no good recourse. It *does* ask the UIApplication and the application's delegate (at least in the case of it being a UIResponder subclass). We'll pass this off to an object nominated by subclasses.
    UIResponder *defaultFirstResponder = self.defaultFirstResponder;
    
    if (defaultFirstResponder == self)
        return [super canBecomeFirstResponder];
    return [defaultFirstResponder canBecomeFirstResponder];
}

- (BOOL)becomeFirstResponder NS_EXTENSION_UNAVAILABLE_IOS("Not available in extensions.");
{
    UIResponder *defaultFirstResponder = self.defaultFirstResponder;
    
    if (defaultFirstResponder == self)
        return [super becomeFirstResponder];
    return [defaultFirstResponder becomeFirstResponder];
}

- (id)targetForAction:(SEL)action withSender:(id)sender;
{
    // The documentation for -[UIResponder targetForAction:withSender:] seems to not be true in some base case. This can return 'self' if our nextResponder is nil (our -canPerformAction:withSender: doesn't get called in this case).
    id target = [super targetForAction:action withSender:sender];
    if (![target respondsToSelector:action])
        return nil;
    
    return target;
}

#pragma mark - UIApplicationDelegate

// For when running on iOS 3.2.
- (void)applicationWillTerminate:(UIApplication *)application;
{
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;
{
    [OAFontDescriptor forgetUnusedInstances];
}

#pragma mark -
#pragma mark MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        UIScene *scene = controller.containingScene;
        OBASSERT_NOTNULL(scene);
        [controller.presentingViewController dismissViewControllerAnimated:YES completion:^{
            void (^completion)(void) = [self.mailInteractionCompletionHandlersByScene objectForKey:scene];
            if (completion != nil) {
                completion();
                [self.mailInteractionCompletionHandlersByScene setObject:nil forKey:scene];
            }
            if (result == MFMailComposeResultFailed) {
                OUI_PRESENT_ALERT_IN_SCENE(error, scene);
            }
        }];
    }];
}

#pragma mark - Scene API

- (nullable UIScene *)mostRecentlyActiveScene
{
    return [self.connectedSceneStack peekAfterCompacting:YES];
}

- (nullable UIScene *)mostRecentlyActiveSceneSatisfyingCondition:(BOOL (^)(UIScene *))condition;
{
    return [self.connectedSceneStack firstElementSatisfyingCondition:condition];
}

- (NSArray<UIScene *> *)allConnectedScenesSatisfyingCondition:(BOOL (^)(UIScene *))condition;
{
    return [self.connectedSceneStack allElementsSatisfyingCondition:condition];
}

- (NSArray<UIScene *> *)allConnectedScenes
{
    return [self.connectedSceneStack allObjects];
}

#pragma mark - Private

- (nullable UIScene *)_findKeyWindowScene NS_EXTENSION_UNAVAILABLE_IOS("Calls into -[UIApplication sharedApplication]");
{
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if ([window isKeyWindow]) {
            return window.windowScene;
        }
    }
    
    return nil;
}

- (void)_sceneDidBecomeActive:(NSNotification *)notification NS_EXTENSION_UNAVAILABLE_IOS("Calls into -[UIApplication sharedApplication]");
{
    UIScene *newlyActiveScene = OB_CHECKED_CAST(UIScene, notification.object);
    UIScene *sceneForNextEnqueuedInteractionController = newlyActiveScene;

    // Push the newly active scene onto the stack so that we have a record of it for the future.
    // We could have also done this by listening for scene will connect, but there we wouldn't have wanted to push it on the stack.
    [self.connectedSceneStack push:newlyActiveScene uniquing:YES];

    // If the key scene is active, put that one back on the top of the stack because this is the one we want to interact with.
    //
    // We may decide, that absent any corrective behavior from Apple, we may wish to come up with some hueristic where newly added or activated scenes become key.
    // This logic may have to change slightly if that ends up being the case.
    UIScene *keyScene = [self _findKeyWindowScene];
    if (keyScene != newlyActiveScene && keyScene.activationState == UISceneActivationStateForegroundActive) {
         [self.connectedSceneStack push:keyScene uniquing:YES];

        // Clear this; the "most recently active" scene didn't actually change, so we don't want to start a presentation.
        sceneForNextEnqueuedInteractionController = nil;
    }

    if (sceneForNextEnqueuedInteractionController != nil) {
        [self _presentNextEnqueuedInteractionControllerOnScene:sceneForNextEnqueuedInteractionController];
    }
}

- (void)_presentNextEnqueuedInteractionControllerOnScene:(UIScene *)anActiveScene NS_EXTENSION_UNAVAILABLE_IOS("Calls into -[UIApplication sharedApplication]");
{
    OBPRECONDITION(anActiveScene.activationState == UISceneActivationStateForegroundActive);
    
    if (!_canDequeueQueuedInteractions) {
        return;
    }
    
    if (![[self class] hasEnqueuedInteractionControllers]) {
        return;
    }
    
    BOOL hasInteractionUpAlready = [[self currentlyPresentedInteractionControllers] anyObjectSatisfiesPredicate:^BOOL(UIViewController<ExtendedInteractionDefining> * _Nonnull controller) {
        return [controller containingScene] == anActiveScene;
    }];
    if (hasInteractionUpAlready) {
        return;
    }
    
    OUIEnqueueableInteractionControllerContext *context = self.enqueuedInteractionControllerContexts[0];
    
    UIScene *sceneForPresentation = anActiveScene;
    
    BOOL shouldDequeue = YES;
    UIViewController<ExtendedInteractionDefining> *controller;
    if (context.requiredScene == nil) {
        // This alert can be presented on any active scene. Dequeue it and present.
        controller = context.controller;
        
        // If there is a parent interaction, complete it instead of dequeuing
        OUIExtendedAlertAction *parentAction = context.parentExtendedAction;
        [OUIAppController _prepareInteraction:controller forImmediatePresentationOnScene:sceneForPresentation parentAction:parentAction interactionCompletionHandler:nil];
    } else if (context.requiredScene.activationState == UISceneActivationStateForegroundActive) {
        // This alert's required scene is foreground active. Dequeue it and present on the scene. (This can happen if multiple scenes are reactivated at once)
        sceneForPresentation = context.requiredScene;
        controller = context.controller;
        
        // If there is a parent interaction, complete it instead of dequeuing
        OUIExtendedAlertAction *parentAction = context.parentExtendedAction;
        [OUIAppController _prepareInteraction:controller forImmediatePresentationOnScene:sceneForPresentation parentAction:parentAction interactionCompletionHandler:nil];
    } else {
        // This alert's required scene is not on screen. Present an alert on the active scene offering to take the user to the alert. Be sure to not dequeue the alert.
        shouldDequeue = NO;
        
        NSString *alertTitleFormat = NSLocalizedStringFromTableInBundle(@"%@ is open in another window", @"OmniUI", OMNI_BUNDLE, @"Something open in another window alert title - the token is a short description of the activity open in the other window, for example: 'Account Setup'");
        NSString *alertTitle = [NSString stringWithFormat:alertTitleFormat, context.activityContextTitle];
        OUIEnqueueableAlertController *alert = [OUIEnqueueableAlertController alertControllerWithTitle:alertTitle message:nil preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *continueAction = [alert addActionWithTitle:context.activityContinuationButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            UISceneActivationRequestOptions *options = [[UISceneActivationRequestOptions alloc] init];
            options.requestingScene = anActiveScene;
            [[UIApplication sharedApplication] requestSceneSessionActivation:context.requiredScene.session userActivity:nil options:options errorHandler:^(NSError * _Nonnull error) {
                NSLog(@"Error switching scenes: %@", error);
                // The scene didn't activate, resume dequeuing any other alerts we may have, placing this one at the end so we aren't caught in a loop.
                [[self enqueuedInteractionControllerContexts] removeObject:context];
                [self _presentNextEnqueuedInteractionControllerOnScene:anActiveScene];
                [[self enqueuedInteractionControllerContexts] addObject:context];
            }];
        }];
        
        [alert addActionWithTitle:context.postponeActivityButtonTitle style:UIAlertActionStyleCancel handler:nil];
        
        // Encourage the user to handle the error that needed to be presented in a specific place.
        alert.preferredAction = continueAction;
        
        controller = alert;
        [OUIAppController _prepareInteraction:controller forImmediatePresentationOnScene:sceneForPresentation parentAction:nil interactionCompletionHandler:nil];
    }
    
    UIWindow *window = [[self class] windowForScene:sceneForPresentation options:OUIWindowForSceneOptionsNone];
    if (window == nil) {
        return;
    }
    
    if (shouldDequeue) {
        [[self enqueuedInteractionControllerContexts] removeObjectAtIndex:0];
    }
    
    UIViewController *controllerForPresentation = [OUIAppController _viewControllerForPresentationInWindow:window];
    [controllerForPresentation presentViewController:controller animated:YES completion:nil];
}

- (void)_windowDidBecomeKey:(NSNotification *)notification;
{
    UIWindow *window = OB_CHECKED_CAST(UIWindow, notification.object);
    UIScene *scene = window.windowScene;
    if (scene != nil) {
        [self.connectedSceneStack push:scene uniquing:YES];
    }
}

- (void)_oui_applicationDidBecomeActive:(NSNotification *)notification NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    [self applicationDidBecomeActive];
}

- (void)_oui_applicationWillResignActive:(NSNotification *)notification NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    [self applicationWillResignActive];
}

- (void)_oui_applicationWillEnterForeground:(NSNotification *)notification NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    // Debounce the case of active -> inactive -> active
    if (_applicationInForeground) {
        return;
    }
    _applicationInForeground = YES;
    [self applicationWillEnterForeground];
}

- (void)_oui_applicationDidEnterBackground:(NSNotification *)notification NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    // Debounce the case of background -> inactive -> background, if that ever happens.
    if (!_applicationInForeground) {
        return;
    }
    _applicationInForeground = NO;
    [self applicationDidEnterBackground];
}

@end

@implementation UIViewController (OUIDisabledDemoFeatureAlerter)
- (NSString *)featureDisabledForDemoAlertTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Feature not enabled for this demo", @"OmniUI", OMNI_BUNDLE, @"disabled for demo");
}
@end

@implementation OUIEnqueueableInteractionControllerContext


+ (OUIEnqueueableInteractionControllerContext *)contextWithInteractionController:(UIViewController<ExtendedInteractionDefining> *)alert parentExtendedAction:(nullable OUIExtendedAlertAction *)parentAction presentationCompletionHandler:(void (^ __nullable)(void))presentationCompletionHandler;
{
    return [[OUIEnqueueableInteractionControllerContext alloc] initWithInteractionController:alert parentExtendedAction:parentAction requiredScene:nil activityContextTitle:nil activityContinuationButtonTitle:nil postponeActivityButtonTitle:nil presentationCompletionHandler: presentationCompletionHandler];
}

- (instancetype)initWithInteractionController:(UIViewController<ExtendedInteractionDefining> *)controller parentExtendedAction:(nullable OUIExtendedAlertAction *)parentAction requiredScene:(nullable UIScene *)scene activityContextTitle:(NSString *)activityContextTitle activityContinuationButtonTitle:(NSString *)activityContinuationButtonTitle postponeActivityButtonTitle:(NSString *)postponeActivityButtonTitle presentationCompletionHandler:(void (^ __nullable)(void))presentationCompletionHandler;
{
    if (self = [super init]) {
        _controller = controller;
        _parentExtendedAction = parentAction;
        _requiredScene = scene;
        _activityContextTitle = activityContextTitle;
        _activityContinuationButtonTitle = activityContinuationButtonTitle;
        _postponeActivityButtonTitle = postponeActivityButtonTitle;
        _presentationCompletionHandler = [presentationCompletionHandler copy];
    }
    return self;
}

@end
