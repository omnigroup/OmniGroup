// Copyright 1998-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSUserNotification.h>

NS_ASSUME_NONNULL_BEGIN

@class OFInvocation, OFMessageQueue;
@class NSBundle, NSException, NSExceptionHandler, NSLock, NSMutableArray, NSMutableSet, NSNotification;

typedef NS_ENUM(NSInteger, OFControllerStatus) {
    OFControllerStatusNotInitialized,
    OFControllerStatusInitialized,
    OFControllerStatusRunning,
    OFControllerStatusRequestingTerminate,
    OFControllerStatusPostponingTerminate,
    OFControllerStatusTerminating
};

typedef NS_ENUM(NSInteger, OFControllerTerminateReply) {
    OFControllerTerminateCancel,
    OFControllerTerminateNow,
    OFControllerTerminateLater
};

// Support for dispatching notifications to different subsystems. +[OFController sharedController] will be the delegate of the notification center.
@protocol OFNotificationOwner <NSUserNotificationCenterDelegate>
- (BOOL)ownsNotification:(NSUserNotification *)notification;
@end
@protocol OFControllerStatusObserver;

@interface OFController : NSObject <NSUserNotificationCenterDelegate>

+ (NSBundle *)controllingBundle;
+ (BOOL)isRunningUnitTests;

+ (instancetype)sharedController;
- (void)becameSharedController NS_REQUIRES_SUPER;

- (OFControllerStatus)status;

// Only a weak reference is made to the observer via OFWeakReference
- (void)addStatusObserver:(id <OFControllerStatusObserver>)observer;
- (void)removeStatusObserver:(id <OFControllerStatusObserver>)observer;

// A simplified way to perform an action at a specific point in the app's lifecycle without going to the trouble of being an observer
- (void)queueSelector:(SEL)message forObject:(NSObject *)receiver whenStatus:(OFControllerStatus)state;
- (void)queueInvocation:(OFInvocation *)action whenStatus:(OFControllerStatus)state;
- (void)performBlock:(void (^)(void))block whenStatus:(OFControllerStatus)state;

- (void)didInitialize;
- (void)startedRunning;
- (OFControllerTerminateReply)requestTermination;
- (void)cancelTermination;

// postponeTermination: should be called by OFController observers as soon as they go into a state from which it would be bad to unexpectedly terminate (as in the middle of a bookmark sync, to use OmniWeb as an example).
- (void)postponeTermination:(id)observer;
// continuePostponedTermination: should be called as soon as the operation is finished.
- (void)continuePostponedTermination:(id)observer;

// Call -willTerminate: from your application delegate's implementation of -applicationWillTerminate:, or if you aren't AppKit-based as soon as you're about to quit (after -gotPostponedTerminateResult: has been called, if anyone called -postponeTermination).
- (void)willTerminate;
- (void)gotPostponedTerminateResult:(BOOL)isReadyToTerminate;

- (unsigned int)exceptionHandlingMask;

- (void)crashWithReport:(NSString *)report;
- (void)crashWithException:(NSException *)exception mask:(NSUInteger)mask;
- (BOOL)shouldLogException:(NSException *)exception mask:(NSUInteger)aMask;

// NSAssertionHandler customization
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,... NS_FORMAT_FUNCTION(5,6);
- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,... NS_FORMAT_FUNCTION(4,5);

// varargs aware versions of the methods above.
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line format:(NSString *)format arguments:(va_list)args;
- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line format:(NSString *)format arguments:(va_list)args;

// NSExceptionHandler delegate
- (BOOL)exceptionHandler:(NSExceptionHandler *)sender shouldLogException:(NSException *)exception mask:(NSUInteger)aMask;

// Support for splitting out ownership of NSUserNotifications across different subsystems.
- (void)addNotificationOwner:(id <OFNotificationOwner>)notificationOwner;
- (void)removeNotificationOwner:(id <OFNotificationOwner>)notificationOwner;

// OFController has concrete implementations of the following NSUserNotificationCenterDelegate methods. If you override these methods, be sure to call super's implementation.
- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification NS_REQUIRES_SUPER;
- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification NS_REQUIRES_SUPER;
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification NS_REQUIRES_SUPER;

@end

@protocol OFControllerStatusObserver <NSObject>

@optional

/*"
The OFControllerStatusObserver informal protocol describes the methods that will be called on an object if it subscribes to OFController notifications by calling -addObserver: on OFController.
*/

- (void)controllerDidInitialize:(OFController *)controller;
/*"
Called when -[OFController didInitialize] is called.  This notification is for setting up a class (reading defaults, etc.).  At this point it shouldn't rely on any other classes (except OFUserDefaults) being set up yet.
"*/

- (void)controllerStartedRunning:(OFController *)controller;
/*"
Called when -[OFController startedRunning] is called.  This notification is for resetting the state of a class to the way it was when the user last left the program:  for instance, popping up a window that was open.
"*/

- (void)controllerRequestsTerminate:(OFController *)controller;
/*"
Called when -[OFController requestTermination] is called.  This notification gives objects an opportunity to save documents, etc., when an application is considering terminating.  If the application does not wish to terminate (maybe the user cancelled the terminate request), it should call -cancelTermination on the OFController.
"*/

- (void)controllerCancelledTermnation:(OFController *)controller;
/*"
 Called when -[OFController cancelTermniation] is called.
 "*/

- (void)controllerWillTerminate:(OFController *)controller;
/*"
Called when -[OFController willTerminate] is called.  This notification is posted by the OFController just before the application terminates, when there's no chance that the termination will be cancelled).  This may be used to wait for a particular activity (e.g. an asynchronous document save) before the application finally terminates.
"*/

@end

NS_ASSUME_NONNULL_END
