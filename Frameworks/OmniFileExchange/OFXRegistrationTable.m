// Copyright 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXRegistrationTable.h>

#import <Foundation/NSString.h>
#import <OmniBase/macros.h>
#import <OmniFoundation/OFPreference.h>
#import <dispatch/dispatch.h>

RCS_ID("$Id$")

static NSInteger OFXRegistrationTableDebug = INT_MAX; // Make sure to log if we hit a log call before this is loaded from preferences/environment

#define DEBUG_TABLE(level, format, ...) do { \
    if (OFXRegistrationTableDebug >= (level)) \
        NSLog(@"TABLE %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)

@implementation OFXRegistrationTable
{
    NSString *_name;
    dispatch_queue_t _queue;
    NSMutableDictionary *_internalTable; // The current version which is protected by serialization through _queue
    BOOL _publicUpdateQueued; // YES if there is a pending update already queued and we should avoid queuing another.
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFInitializeDebugLogLevel(OFXRegistrationTableDebug);
}

- init;
{
    // Must supply a name for debugging
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithName:(NSString *)name;
{
    if (!(self = [super init]))
        return nil;
    
    _name = [name copy];
    _queue = dispatch_queue_create([[NSString stringWithFormat:@"com.omnigroup.OmniFileStore.RegistrationTable %@", name] UTF8String], DISPATCH_QUEUE_SERIAL);
    _internalTable = [[NSMutableDictionary alloc] init];

    _values = [[NSSet alloc] init];
    
    return self;
}

// Regarding -dealloc. GCD is inluded in ARC. There should be no operations on the queue -- writers don't have a reference to us since we are being deallocated. There should be no pending update queued since we reference 'self' in those blocks and thus we can't be deallocated while one is pending.

- (id)objectForKeyedSubscript:(NSString *)key;
{
    __block id value;
    dispatch_barrier_sync(_queue, ^{
        value = _internalTable[key];
    });
    return value;
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key;
{
    key = [key copy]; // Unlikely that the key is mutable, but just in case...
    dispatch_async(_queue, ^{
        DEBUG_TABLE(1, @"register %@ -> %@", key, [obj shortDescription]);
        _internalTable[key] = obj;
        [self _queueUpdate];
    });
}

- (void)removeObjectForKey:(NSString *)key;
{
    key = [key copy]; // Unlikely that the key is mutable, but just in case...
    dispatch_async(_queue, ^{
        DEBUG_TABLE(1, @"remove %@", key);
        [_internalTable removeObjectForKey:key];
        [self _queueUpdate];
    });
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, _name];
}

#pragma mark - Private

- (void)_queueUpdate;
{
    // dispatch_get_current_queue() is deprecated sadly.
    //OBPRECONDITION(dispatch_get_current_queue() == _queue);
    
    if (_publicUpdateQueued)
        return;
    
    DEBUG_TABLE(1, @"queuing update");
    _publicUpdateQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _performUpdate];
    });
}

- (void)_performUpdate;
{
    // dispatch_get_current_queue() is deprecated sadly.
    //OBPRECONDITION(dispatch_get_current_queue() == dispatch_get_main_queue());
    
    __block NSDictionary *table;
    
    // Snapshot the current table state and then unblock any other writers (which will set the flag again and queue up another update).
    dispatch_barrier_sync(_queue, ^{
        _publicUpdateQueued = NO;
        table = [_internalTable copy];
    });
    
    // Then, while the writers aren't blocked, propagate this information to listeners via KVO.
    DEBUG_TABLE(1, @"publishing update");
    [self willChangeValueForKey:@"values"];
    {
        _values = [[NSSet alloc] initWithArray:[table allValues]];
        
        OBASSERT([_values count] == [table count]); // Values should be unique
    }
    [self didChangeValueForKey:@"values"];
    
}

@end
