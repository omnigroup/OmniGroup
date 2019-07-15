// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTransientObjectsTracker.h>

#if OF_TRANSIENT_OBJECTS_TRACKER_ENABLED

#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/OFBacktrace.h>

RCS_ID("$Id$")

/*
 This can be useful once you've identified some classes of objects in Instruments' "Allocations" instrument and want to work on reducing the number of transient allocations w/o switching back and forth between your debug build and running in instruments.
 */

@implementation OFTransientObjectsTracker
{
    Class _trackedClass;
    dispatch_queue_t _queue;
    CFMutableDictionaryRef _originalImpBySelector;
    
    void (*_original_dealloc)(id object, SEL _cmd);

    // Only around while tracking. Guarded by _queue.
    CFMutableDictionaryRef _liveInstanceToAllocationBacktrace;
    NSMutableDictionary *_transientInstanceAllocationBacktracesByClass;
}

// Removing instances of this are probably possible, but it seems messy and not really needed. So, they get set up once and then reused.
dispatch_queue_t TrackerByClassQueue = NULL;
NSMutableDictionary *TrackerByClass = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    TrackerByClassQueue = dispatch_queue_create("com.omnigroup.OmniAppKit.OFTransientObjectsTracker.TrackerByClassQueue", DISPATCH_QUEUE_SERIAL);
    TrackerByClass = [[NSMutableDictionary alloc] init];
}

// Could pass a block that the caller could use to do -addInitializerWithSelector: and -originalImplementationForSelector:, but that's probably more work that it's worth.
+ (OFTransientObjectsTracker *)transientObjectsTrackerForClass:(Class)cls addInitializers:(void (^)(OFTransientObjectsTracker *tracker))addInitializers;
{
    OBPRECONDITION([NSThread isMainThread], "Could add a class-wide serial queue to manage this dictionary, if needed");
    
    __block OFTransientObjectsTracker *tracker;
    dispatch_sync(TrackerByClassQueue, ^{
        tracker = TrackerByClass[cls];
        if (!tracker) {
            tracker = [[OFTransientObjectsTracker alloc] initWithTrackedClass:cls addInitializers:addInitializers];
            TrackerByClass[(id)cls] = tracker;
        }
    });
    
    return tracker;
}

- initWithTrackedClass:(Class)trackedClass addInitializers:(void (^)(OFTransientObjectsTracker *tracker))addInitializers;
{
    if (!(self = [super init]))
        return nil;
    
    _trackedClass = trackedClass;
    _queue = dispatch_queue_create([[NSString stringWithFormat:@"com.omnigroup.OmniAppKit.OFTransientObjectsTracker.%@", NSStringFromClass(trackedClass)] UTF8String], DISPATCH_QUEUE_SERIAL);

    _originalImpBySelector = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
    
    // Do this work in the queue so that newly installed methods don't execute before we're finished.
    dispatch_sync(_queue, ^{

        // No SEL parameter is passed to the block
        IMP replacment_dealloc = imp_implementationWithBlock(^(id object){
            const void *ptr = object;
            Class objectClass = object_getClass(object);
            
            dispatch_async(_queue, ^{
                if (_liveInstanceToAllocationBacktrace == NULL)
                    return;
                
                // If this pointer was allocated during this tracking session, then it is transient.
                NSString *backtrace = CFDictionaryGetValue(_liveInstanceToAllocationBacktrace, ptr);
                if (backtrace) {
                    NSMutableArray *backtraces = _transientInstanceAllocationBacktracesByClass[objectClass];
                    if (!backtraces) {
                        backtraces = [[NSMutableArray alloc] init];
                        _transientInstanceAllocationBacktracesByClass[(id)objectClass] = backtraces;
                        [backtraces release];
                    }
                    [backtraces addObject:backtrace];
                    CFDictionaryRemoveValue(_liveInstanceToAllocationBacktrace, ptr);
                }
            });
            
            _original_dealloc(object, @selector(dealloc));
        });
        
        _original_dealloc = (typeof(_original_dealloc))OBReplaceMethodImplementation(_trackedClass, @selector(dealloc), replacment_dealloc);

        // Add initializers
        addInitializers(self);
    });

    return self;
}

- (void)dealloc;
{
    // Cleaning up instances of this are more trouble than its worth since this is debugging code.
    OBRejectUnusedImplementation(self, _cmd);
    [super dealloc];
}

- (void)addInitializerWithSelector:(SEL)sel action:(id)block;
{
    // We expect to be called on our queue.
    IMP replacementImp = imp_implementationWithBlock(block);
    IMP originalImp = OBReplaceMethodImplementation(_trackedClass, sel, replacementImp);
    
    CFDictionaryAddValue(_originalImpBySelector, sel, originalImp);
}

- (void)registerInstance:(id)instance;
{
    if (!instance)
        return;
    
    const void *ptr = instance;
    NSString *backtrace = OFCopyNumericBacktraceString(2);
    dispatch_async(_queue, ^{
        if (_liveInstanceToAllocationBacktrace == NULL)
            return;
        
        OBASSERT(CFDictionaryGetValue(_liveInstanceToAllocationBacktrace, ptr) == NULL);
        CFDictionarySetValue(_liveInstanceToAllocationBacktrace, ptr, backtrace);
        [backtrace release];
    });
}

- (IMP)originalImplementationForSelector:(SEL)sel;
{
    IMP imp = CFDictionaryGetValue(_originalImpBySelector, sel);
    OBASSERT(imp != NULL, "Calling -originalImplementationForSelector: for a selector (%s) that wasn't registered as an initializer.", sel_getName(sel));
    return imp;
}

- (void)trackAllocationsIn:(void (^)(void))block;
{
    [self beginTracking];
    @try {
        @autoreleasepool {
            block();
        }
    }
    @finally {
        [self endTracking];
    }
}

- (void)beginTracking;
{
    dispatch_sync(_queue, ^{
        OBASSERT(_liveInstanceToAllocationBacktrace == NULL, "Unbalanced calls to -beginTracking and -endTracking?");
        _liveInstanceToAllocationBacktrace = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, &OFNSObjectDictionaryValueCallbacks);
        _transientInstanceAllocationBacktracesByClass = [[NSMutableDictionary alloc] init];
    });
}

- (void)endTracking;
{
    dispatch_sync(_queue, ^{
        OBASSERT(_liveInstanceToAllocationBacktrace != NULL, "Unbalanced calls to -beginTracking and -endTracking?");
        
        CFRelease(_liveInstanceToAllocationBacktrace);
        _liveInstanceToAllocationBacktrace = NULL;
        
        if ([_transientInstanceAllocationBacktracesByClass count] > 0) {
            fprintf(stderr, "Transient instance count by class:\n");
            NSArray *classes = [[_transientInstanceAllocationBacktracesByClass allKeys] sortedArrayUsingComparator:^NSComparisonResult(Class cls1, Class cls2) {
                NSUInteger count1 = [_transientInstanceAllocationBacktracesByClass[cls1] count];
                NSUInteger count2 = [_transientInstanceAllocationBacktracesByClass[cls2] count];
                
                if (count1 < count2)
                    return NSOrderedAscending;
                if (count1 > count2)
                    return NSOrderedDescending;
                return strcmp(class_getName(cls1), class_getName(cls2));
            }];
            
            for (Class cls in classes) {
                fprintf(stderr, "    %6.lu -- %s\n", [_transientInstanceAllocationBacktracesByClass[cls] count], class_getName(cls));
            }
            
            for (Class cls in classes) {
                fprintf(stderr, "############# %s #############\n\n", class_getName(cls));
                for (NSString *numericBacktrace in _transientInstanceAllocationBacktracesByClass[cls]) {
                    NSString *symbolicBacktrace = OFCopySymbolicBacktraceForNumericBacktrace(numericBacktrace);
                    NSData *data = [symbolicBacktrace dataUsingEncoding:NSUTF8StringEncoding];
                    fwrite([data bytes], [data length], 1, stderr);
                    fputs("\n\n", stderr);
                    [symbolicBacktrace release];
                }
            }
        }
        [_transientInstanceAllocationBacktracesByClass release];
        _transientInstanceAllocationBacktracesByClass = nil;
    });
}

#if 0

static void _addAllocatedObject(const void *ptr)
{
    NSString *backtrace = OFCopyNumericBacktraceString(2);
    dispatch_async(ViewTrackingQueue, ^{
        if (_liveInstanceToAllocationBacktrace == NULL)
            return;
        
        OBASSERT(CFDictionaryGetValue(_liveInstanceToAllocationBacktrace, ptr) == NULL);
        CFDictionarySetValue(_liveInstanceToAllocationBacktrace, ptr, backtrace);
        [backtrace release];
    });
}

static id replacement_NSView_initWithFrame(NSView *self, SEL _cmd, CGRect frame)
{
    self = original_NSView_initWithFrame(self, _cmd, frame);
    _addAllocatedObject(self);
    return self;
}

static id replacement_NSView_initWithCoder(NSView *self, SEL _cmd, NSCoder *coder)
{
    self = original_NSView_initWithCoder(self, _cmd, coder);
    _addAllocatedObject(self);
    return self;
}

+ (void)beginTransientViewTracking;
{
    if (!ViewTrackingQueue) {
        ViewTrackingQueue = dispatch_queue_create("com.omnigroup.OmniAppKit.ViewTracking", DISPATCH_QUEUE_SERIAL);
    }
    
    dispatch_sync(ViewTrackingQueue, ^{
        // Install these in the queue too so that the new implementations don't run before we finish setting up!
        if (original_NSView_dealloc == NULL) {
            Class cls = [NSView class];
            original_NSView_dealloc = (typeof(original_NSView_dealloc))OBReplaceMethodImplementation(cls, @selector(dealloc), (IMP)replacement_NSView_dealloc);
            original_NSView_initWithFrame = (typeof(original_NSView_initWithFrame))OBReplaceMethodImplementation(cls, @selector(initWithFrame:), (IMP)replacement_NSView_initWithFrame);
            original_NSView_initWithCoder = (typeof(original_NSView_initWithCoder))OBReplaceMethodImplementation(cls, @selector(initWithCoder:), (IMP)replacement_NSView_initWithCoder);
        }
        
        OBASSERT(_liveInstanceToAllocationBacktrace == NULL, "Unbalanced calls to +beginTransientViewTracking and +endTransientViewTracking?");
        _liveInstanceToAllocationBacktrace = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, &OFNSObjectDictionaryValueCallbacks);
        _transientInstanceAllocationBacktracesByClass = [[NSMutableDictionary alloc] init];
    });
}

+ (void)endTransientViewTracking;
{
    dispatch_sync(ViewTrackingQueue, ^{
        OBASSERT(_liveInstanceToAllocationBacktrace != NULL, "Unbalanced calls to +beginTransientViewTracking and +endTransientViewTracking?");
        
        CFRelease(_liveInstanceToAllocationBacktrace);
        _liveInstanceToAllocationBacktrace = NULL;
        
        if ([_transientInstanceAllocationBacktracesByClass count] > 0) {
            fprintf(stderr, "Transient instance count by class:\n");
            NSArray *classes = [[_transientInstanceAllocationBacktracesByClass allKeys] sortedArrayUsingComparator:^NSComparisonResult(Class cls1, Class cls2) {
                NSUInteger count1 = [_transientInstanceAllocationBacktracesByClass[cls1] count];
                NSUInteger count2 = [_transientInstanceAllocationBacktracesByClass[cls2] count];
                
                if (count1 < count2)
                    return NSOrderedAscending;
                if (count1 > count2)
                    return NSOrderedDescending;
                return strcmp(class_getName(cls1), class_getName(cls2));
            }];
            
            for (Class cls in classes) {
                fprintf(stderr, "    %6.lu -- %s\n", [_transientInstanceAllocationBacktracesByClass[cls] count], class_getName(cls));
            }
            
            for (Class cls in classes) {
                fprintf(stderr, "############# %s #############\n\n", class_getName(cls));
                for (NSString *numericBacktrace in _transientInstanceAllocationBacktracesByClass[cls]) {
                    NSString *symbolicBacktrace = OFCopySymbolicBacktraceForNumericBacktrace(numericBacktrace);
                    NSData *data = [symbolicBacktrace dataUsingEncoding:NSUTF8StringEncoding];
                    fwrite([data bytes], [data length], 1, stderr);
                    fputs("\n\n", stderr);
                    [symbolicBacktrace release];
                }
            }
        }
        [_transientInstanceAllocationBacktracesByClass release];
        _transientInstanceAllocationBacktracesByClass = nil;
    });
}
#endif

@end

#endif
