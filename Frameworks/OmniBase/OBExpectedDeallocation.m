// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
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

#ifdef DEBUG

#define DEBUG_EXPECTED_DEALLOCATIONS 0
#if DEBUG_EXPECTED_DEALLOCATIONS
    #define LOG(format, ...) NSLog(@"DEALLOC: " format, ## __VA_ARGS__)
#else
    #define LOG(format, ...) do {} while(0)
#endif

@interface _OBExpectedDeallocation : NSObject
- initWithObject:(__unsafe_unretained id)object;
@end

@implementation _OBExpectedDeallocation
{
    __unsafe_unretained id _object;
    Class _originalClass;
    CFAbsoluteTime _originalTime;
    NSArray *_backtraceFrames;
    BOOL _hasWarned;
}

static dispatch_queue_t WarningQueue;
static CFMutableArrayRef PendingDeallocations = NULL;
static NSTimer *WarningTimer = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    WarningQueue = dispatch_queue_create("com.omnigroup.OmniBase.ExpectedDeallocation", DISPATCH_QUEUE_SERIAL);
    PendingDeallocations = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL); // non-retaining
}

- initWithObject:(__unsafe_unretained id)object;
{
    if (!(self = [super init]))
        return nil;
    
    _object = object;
    _originalClass = [object class];
    
    {
        // Could move this whole thing to OmniFoundation to use the utilities in OFBacktrace.m, but it doesn't have the exact code I want here.
        NSMutableArray *frameStrings = [[NSMutableArray alloc] init];
        void *frames[512];
        int frameCount = backtrace(frames, sizeof(frames)/sizeof(*frames));
        char **symbols = backtrace_symbols(frames, (unsigned int)frameCount);

        for (int frameIndex = 0; frameIndex < frameCount; frameIndex++) {
            NSString *frame = [[NSString alloc] initWithFormat:@"\t%p -- %s\n", frames[frameIndex], symbols[frameIndex]];
            [frameStrings addObject:frame];
        }

        if (symbols)
            free(symbols); // The individual strings don't need to be free'd.
        
        _backtraceFrames = [frameStrings copy];
    }
    
    LOG(@"Expecting <%@:%p>", NSStringFromClass(_originalClass), object);
    
    dispatch_async(WarningQueue, ^{
        if (!WarningTimer) {
            // Create the timer here so that further enqueue blocks won't, but we flip to the main queue to schedule.
            WarningTimer = [NSTimer timerWithTimeInterval:2 target:[self class] selector:@selector(_warnAboutPendingDeallocations:) userInfo:nil repeats:NO];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSRunLoop currentRunLoop] addTimer:WarningTimer forMode:NSRunLoopCommonModes];
            });
        }

        // Don't start the clock until we actually make it onto the serial queue, in case it gets backed up with lots of objects.
        _originalTime = CFAbsoluteTimeGetCurrent();

        CFArrayAppendValue(PendingDeallocations, (__bridge void *)self);
    });

    return self;
}

- (void)dealloc;
{
    void *unsafeSelf = (__bridge void *)self; // Avoid retain by block.
    
    // Capture the info we will need later in the block
    void *object = (__bridge void *)_object;
    Class originalClass = _originalClass;
    CFAbsoluteTime deallocTime = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime originalTime = _originalTime;
    
#ifdef OMNI_ASSERTIONS_ON
    BOOL hasWarned = _hasWarned;
#endif
    
    dispatch_async(WarningQueue, ^{
        CFIndex warningCount = CFArrayGetCount(PendingDeallocations);
        CFIndex warningIndex = CFArrayGetFirstIndexOfValue(PendingDeallocations, CFRangeMake(0, warningCount), unsafeSelf);
        
        LOG(@"Actual <%@:%p>", NSStringFromClass(originalClass), object);

        // Might have logged and purged the warning already
        if (warningIndex == kCFNotFound) {
            OBASSERT_NOT_REACHED("Dealloc is the only place that instances are removed...");
        } else {
            // Order isn't important, so move the last object to this slot. If there is only one entry, this still works.
            const void *lastValue = CFArrayGetValueAtIndex(PendingDeallocations, warningCount - 1);
            CFArraySetValueAtIndex(PendingDeallocations, warningIndex, lastValue);
            CFArrayRemoveValueAtIndex(PendingDeallocations, warningCount - 1);
            warningCount--;
            
            if (hasWarned) {
                NSUInteger warnedCount = 0;
                for (warningIndex = 0; warningIndex < warningCount; warningIndex++) {
                    __unsafe_unretained _OBExpectedDeallocation *other = (__unsafe_unretained _OBExpectedDeallocation *)CFArrayGetValueAtIndex(PendingDeallocations, warningIndex);
                    if (other->_hasWarned)
                        warnedCount++;
                }
                
                NSLog(@"Eventually did deallocate <%@:%p> after %.2fs (%lu left)", NSStringFromClass(originalClass), object, deallocTime - originalTime, warnedCount);
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
        
        CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
        CFIndex warningIndex = 0, warningCount = CFArrayGetCount(PendingDeallocations);
        while (warningIndex < warningCount) {
            __unsafe_unretained _OBExpectedDeallocation *warning = (__bridge _OBExpectedDeallocation *)CFArrayGetValueAtIndex(PendingDeallocations, warningIndex);
            
            CFTimeInterval elapsedTime = currentTime - warning->_originalTime;
            if (!warning->_hasWarned && elapsedTime > kExpectedWarningTimeout) {
                OBInvokeAssertionFailureHandler("DEALLOC", "", __FILE__, __LINE__, @"*** Expected deallocation of <%@:%p> %.2fs ago from:\n\t%@", NSStringFromClass(warning->_originalClass), warning->_object, elapsedTime, [warning->_backtraceFrames componentsJoinedByString:@"\t"]);

#ifdef DEBUG_bungi
                _searchAllRegionsForPointer((__bridge const void *)warning->_object);
#else
                (void)(_searchAllRegionsForPointer);
#endif
                // We leave the object in the array so that we can have a running count of the number of expected deallocations that haven't happened.
                warning->_hasWarned = YES;
            } else {
                warningIndex++;
            }
        }
        
        CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
        if (endTime - currentTime > 1) {
            NSLog(@"Took %f seconds to process deallocation warnings.", endTime - currentTime);
        }
        
        if (warningCount > 0) {
            WarningTimer = [NSTimer timerWithTimeInterval:2 target:[self class] selector:@selector(_warnAboutPendingDeallocations:) userInfo:nil repeats:NO];

            // We are already on the main queue
            [[NSRunLoop currentRunLoop] addTimer:WarningTimer forMode:NSRunLoopCommonModes];
        }
    });
}

@end

static unsigned DeallocationWarningKey;

void OBExpectDeallocation(id object)
{
    if (!object)
        return;
    
    if (objc_getAssociatedObject(object, &DeallocationWarningKey))
        return;
    
    _OBExpectedDeallocation *warning = [[_OBExpectedDeallocation alloc] initWithObject:object];
    objc_setAssociatedObject(object, &DeallocationWarningKey, warning, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#endif
