// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTrace.h"

RCS_ID("$Id$")

static dispatch_queue_t Queue;
static NSCountedSet *Signals;

BOOL OFXTraceEnabled = NO;

static void _OFXTraceInitialize(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Queue = dispatch_queue_create("com.omnigroup.OmniFileStore.OFXTrace", DISPATCH_QUEUE_SERIAL);
        Signals = [[NSCountedSet alloc] init];
    });
}

void OFXTraceReset(void)
{
    _OFXTraceInitialize();

    // TODO: Could add a 'generation' number to help track down signal/wait calls that are from the wrong generation.
    dispatch_barrier_sync(Queue, ^{
        //NSLog(@"TRACE RESET");
        [Signals removeAllObjects];
    });
}

void OFXTraceSignal(NSString *name)
{
    _OFXTraceInitialize();
    
    dispatch_async(Queue, ^{
        //NSLog(@"TRACE SIGNAL \"%@\"", name);
        [Signals addObject:name];
    });
}

void OFXTraceWait(NSString *name)
{
    _OFXTraceInitialize();
    
    __block BOOL found = NO;
    
    // TODO: Could add a timeout and an idle block instead of always running the runloop
    while (!found) {
        dispatch_barrier_sync(Queue, ^{
            if ([Signals countForObject:name] > 0) {
                //NSLog(@"TRACE WAIT \"%@\"", name);
                [Signals removeObject:name];
                found = YES;
            }
        });
        
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }
}


