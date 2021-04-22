// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAnimationSequence.h>

#import <UIKit/UIView.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIInteractionLock.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG_bungi)
    #define DEBUG_SEQ(format, ...) NSLog(@"SEQ: " format, ## __VA_ARGS__)
#else
    #define DEBUG_SEQ(format, ...)
#endif

const NSTimeInterval OUIAnimationSequenceDefaultDuration = 0.2;
const NSTimeInterval OUIAnimationSequenceImmediateDuration = 0.0;

@implementation OUIAnimationSequence
{
    OUIInteractionLock *_lock;
    id _retainCycleWhileRunning;
    NSTimeInterval _duration;
    CFAbsoluteTime _startTime;
    NSArray *_steps;
    NSUInteger _stepIndex;
}

- _initWithDuration:(NSTimeInterval)duration steps:(NSArray *)steps;
{
    if (!(self = [super init]))
        return nil;
    _duration = duration;
    _steps = [steps copy];
    _stepIndex = [_steps count];
    return self;
}

- (void)_runNextStep NS_EXTENSION_UNAVAILABLE_IOS("");
{
    if (_stepIndex == 0) {
        // Done!
        DEBUG_SEQ(@"done at %f", CFAbsoluteTimeGetCurrent() - _startTime);
        [_lock unlock];
        _lock = nil;
        _retainCycleWhileRunning = nil; // Set up in -run
        return;
    }
    
    _stepIndex--;
    DEBUG_SEQ(@"running step %ld at %f", _stepIndex, CFAbsoluteTimeGetCurrent() - _startTime);
    id obj = [_steps objectAtIndex:_stepIndex];
    
    if ([obj isKindOfClass:[NSNumber class]]) {
        _duration = [obj doubleValue];
        [self _runNextStep];
        return;
    }
    
    void (^oneAction)(void) = (typeof(oneAction))obj;
    
    // We used to interpret a zero duration as meaing a default of 0.2, but now we treat it as meaning we should run that block w/o animation enabled.
    if (_duration == OUIAnimationSequenceImmediateDuration) {
        OUIWithoutAnimating(oneAction);
        [self _runNextStep];
    } else {
        [UIView animateWithDuration:_duration animations:oneAction
                         completion:^(BOOL finished){
                             [self _runNextStep];
                         }];
    }
}

- (void)_run NS_EXTENSION_UNAVAILABLE_IOS("");
{
    DEBUG_SEQ(@"steps = %@", _steps);
    
    // If animation is disabled, perform the blocks synchronously. They'd still get performed without any animated delay, but they'd be one after returning to the run loop. This approach makes it possible to have methods that animate or perform actions immediately and following code can depend on it being done.
    if (![UIView areAnimationsEnabled]) {
        DEBUG_SEQ(@"animation disabled; running synchronously");
        NSUInteger stepIndex = [_steps count];
        while (stepIndex--) {
            id step = [_steps objectAtIndex:stepIndex];
            if ([step isKindOfClass:[NSNumber class]])
                continue;
            void (^oneAction)(void) = (typeof(oneAction))step;
            oneAction();
        }
        return;
    }
    
    
    // Turn off interaction and fire up the animations.
    _lock = [OUIInteractionLock applicationLock];
    
    // so the caller can -release us w/o clang-sa complaining.
    _retainCycleWhileRunning = self;
    
    _startTime = CFAbsoluteTimeGetCurrent();
    [self _runNextStep];
}

+ (void)runWithDuration:(NSTimeInterval)duration actions:(void (^)(void))action, ...;
{
    OBPRECONDITION(action);
    
    // Collect all the blocks and time intervals into a reversed array.
    action = [action copy]; // promote stack blocks to heap.
    NSMutableArray *objects = [NSMutableArray arrayWithObjects:action, nil];
    
    {
        va_list args;
        va_start(args, action);
        id object;
        while ((object = va_arg(args, id))) {
            object = [object copy]; // promote stack blocks to heap.
            [objects insertObject:object atIndex:0];
        }
        va_end(args);
    }
    
    OUIAnimationSequence *seq = [[OUIAnimationSequence alloc] _initWithDuration:duration steps:objects];
    [seq _run]; // -retains the receiver until it is done
}

@end
