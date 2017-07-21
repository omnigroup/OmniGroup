// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBLoadAction.h>

#import <OmniBase/OBRuntimeCheck.h>
#import <OmniBase/OBUtilities.h>
#import <OmniBase/macros.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

#if 0 && defined(DEBUG)
    #define LOADACTION_DEBUG(format, ...) NSLog(@"LOAD ACTION: " format, ## __VA_ARGS__)
#else
    #define LOADACTION_DEBUG(format, ...) do {} while (0)
#endif

/*

 We want to deal in packets of "perform posing" and "did load" actions where bundle loading notifications (or the first call after execution starts) provides the separator between packets. But, actions can themselves cause more actions to be registered, and we don't want to process those packets of actions until after their bundle is done loading, and we don't want to re-order actions across bundle load seperators. We also want OBInvokeRegisteredLoadActions() to not return until the actions registered to that point have been executed.

 So, consider the following case:

 - execution starts
 - constructors register actions A, B, C
 - somewhere in main(), call OBInvokeRegisteredLoadActions()
 - Action B is invoked and ends up loading a bundle
 - Action D is registered
 - Bundle load notifiction posted, and OBInvokeRegisteredLoadActions() called

 The nested call to OBInvokeRegisteredLoadActions() needs to invoke action C and D; it can't block waiting for the first OBInvokeRegisteredLoadActions() to do C since it would then deadlock.
 
 So, we stage actions into individual arrays (since all "perform posings" actions from a bundle should be done before the "did load" actions). At the sequence points, these actions are collected into an execution array. Each invocation of OBInvokeRegisteredLoadActions() will process all the actions before the most recent sequence point.

 We use a recursive lock so that actions can call back to register more actions, but any call to OBInvokeRegisteredLoadActions() will completely execute all previously noted sequence points.

 */

static dispatch_once_t LoadActionOnceToken;
static NSRecursiveLock *LoadActionLock;

// Staging arrays
static NSMutableArray <OBLoadAction> *PerformPosingActions;
static NSMutableArray <OBLoadAction> *DidLoadActions;

// Execution
static NSMutableArray <OBLoadAction> *ExecutableActions;
static NSUInteger NextExecutionIndex;

static void _InitializeLoadActions(void)
{
    dispatch_once(&LoadActionOnceToken, ^{
        LoadActionLock = [[NSRecursiveLock alloc] init];
        PerformPosingActions = [[NSMutableArray alloc] init];
        DidLoadActions = [[NSMutableArray alloc] init];
        ExecutableActions = [[NSMutableArray alloc] init];

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
        // Note: adding this observation block on iOS causes a hang in CoreAnimation when initializing a UIWebView
        [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note){
            LOADACTION_DEBUG(@"Bundle loaded %@", note.object);
            OBInvokeRegisteredLoadActions();
        }];
#endif
    });
}

void _OBRegisterLoadAction(OBLoadActionKind kind, const char *file, unsigned line, OBLoadAction action)
{
    _InitializeLoadActions();

    [LoadActionLock lock];

    LOADACTION_DEBUG(@"Register load action of kind %ld from %s:%d", kind, file, line);

    // Note: even if we are past the first call of OBInvokeRegisteredLoadActions(), we should buffer these up so that a runtime loaded bundle that uses both kinds of load actions will have its perform-posing actions called, and then its did-load actions.
    switch (kind) {
        case OBLoadActionKindPerformPosing:
            [PerformPosingActions addObject:action];
            break;
        case OBLoadActionKindDidLoad:
            [DidLoadActions addObject:action];
            break;
        default:
            OBASSERT_NOT_REACHED("Unrecognized action kind %ld", kind);
    }

    [LoadActionLock unlock];
}

void OBInvokeRegisteredLoadActions(void)
{
    _InitializeLoadActions();

#ifdef OMNI_ASSERTIONS_ON
    BOOL didExecuteAction = NO;
#endif

    [LoadActionLock lock];

    LOADACTION_DEBUG(@"Sequence point with %ld perform-posing and %ld did-load actions", [PerformPosingActions count], [DidLoadActions count]);

    [ExecutableActions addObjectsFromArray:PerformPosingActions];
    [PerformPosingActions removeAllObjects];

    [ExecutableActions addObjectsFromArray:DidLoadActions];
    [DidLoadActions removeAllObjects];

    if ([ExecutableActions count] > 0) {
        LOADACTION_DEBUG(@"Invoking load actions up to %ld, starting from %ld", [ExecutableActions count], NextExecutionIndex);

        // Intentionally calling -count on each loop since the action might reeentrantly call us and the reentrant call will finish the work we started.
        while (NextExecutionIndex < [ExecutableActions count]) {
            OBLoadAction action = ExecutableActions[NextExecutionIndex];
            NextExecutionIndex++;

            @autoreleasepool {
#ifdef OMNI_ASSERTIONS_ON
                didExecuteAction = YES;
#endif
                action();
            }
        }

        OBASSERT(NextExecutionIndex == [ExecutableActions count]);

        if (NextExecutionIndex != 0) {
            LOADACTION_DEBUG(@"Done invoking load actions -- clearing");
            [ExecutableActions removeAllObjects];
            NextExecutionIndex = 0;
        } else {
            // Reentrantly call finished our work.
            LOADACTION_DEBUG(@"Reentrant call already cleared finished actions");
        }
    }

    [LoadActionLock unlock];

#ifdef OMNI_ASSERTIONS_ON
    if (didExecuteAction) {
        dispatch_async(dispatch_get_main_queue(), ^{
            OBRequestRuntimeChecks();
        });
    }
#endif
}
