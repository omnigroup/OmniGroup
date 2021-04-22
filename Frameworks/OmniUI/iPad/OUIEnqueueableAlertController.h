// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIResponder.h>

NS_ASSUME_NONNULL_BEGIN

// In a multi-scene context, we need to be able to enqueue important interactions so that we can be assured that a user will see them. If every scene is backgrounded, then we can't know where to present something as the user may foreground any of the existing scenes. So, in that situation, we build up a queue of interactions and present them one at a time on whichever scene is foregrounded first. The actual enqueuing of these interactions is done via API on OUIAppController. This file defines the objects that are supplied to that enqueuing API.
// In order to enqueue an interaction, we need to know when a given interaction is "complete" so that we can then present the next enqueued thing. Most enqueued interactions will be alerts for presenting errors to the user. For most alerts, you read about an error, hit "OK", and you're done. At that point, the interaction is complete. But, we sometimes also need to enqueue "longer" interactions, like presenting a mail sheet for the user to send Omni feedback. In that case, the interaction is complete after the user has either sent the feedback email, or cancelled it. Another "longer" example is an alert needs a "Retry" button for an asynchronous operation that resulted in an error. That interaction is complete either when the asynchronous operation succeeds, or the user decides to cancel attempting it. There are also situations in which we'd like to enqueue non-alert interactions. For example, OmniFocus occassionally wants to prompt the user to migrate their database to enable new capabilities.
// The protocol below exists so that any UIViewController subclass can define the end of its interaction. Also, since alerts are the most common thing to enqueue, OUIEnqueueableAlertController is defined below. OUIEnqueueableAlertController accepts two kinds of alert actions: simple "OK and you're done" actions, and extended actions that spawn off some additional flow.

// This protocol is only ever adopted by UIViewController subclasses in practice. In general, interaction completion should defined as the point at which the UI elements that implement this protocol are no longer visible on screen, and the surrounding app is ready to potentially present a new Extended Interaction.
@protocol ExtendedInteractionDefining

// The implementer is responsible for calling these blocks when the interaction it defines is complete.
- (void)addInteractionCompletion:(void (^)(void))interactionCompletionHandler;

@end

#pragma mark -

// If an OUIEnqueueableAlertController instance requires an action that presents some UI (such as a progress indicator, a subsequent alert, etc.) then that action's handler MUST be an OUIExtendedAlertAction, and the caller must call the -extendedActionComplete method when that extended interaction is complete.
@interface OUIExtendedAlertAction: UIAlertAction <ExtendedInteractionDefining>

+ (instancetype)extendedActionWithTitle:(nullable NSString *)title style:(UIAlertActionStyle)style handler:(void (^ __nonnull)(OUIExtendedAlertAction *action))handler;

// This alert action forwards the interaction definition onto its creator. Usually, a block containing a call to this method is passed off to a view controller that gets presented in the body of this action's handler.
// This must be called when the extended interaction triggered by this action is complete.
- (void)extendedActionComplete;

@end

#pragma mark -

// Alert controllers must be this subclass in order to be eligible for enqueing for presentation.
// Additionally, callers cannot call -[OUIEnqueueableAlertControllereableAlertController addAction:]. Instead, depending on the type of action you'd like to add, call one of the two methods provided below.
@interface OUIEnqueueableAlertController: UIAlertController <ExtendedInteractionDefining>

- (void)addAction:(UIAlertAction *)action NS_UNAVAILABLE;

// The handler for these actions spawns some sort of extended flow. When that flow is complete, it is the responsibility of the creator of this action to call its extendedActionComplete method. For example, an extended action could begin an asynchronous operation and put up a progress indicator while awaiting an answer. Once the operation is complete, the caller would remove the progress indicator from the view hierarchy and call the action's -extendedActionComplete method. If this alert controller is enqueued with OUIAppController, then it is possible the controller will immediately dequeue and present another alert as soon as -extendedActionComplete is called.
- (void)addExtendedAction:(OUIExtendedAlertAction *)action;

// The logic performed in the handler for actions added via this method must not exit its scope. These handlers are suitable for one-and-done operations like changing a preference, or triggering a UINavigationController navigation. Once the handler returns, it is possible  another alert or interaction will be immediately dequeued and presented. If callers require subsequent user interaction or attention after the handler has returned, they should instead use an OUIExtendedAlertAction.
- (UIAlertAction *)addActionWithTitle:(nullable NSString *)title style:(UIAlertActionStyle)style handler:(void (^ __nullable)(UIAlertAction *action))handler;

// Can be set by callers if they would like some kind of identifier to be associated with this alert.
@property (nullable, strong, nonatomic) NSString *alertIdentifier;
@end

NS_ASSUME_NONNULL_END
