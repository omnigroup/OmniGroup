// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBExpectedDeallocation.h>

#import <Foundation/Foundation.h>
#import <OmniBase/assertions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
#import <execinfo.h>
#import <malloc/malloc.h>
#import <mach/mach.h>
#import <mach/vm_task.h>
#import <dlfcn.h>

RCS_ID("$Id$")

#define DEBUG_EXPECTED_DEALLOCATIONS 0
#if DEBUG_EXPECTED_DEALLOCATIONS
    #define LOG(format, ...) NSLog(@"DEALLOC: " format, ## __VA_ARGS__)
#else
    #define LOG(format, ...) do {} while(0)
#endif

#ifdef DEBUG
static BOOL Enabled = YES;
#else
static BOOL Enabled = NO;
#endif

void OBEnableExpectedDeallocations(void)
{
    Enabled = YES;
}

BOOL OBExpectedDeallocationsIsEnabled(void)
{
    return Enabled;
}

static __weak id <OBMissedDeallocationObserver> Observer = nil;

@interface OBMissedDeallocation ()

- initWithPointer:(const void *)pointer originalClass:(Class)originalClass timeInterval:(NSTimeInterval)timeInterval possibleFailureReason:(OBExpectedDeallocationPossibleFailureReason)possibleFailureReason;

@end

@implementation OBMissedDeallocation
{
    // Store the pointer as an integer and inverted. Xcode's memory graph support will find potential pointer to the interior (so 'masking' by adding one doesn't help).
    intptr_t _maskedPointerValue;
}

+ (void)setObserver:(id <OBMissedDeallocationObserver>)observer;
{
    OBPRECONDITION(Enabled);
    Observer = observer;
}

+ (id <OBMissedDeallocationObserver>)observer;
{
    return Observer;
}

- initWithPointer:(const void *)pointer originalClass:(Class)originalClass timeInterval:(NSTimeInterval)timeInterval possibleFailureReason:(OBExpectedDeallocationPossibleFailureReason)possibleFailureReason;
{
    _maskedPointerValue = ~(intptr_t)pointer;
    _originalClass = originalClass;
    _timeInterval = timeInterval;
    _possibleFailureReason = [possibleFailureReason copy];
    return self;
}

- (const void *)pointer;
{
    return (const void *)(~_maskedPointerValue);
}

- (nullable NSString *)failureReason;
{
    if (!_possibleFailureReason)
        return nil;
    return _possibleFailureReason((__bridge id)(const void *)(~_maskedPointerValue)); // Not safe since we are racing with a possible eventual deallocation.
}

- (NSUInteger)hash;
{
    return _maskedPointerValue ^ ((uintptr_t)_originalClass >> 4);
}

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[self class]]) {
        return NO;
    }
    OBMissedDeallocation *otherMissed = (OBMissedDeallocation *)otherObject;

    return _maskedPointerValue == otherMissed->_maskedPointerValue && _originalClass == otherMissed->_originalClass && _timeInterval == otherMissed->_timeInterval;
}

@end

// Storage that is strongly retained by the _OBExpectedDeallocationToken and our array of pending deallocations (and thus can only go away on our background queue).
@interface _OBExpectedDeallocationData : NSObject
{
@package
    __unsafe_unretained id _object;
    OBExpectedDeallocationPossibleFailureReason _possibleFailureReason;
    Class _originalClass;
    CFAbsoluteTime _originalTime;
    BOOL _hasWarned;
}

- initWithObject:(__unsafe_unretained id)object possibleFailureReason:(OBExpectedDeallocationPossibleFailureReason)possibleFailureReason;

@end

@implementation _OBExpectedDeallocationData

- initWithObject:(__unsafe_unretained id)object possibleFailureReason:(OBExpectedDeallocationPossibleFailureReason)possibleFailureReason;
{
    if (!(self = [super init]))
        return nil;

    _object = object;
    _possibleFailureReason = [possibleFailureReason copy];
    _originalClass = [object class];

    LOG(@"Expecting <%@:%p>", NSStringFromClass(_originalClass), object);

    return self;
}

@end


// Object that is used as a trigger to notice when the owning object is deallocated via ObjC associated objects.
@interface _OBExpectedDeallocationToken : NSObject
- initWithObject:(__unsafe_unretained id)object possibleFailureReason:(OBExpectedDeallocationPossibleFailureReason)possibleFailureReason;
@end

@implementation _OBExpectedDeallocationToken
{
    _OBExpectedDeallocationData *_data;
}

static dispatch_queue_t WarningQueue;
static NSMutableArray <_OBExpectedDeallocationData *> *PendingDeallocations = nil;
static NSTimer *WarningTimer = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    WarningQueue = dispatch_queue_create("com.omnigroup.OmniBase.ExpectedDeallocation", DISPATCH_QUEUE_SERIAL);
    PendingDeallocations = [[NSMutableArray alloc] init];
}

- initWithObject:(__unsafe_unretained id)object possibleFailureReason:(OBExpectedDeallocationPossibleFailureReason)possibleFailureReason;
{
    if (!(self = [super init]))
        return nil;

    _data = [[_OBExpectedDeallocationData alloc] initWithObject:object possibleFailureReason:possibleFailureReason];

    dispatch_async(WarningQueue, ^{
        if (!WarningTimer) {
            // Create the timer here so that further enqueue blocks won't, but we flip to the main queue to schedule.
            WarningTimer = [NSTimer timerWithTimeInterval:2 target:[self class] selector:@selector(_warnAboutPendingDeallocations:) userInfo:nil repeats:NO];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSRunLoop currentRunLoop] addTimer:WarningTimer forMode:NSRunLoopCommonModes];
            });
        }

        // Don't start the clock until we actually make it onto the serial queue, in case it gets backed up with lots of objects.
        _data->_originalTime = CFAbsoluteTimeGetCurrent();
        [PendingDeallocations addObject:_data];
    });

    return self;
}

- (void)dealloc;
{
    // Pass our _data off to the background queue to be removed and then return immediately.
    _OBExpectedDeallocationData *data = _data;
    CFAbsoluteTime deallocTime = CFAbsoluteTimeGetCurrent();

    dispatch_async(WarningQueue, ^{
        NSUInteger warningCount = [PendingDeallocations count];
        NSUInteger warningIndex = [PendingDeallocations indexOfObjectIdenticalTo:data];
        
        LOG(@"Actual <%@:%p>", NSStringFromClass(data->_originalClass), data->_object);

        // Might have logged and purged the warning already
        if (warningIndex == NSNotFound) {
            OBASSERT_NOT_REACHED("Dealloc is the only place that instances are removed...");
        } else {
            // Order isn't important, so move the last object to this slot. If there is only one entry, this still works.
            _OBExpectedDeallocationData *lastData = PendingDeallocations[warningCount - 1];
            PendingDeallocations[warningIndex] = lastData;
            [PendingDeallocations removeLastObject];
            warningCount--;
            
            if (data->_hasWarned) {
                NSUInteger warnedCount = 0;

                for (_OBExpectedDeallocationData *other in PendingDeallocations) {
                    if (other->_hasWarned)
                        warnedCount++;
                }
                
                NSLog(@"Eventually did deallocate <%@:%p> after %.2fs (%lu left)", NSStringFromClass(data->_originalClass), data->_object, deallocTime - data->_originalTime, warnedCount);

                id <OBMissedDeallocationObserver> observer = Observer;
                if (observer) {
                    NSMutableSet <OBMissedDeallocation *> *missedDeallocations = [[NSMutableSet alloc] init];

                    for (_OBExpectedDeallocationData *other in PendingDeallocations) {
                        if (other->_hasWarned) {
                            const void *ptr = (__bridge const void *)other->_object;

                            OBMissedDeallocation *missed = [[OBMissedDeallocation alloc] initWithPointer:ptr originalClass:other->_originalClass timeInterval:other->_originalTime possibleFailureReason:other->_possibleFailureReason];
                            [missedDeallocations addObject:missed];
                        }
                    }

                    dispatch_async(dispatch_get_main_queue(), ^{
                        [observer missedDeallocationsUpdated:missedDeallocations];
                    });
                }
            }
        }
    });
}

typedef BOOL (^MemoryRegionHandler)(vm_address_t allocatedAddress, vm_size_t allocatedLength, vm_region_basic_info_64_t region);

static kern_return_t _enumerateMemoryRegions(MemoryRegionHandler handler)
{
    vm_address_t addressCursor = 0;
    vm_map_t targetTask = mach_task_self();
    
    void *dl = dlopen(NULL, RTLD_GLOBAL);
    typeof(&vm_region) vm_region_p = (void *)dlsym(dl, "vm_region"); // Not exported to stuff we link against...
    if (!vm_region_p) {
        LOG(@"Cannot find `vm_region`");
        return KERN_FAILURE;
    }
    
    for(;;) {
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        vm_address_t allocatedAddress = addressCursor;
        vm_size_t allocatedLength;
        vm_region_info_data_t region_info;
        mach_port_name_t mobjPort = MACH_PORT_NULL;
        
        kern_return_t krt = vm_region_p(targetTask, &allocatedAddress, &allocatedLength, VM_REGION_BASIC_INFO_64, region_info, &infoCount, &mobjPort);
        
        if (krt != KERN_SUCCESS)
            return krt;
        
        // mobjPort is supposedly no longer used.
        if (MACH_PORT_VALID(mobjPort))
            mach_port_deallocate(mach_task_self(), mobjPort);
        
        BOOL cont = handler(allocatedAddress, allocatedLength, (vm_region_basic_info_64_t)region_info);
        if (!cont)
            break;
        
        addressCursor = allocatedAddress + allocatedLength;
    }
    
    return KERN_SUCCESS;
}

static void _searchRegionForPointer(const void *base, unsigned long length, const void *ptr, void (^found)(const void *pptr))
{
    // We assume base is aligned (page aligned since it is a vm region)
    const void *end = base + length;
    while (base < end) {
        if (ptr == *(const void **)base) {
            found(base);
        }
        base += sizeof(ptr);
    }
}

static kern_return_t _memory_reader(task_t remote_task, vm_address_t remote_address, vm_size_t size, void **local_memory)
{
#if 0
    // Turns out the lame approach works a bit better since the buffer lasts longer. <malloc/malloc.h> says the lifetime of the returned buffer is expected to be short, but isn't precise about it. Presumably it depends on the caller -- we could do the approach below with a pool of buffers.
    *local_memory = (void *)remote_address;
#else
    // We could just do "*local_memory = remote_address;", but it seems better to make a snapshot of the memory. We should try to avoid malloc activity while doing this enumeration, we could still have some due to ObjC message caches, background threads, etc... this is just debugging code.
    
    static const unsigned int bufferCount = 16;
    static unsigned int bufferIndex = 0;
    
    static vm_range_t buffers[bufferCount];

    vm_range_t *buffer = &buffers[bufferIndex];
    bufferIndex = (bufferIndex + 1) % bufferCount;

    kern_return_t krc;
    
    if (size > buffer->size) {
        if (buffer->address) {
            krc = vm_deallocate(mach_task_self(), buffer->address, buffer->size);
            if (krc != KERN_SUCCESS)
                return krc;
            buffer->address = 0;
            buffer->size = 0;
        }
        
        vm_address_t updatedBuffer;
        krc = vm_allocate(mach_task_self(), &updatedBuffer, size, 1);
        if (krc != KERN_SUCCESS)
            return krc;
    
        buffer->address = updatedBuffer;
        buffer->size = size;
    }
    
    memcpy((void *)buffer->address, (const void *)remote_address, size);
    
    *local_memory = (void *)buffer->address;
#endif
    
    return KERN_SUCCESS;
}

static void _recorder(task_t task, void *ctx, unsigned type, vm_range_t *ranges, unsigned rangeCount)
{
    NSIndexSet *pointerLocations = (__bridge NSIndexSet *)ctx;

    for (unsigned rangeIndex = 0; rangeIndex < rangeCount; rangeIndex++) {
        vm_range_t range = ranges[rangeIndex];
        
        if ([pointerLocations intersectsIndexesInRange:NSMakeRange(range.address, range.size)]) {
            NSLog(@"    FOUND!");
            NSLog(@"    range: %p, %ld   ctx:%p, type:%d", (const void *)range.address, (unsigned long)range.size, ctx, type);
        }
    }
}

static void _searchAllRegionsForPointer(const void *ptr)
{
    NSMutableIndexSet *pointerLocations = [[NSMutableIndexSet alloc] init];
    
    if (getenv("NSZombieEnabled")) {
        NSLog(@"*** Cannot search for references with NSZombieEnabled enabled ***");
        return;
    }
    if (getenv("MallocScribble") == NULL) {
        NSLog(@"*** Cannot search for references without MallocScribble enabled ***");
        return;
    }
    
    kern_return_t krt = _enumerateMemoryRegions(^BOOL(vm_address_t allocatedAddress, vm_size_t allocatedLength, vm_region_basic_info_64_t region){
        if ((region->protection & (VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE)) != (VM_PROT_READ|VM_PROT_WRITE)) {
            // Only heap and writable globals should be considered.
        } else {
            //NSLog(@"Region: %lx .. %lx", (unsigned long)allocatedAddress, (unsigned long)(allocatedAddress + allocatedLength - 1));
            _searchRegionForPointer((const void *)allocatedAddress, (unsigned long)allocatedLength, ptr, ^(const void *pptr){
                [pointerLocations addIndex:(NSUInteger)pptr];
            });
        }
        return YES;
    });
    
    if (krt != KERN_SUCCESS) {
        LOG(@"_enumerateMemoryRegions returned %d", krt);
    }
    
    // Lookups might be faster in an immutable version...
    NSIndexSet *immutablePointerLocations = [pointerLocations copy];
    NSLog(@"immutablePointerLocations = %@", immutablePointerLocations);
    
    vm_address_t *zones;
    unsigned zoneCount;
    krt = malloc_get_all_zones(mach_task_self(), _memory_reader, &zones, &zoneCount);
    if (krt != KERN_SUCCESS) {
        LOG(@"malloc_get_all_zones returned %d", krt);
    } else {
        for (unsigned zoneIndex = 0; zoneIndex < zoneCount; zoneIndex++) {
            malloc_zone_t *zone = (malloc_zone_t *)zones[zoneIndex];
            NSLog(@"zone at %p", zone);
            NSLog(@"  name %s", zone->zone_name);
            
            krt = zone->introspect->enumerator(mach_task_self(), (__bridge void *)immutablePointerLocations/*ctx*/, MALLOC_PTR_IN_USE_RANGE_TYPE, (vm_address_t)zone, _memory_reader, _recorder);
            if (krt != KERN_SUCCESS) {
                LOG(@"zone->introspect->enumerator returned %d", krt);
            }
        }
    }

    [immutablePointerLocations self]; // keep this alive until we are done enumerating zones
}

static float kExpectedWarningTimeout = 3.0;

+ (void)_warnAboutPendingDeallocations:(NSTimer *)timer;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(timer == WarningTimer);
    
    // Block enqueues while we decide whether to make a new timer
    dispatch_sync(WarningQueue, ^{
        LOG(@"Checking for missing deallocation...");
        
        WarningTimer = nil;

        id <OBMissedDeallocationObserver> observer = Observer;
        NSMutableSet <OBMissedDeallocation *> *missedDeallocations;
        if (observer) {
            missedDeallocations = [[NSMutableSet alloc] init];
        } else {
            missedDeallocations = nil;
        }

        CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();

        for (_OBExpectedDeallocationData *warning in PendingDeallocations) {
            CFTimeInterval elapsedTime = currentTime - warning->_originalTime;

            if (!warning->_hasWarned && elapsedTime > kExpectedWarningTimeout) {

                NSString *failureReason = nil;
                if (warning->_possibleFailureReason) {
                    // This is dangerous, but hopefully will usually be OK, and this is DEBUG only... we are on a background queue, and we don't have a strong reference to the object. So, it could get deallocated out from under us, or the block could do things that aren't thread-safe, etc. For example, when we notice that a view hasn't been deallocated, we check if it still has a superview. If so, the superview is the real problem.
                    failureReason = warning->_possibleFailureReason(warning->_object);
                }

                if (failureReason) {
                    NSLog(@"*** Expected deallocation of <%@:%p> %.2fs ago, possibly failed due to: %@", NSStringFromClass(warning->_originalClass), warning->_object, elapsedTime, failureReason);
                } else {
                    NSLog(@"*** Expected deallocation of <%@:%p> %.2fs ago", NSStringFromClass(warning->_originalClass), warning->_object, elapsedTime);
                }

#if 0 && defined(DEBUG_bungi)
                _searchAllRegionsForPointer((__bridge const void *)warning->_object);
#else
                (void)(_searchAllRegionsForPointer);
#endif
                // We leave the object in the array so that we can have a running count of the number of expected deallocations that haven't happened.
                warning->_hasWarned = YES;
            }

            if (warning->_hasWarned && missedDeallocations) {
                OBMissedDeallocation *missed = [[OBMissedDeallocation alloc] initWithPointer:(__bridge const void *)warning->_object originalClass:warning->_originalClass timeInterval:warning->_originalTime possibleFailureReason:warning->_possibleFailureReason];
                [missedDeallocations addObject:missed];
            }
        }

        if (observer) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [observer missedDeallocationsUpdated:missedDeallocations];
            });
        }

        CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
        if (endTime - currentTime > 1) {
            NSLog(@"Took %f seconds to process deallocation warnings.", endTime - currentTime);
        }
        
        if ([PendingDeallocations count] > 0) {
            WarningTimer = [NSTimer timerWithTimeInterval:2 target:[self class] selector:@selector(_warnAboutPendingDeallocations:) userInfo:nil repeats:NO];

            // We are already on the main queue
            [[NSRunLoop currentRunLoop] addTimer:WarningTimer forMode:NSRunLoopCommonModes];
        }
    });
}

@end

static unsigned DeallocationTokenKey;

void _OBExpectDeallocation(id object)
{
    OBPRECONDITION(Enabled);

    OBExpectDeallocationWithPossibleFailureReason(object, nil);
}

void _OBExpectDeallocationWithPossibleFailureReason(id object, OBExpectedDeallocationPossibleFailureReason possibleFailureReason)
{
    OBPRECONDITION(Enabled);

    if (!object)
        return;

    if (objc_getAssociatedObject(object, &DeallocationTokenKey))
        return;

    _OBExpectedDeallocationToken *token = [[_OBExpectedDeallocationToken alloc] initWithObject:object possibleFailureReason:possibleFailureReason];
    objc_setAssociatedObject(object, &DeallocationTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
