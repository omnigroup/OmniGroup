// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTrace.h"

RCS_ID("$Id$")

static dispatch_queue_t Queue;
static NSCountedSet *Signals;
static NSMutableDictionary *Accumulators;

BOOL OFXTraceEnabled = NO;

static void _OFXTraceInitialize(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Queue = dispatch_queue_create("com.omnigroup.OmniFileStore.OFXTrace", DISPATCH_QUEUE_SERIAL);
        Signals = [[NSCountedSet alloc] init];
        Accumulators = [[NSMutableDictionary alloc] init];
    });
}

void OFXTraceReset(void)
{
    _OFXTraceInitialize();

    // TODO: Could add a 'generation' number to help track down signal/wait calls that are from the wrong generation.
    dispatch_barrier_sync(Queue, ^{
        //NSLog(@"TRACE RESET");
        [Signals removeAllObjects];
        [Accumulators removeAllObjects];
    });
}

void OFXTraceSignal(NSString *name)
{
    OBPRECONDITION([name rangeOfString:@"\""].location == NSNotFound, "Should not add quotes when passing the name in via a macro");
    
    _OFXTraceInitialize();
    
    dispatch_async(Queue, ^{
        //NSLog(@"TRACE SIGNAL \"%@\"", name);
        [Signals addObject:name];
    });
}

NSUInteger OFXTraceSignalCount(NSString *name)
{
    OBPRECONDITION([name rangeOfString:@"\""].location == NSNotFound, "Should not add quotes when passing the name in via a macro");

    __block NSUInteger count = NO;
    dispatch_barrier_sync(Queue, ^{
        count = [Signals countForObject:name];
        //NSLog(@"TRACE COUNT \"%@\" is %ld", name, count);
    });
    return count;
}

BOOL OFXTraceHasSignal(NSString *name)
{
    OBPRECONDITION([name rangeOfString:@"\""].location == NSNotFound, "Should not add quotes when passing the name in via a macro");

    return OFXTraceSignalCount(name) > 0;
}

void OFXTraceAppend(NSString *name, id object)
{
    OBPRECONDITION([name rangeOfString:@"\""].location == NSNotFound, "Should not add quotes when passing the name in via a macro");
    
    _OFXTraceInitialize();
    
    dispatch_async(Queue, ^{
        //NSLog(@"TRACE APPEND \"%@\" -- %@", name, object);
        NSMutableArray *accumulator = Accumulators[name];
        if (!accumulator) {
            accumulator = [[NSMutableArray alloc] init];
            Accumulators[name] = accumulator;
        }
        [accumulator addObject:object];
    });
}

NSArray *OFXTraceCopy(NSString *name)
{
    OBPRECONDITION([name rangeOfString:@"\""].location == NSNotFound, "Should not add quotes when passing the name in via a macro");

    __block NSArray *result = nil;
    dispatch_barrier_sync(Queue, ^{
        result = [Accumulators[name] copy];
        //NSLog(@"TRACE COPY \"%@\" is %@", name, result);
    });
    return result;
}

static BOOL _OFXTraceWait(NSString *name)
{
    OBPRECONDITION([name rangeOfString:@"\""].location == NSNotFound, "Should not add quotes when passing the name in via a macro");

    __block BOOL found = NO;
    dispatch_barrier_sync(Queue, ^{
        if ([Signals countForObject:name] > 0) {
            //NSLog(@"TRACE WAIT \"%@\"", name);
            [Signals removeObject:name];
            found = YES;
        }
    });
    return found;
}

void OFXTraceWait(NSString *name)
{
    OBPRECONDITION([name rangeOfString:@"\""].location == NSNotFound, "Should not add quotes when passing the name in via a macro");

    _OFXTraceInitialize();
    
    while (!_OFXTraceWait(name)) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }
}


