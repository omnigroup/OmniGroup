// Copyright 2012-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAnimationContext-OAExtensions.h>

RCS_ID("$Id$")

#if 0 && defined(DEBUG_bungi)
    #define DEBUG_SEQ(format, ...) NSLog(@"SEQ: " format, ## __VA_ARGS__)
#else
    #define DEBUG_SEQ(format, ...)
#endif

@interface _OAAnimationSequence : NSObject
{
    NSArray *_steps;
    NSUInteger _stepIndex;
    NSTimeInterval _startTime;
}

- initWithSteps:(NSArray *)steps;
- (void)run;
@end

@implementation _OAAnimationSequence

- initWithSteps:(NSArray *)steps;
{
    if (!(self = [super init]))
        return nil;
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
        //[[UIApplication sharedApplication] endIgnoringInteractionEvents];
        OBAnalyzerProofRelease(self);
        return;
    }
    
    _stepIndex--;
    DEBUG_SEQ(@"running step %ld at %f", _stepIndex, CFAbsoluteTimeGetCurrent() - _startTime);
    OAAnimationGroup group = [_steps objectAtIndex:_stepIndex];
    
    [NSAnimationContext runAnimationGroup:group completionHandler:^{
        [self _runNextStep];
    }];
}

- (void)run;
{
    DEBUG_SEQ(@"steps = %@", _steps);

    // TODO: Support for synchronous animations like OUIAnimationSequence? NSAnimationContext.allowsImplicitAnimation doesn't seem quite like the correct thing to base this on, but maybe.
#if 0
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
#endif
    
    // Turn off interaction and fire up the animations.
//    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    OBAnalyzerProofRetain(self); // so the caller can -release us w/o clang-sa complaining.
    
    _startTime = CFAbsoluteTimeGetCurrent();
    [self _runNextStep];
}

@end

@implementation NSAnimationContext (OAExtensions)

+ (void)runAnimationGroups:(OAAnimationGroup)group, ...;
{
    OBPRECONDITION(group);
    
    // Collect all the blocks into a reversed array.
    group = [group copy]; // promote stack blocks to heap.
    NSMutableArray *steps = [NSMutableArray arrayWithObjects:group, nil];
    [group release];
    
    {
        va_list args;
        va_start(args, group);
        id object;
        while ((object = va_arg(args, id))) {
            object = [object copy]; // promote stack blocks to heap.
            [steps insertObject:object atIndex:0];
            [object release];
        }
        va_end(args);
    }
    
    _OAAnimationSequence *seq = [[_OAAnimationSequence alloc] initWithSteps:steps];
    [seq run]; // -retains the receiver until it is done
    [seq release];
}

@end

void OAWithoutAnimation(void (NS_NOESCAPE ^action)(void))
{
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.allowsImplicitAnimation = NO;
        context.duration = 0;

        action();
    }];
}
