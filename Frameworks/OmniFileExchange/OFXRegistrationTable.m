// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
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

static OFDeclareDebugLogLevel(OFXRegistrationTableDebug);
#define DEBUG_TABLE(level, format, ...) do { \
    if (OFXRegistrationTableDebug >= (level)) \
        NSLog(@"TABLE %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)

@implementation OFXRegistrationTable
{
    NSString *_name;
    dispatch_queue_t _queue;
    NSMutableDictionary <NSString *, NSObject *> *_internalTable; // The current version which is protected by serialization through _queue
    BOOL _publicUpdateQueued; // YES if there is a pending update already queued and we should avoid queuing another.
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
    OBPRECONDITION(key);

    __block NSObject * value;
    dispatch_barrier_sync(_queue, ^{
        value = _internalTable[key];
    });
    return value;
}

static void _unlockedRemove(OFXRegistrationTable *self, NSString *key)
{
    DEBUG_TABLE(1, @"remove %@", key);
    [self->_internalTable removeObjectForKey:key];
}
static void _unlockedRegister(OFXRegistrationTable *self, NSString *key, id object)
{
    DEBUG_TABLE(1, @"register %@ -> %@", key, [object shortDescription]);
    self->_internalTable[key] = object;
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key;
{
    OBPRECONDITION(key);
    OBPRECONDITION(obj);
    
    key = [key copy]; // Unlikely that the key is mutable, but just in case...
    dispatch_async(_queue, ^{
        _unlockedRegister(self, key, obj);
        [self _queueUpdate];
    });
}

- (void)removeObjectForKey:(NSString *)key;
{
    OBPRECONDITION(key);

    key = [key copy]; // Unlikely that the key is mutable, but just in case...
    dispatch_async(_queue, ^{
        _unlockedRemove(self, key);
        [self _queueUpdate];
    });
}

- (void)removeObjectsWithKeys:(NSArray <NSString *> *)removeKeys setObjectsWithDictionary:(NSDictionary *)setObjects;
{
    // Make sure the sets are immutable and that the block will live
    removeKeys = [removeKeys copy];
    setObjects = [setObjects copy];
    
    dispatch_async(_queue, ^{
        for (NSString *key in removeKeys) {
            _unlockedRemove(self, key);
        }
        [setObjects enumerateKeysAndObjectsUsingBlock:^(NSString *key, id object, BOOL *stop) {
            _unlockedRegister(self, key, object);
        }];
        [self _queueUpdate];
    });
}

- (void)afterUpdate:(void (^)(void))action;
{
    // Run the block through our background queue and back through the main queue to make sure it happens after any currently queued updates.
    action = [action copy];
    dispatch_async(_queue, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            action();
        });
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
#ifdef DEBUG
    dispatch_assert_queue(_queue);
#endif
    
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
#ifdef DEBUG
    dispatch_assert_queue(dispatch_get_main_queue());
#endif
    
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
