// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSDebug.h>
#endif

#import <libkern/OSAtomic.h>

RCS_ID("$Id$")

#if OFOBJECT_USE_INTERNAL_EXTRA_REF_COUNT
@interface OFObject (Private)
- (void)_resetInternalReferenceCount;
@end
#endif

@implementation OFObject
/*" If enabled, OFObject provides an inline retain count for much more efficient reference counting. "*/

#if OFOBJECT_USE_INTERNAL_EXTRA_REF_COUNT
- (NSUInteger)retainCount;
{
    return _extraRefCount + 1;
}
#endif

#ifdef DEBUG
#define SaneRetainCount 1000000
#define FreedObjectRetainCount SaneRetainCount + 234567;
#endif

// We aren't using our _extraRefCount as a flag to indicate that other changes are complete, so the _extraRefCount needs to be atomically updated, but not ordered with other memory operations.  So, use the non-barrier versions.

#if OFOBJECT_USE_INTERNAL_EXTRA_REF_COUNT
- (id)retain;
{
#ifdef DEBUG
    int32_t newExtraRefCount = 
#endif
    OSAtomicIncrement32(&_extraRefCount);
    
#ifdef DEBUG
    if (newExtraRefCount > SaneRetainCount) {
        OBASSERT(newExtraRefCount <= SaneRetainCount);
        [NSException raise:@"RetainInsane" format:@"-[%@ %s]: Insane retain count! count=%d", OBShortObjectDescription(self), _cmd, newExtraRefCount];
    }
#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    if (NSKeepAllocationStatistics) {
        // Repord our allocation statistics to make OOM and oh happy
#if defined(MAC_OS_X_VERSION_10_5) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
#else
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self, NULL, NULL, NULL);
#endif
    }
#endif
    
    return self;
}

- (oneway void)release;
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    if (NSKeepAllocationStatistics) {
        // Report our allocation statistics to make OOM and oh happy
#if defined(MAC_OS_X_VERSION_10_5) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
#else
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self, NULL, NULL, NULL);
#endif
    }
#endif
    
    int32_t newExtraRefCount = OSAtomicDecrement32(&_extraRefCount);
    if (newExtraRefCount < 0) {
#ifdef DEBUG
        _extraRefCount = FreedObjectRetainCount;
#endif
        [self dealloc];
    } else {
#ifdef DEBUG
        if (newExtraRefCount > SaneRetainCount) {
            [NSException raise:@"RetainInsane" format:@"-[%@ %s]: Insane retain count! count=%d", OBShortObjectDescription(self), _cmd, _extraRefCount];
        }
#endif
    }
}
#endif // OFOBJECT_USE_INTERNAL_EXTRA_REF_COUNT

@end

#if OFOBJECT_USE_INTERNAL_EXTRA_REF_COUNT
@implementation OFObject (Private)

- (void)_resetInternalReferenceCount;
{
    _extraRefCount = 0;
}

@end
#endif

#if OFOBJECT_USE_INTERNAL_EXTRA_REF_COUNT
// NSCopyObject does a byte-by-byte copy, which would clone the reference count of the copied object into the result.
id <NSObject> OFCopyObject(OFObject *object, unsigned extraBytes, NSZone *zone)
{
    id <NSObject> result = NSCopyObject(object, extraBytes, zone);
    if (result) {
        OBASSERT([result isKindOfClass:[OFObject class]]);
        [(OFObject *)result _resetInternalReferenceCount];
    }
    return result;
}
#endif


