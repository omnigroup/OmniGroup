// Copyright 1998-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OFInvocation, OFMessageQueue;
@class NSBundle, NSException, NSExceptionHandler, NSLock, NSMutableArray, NSMutableSet, NSNotification;

typedef enum _OFControllerStatus {
    OFControllerNotInitializedStatus,
    OFControllerInitializedStatus,
    OFControllerRunningStatus,
    OFControllerRequestingTerminateStatus,
    OFControllerPostponingTerminateStatus,
    OFControllerTerminatingStatus
} OFControllerStatus;

typedef enum _OFControllerTerminateReply {
    OFControllerTerminateCancel,
    OFControllerTerminateNow,
    OFControllerTerminateLater
} OFControllerTerminateReply;

@interface OFController : NSObject

+ (NSBundle *)controllingBundle;

+ (instancetype)sharedController;

- (OFControllerStatus)status;

// Only a weak reference is made to the observer via OFWeakReference
- (void)addObserver:(id)observer;
- (void)removeObserver:(id)observer;

// A simplified way to perform an action at a specific point in the app's lifecycle without going to the trouble of being an observer
- (void)queueSelector:(SEL)message forObject:(NSObject *)receiver whenStatus:(OFControllerStatus)state;
- (void)queueInvocation:(OFInvocation *)action whenStatus:(OFControllerStatus)state;

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
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,...;
- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,...;

// varargs aware versions of the methods above.
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line format:(NSString *)format arguments:(va_list)args;
- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line format:(NSString *)format arguments:(va_list)args;

// NSExceptionHandler delegate
- (BOOL)exceptionHandler:(NSExceptionHandler *)sender shouldLogException:(NSException *)exception mask:(NSUInteger)aMask;

@end

@interface NSObject (OFControllerObserver)
/*"
The OFControllerObserver informal protocol describes the methods that will be called on an object if it subscribes to OFController notifications by calling -addObserver: on OFController.
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

- (void)controllerWillTerminate:(OFController *)controller;
/*"
Called when -[OFController willTerminate] is called.  This notification is posted by the OFController just before the application terminates, when there's no chance that the termination will be cancelled).  This may be used to wait for a particular activity (e.g. an asynchronous document save) before the application finally terminates.
"*/

@end
