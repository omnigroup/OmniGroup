// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAnimationSequence.h>
#import <UIKit/UIView.h>

RCS_ID("$Id$");

#ifdef NS_BLOCKS_AVAILABLE

#if 0 && defined(DEBUG_bungi)
    #define DEBUG_SEQ(format, ...) NSLog(@"SEQ: " format, ## __VA_ARGS__)
#else
    #define DEBUG_SEQ(format, ...)
#endif

@implementation OUIAnimationSequence

- _initWithDuration:(NSTimeInterval)duration steps:(NSArray *)steps;
{
    if (!(self = [super init]))
        return nil;
    _duration = duration;
    _steps = [steps copy];
    _stepIndex = [_steps count];
    return self;
}

- (void)dealloc;
{
    [_steps release];
    [super dealloc];
}

- (void)_runNextStep;
{
    if (_stepIndex == 0) {
        // Done!
        DEBUG_SEQ(@"done at %f", CFAbsoluteTimeGetCurrent() - _startTime);
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        objc_msgSend(self, @selector(release)); // matching -run
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
    [UIView animateWithDuration:_duration > 0 ? _duration : 0.2
                     animations:oneAction
                     completion:^(BOOL finished){
                         [self _runNextStep];
                     }];
}

- (void)_run;
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
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    objc_msgSend(self, @selector(retain)); // so the caller can -release us w/o clang-sa complaining.
    
    _startTime = CFAbsoluteTimeGetCurrent();
    [self _runNextStep];
}

+ (void)runWithDuration:(NSTimeInterval)duration actions:(void (^)(void))action, ...;
{
    OBPRECONDITION(action);
    
    // Collect all the blocks and time intervals into a reversed array.
    action = [action copy]; // promote stack blocks to heap.
    NSMutableArray *objects = [NSMutableArray arrayWithObjects:action, nil];
    [action release];
    
    {
        va_list args;
        va_start(args, action);
        id object;
        while ((object = va_arg(args, id))) {
            object = [object copy]; // promote stack blocks to heap.
            [objects insertObject:object atIndex:0];
            [object release];
        }
        va_end(args);
    }
    
    OUIAnimationSequence *seq = [[OUIAnimationSequence alloc] _initWithDuration:duration steps:objects];
    [seq _run]; // -retains the receiver until it is done
    [seq release];
}


@end

#endif
