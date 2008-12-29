// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OFWeakRetainConcreteImplementation.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSObject.h>

#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <OmniBase/assertions.h>

#import <OmniFoundation/OFWeakRetainProtocol.h>
#import <OmniFoundation/OFSimpleLock.h>

//#define DEBUG_WEAK_RETAIN

#ifdef DEBUG_WEAK_RETAIN
#import <OmniBase/OBObject.h> // For OBShortObjectDescription
#endif

//
// Private -- Don't depend or use anything here -- use the public macros below
//

@interface NSObject (OFWeakRetainSupport)
- (void)_releaseFromWeakRetainHelper;
@end

#define OF_WEAK_RETAIN_INVALID_COUNT 0x7fffffff

typedef struct _OFWeakRetainIvars {
    OFSimpleLockType lock;
#ifdef OMNI_ASSERTIONS_ON
    unsigned int     count:31;
    unsigned int     inited:1;
#else
    unsigned int     count;
#endif
} OFWeakRetainIvars;

static inline void _OFWeakRetainIvarsInit(OFWeakRetainIvars *ivars, NSObject <OFWeakRetain> *self)
{
    OFSimpleLockInit(&ivars->lock);
    // since we are in the ivars of an ObjC object, count is already zero
    OBASSERT(ivars->count == 0);
#ifdef OMNI_ASSERTIONS_ON
    ivars->inited = 1;
#endif

#ifdef DEBUG_WEAK_RETAIN
    NSLog(@"_OFWeakRetainIvarsInit(%@)", OBShortObjectDescription(self));
#endif
}

static inline void _OFWeakRetainIncrement(OFWeakRetainIvars *ivars, NSObject <OFWeakRetain> *self)
{
    OBPRECONDITION(ivars->inited);

    OFSimpleLock(&ivars->lock);
    if (ivars->count != OF_WEAK_RETAIN_INVALID_COUNT)
        ivars->count++;
#ifdef DEBUG_WEAK_RETAIN
    NSLog(@"-[%@ incrementWeakRetainCount]: count=%d", OBShortObjectDescription(self), ivars->count);
#endif
    OFSimpleUnlock(&ivars->lock);
}

static inline void _OFWeakRetainDecrement(OFWeakRetainIvars *ivars, NSObject <OFWeakRetain> *self)
{
    OBPRECONDITION(ivars->inited);

    OFSimpleLock(&ivars->lock);
    if (ivars->count != OF_WEAK_RETAIN_INVALID_COUNT)
        ivars->count--;
#ifdef DEBUG_WEAK_RETAIN
    NSLog(@"-[%@ decrementWeakRetainCount]: count=%d", OBShortObjectDescription(self), ivars->count);
#endif
    OFSimpleUnlock(&ivars->lock);
}

static inline NSObject <OFWeakRetain> *_OFStrongRetainIncrement(OFWeakRetainIvars *ivars, NSObject <OFWeakRetain> *self)
{
    NSObject <OFWeakRetain> *result;
    OBPRECONDITION(ivars->inited);

    OFSimpleLock(&ivars->lock);
    if (ivars->count != OF_WEAK_RETAIN_INVALID_COUNT)
        result = [self retain];
    else
        result = nil;
    OFSimpleUnlock(&ivars->lock);
    return result;
}

extern void _OFWeakRetainRelease(OFWeakRetainIvars *ivars, NSObject <OFWeakRetain> *self);

//
// Public macros
//


// This goes in the ivar section of the class definition that is adopting the OFWeakRetain protocol
#define OFWeakRetainConcreteImplementation_IVARS \
    OFWeakRetainIvars weakRetainIvars

// This goes in the init method of the class that is adopting the OFWeakRetain protocol
#define OFWeakRetainConcreteImplementation_INIT _OFWeakRetainIvarsInit(&weakRetainIvars, self)

// This goes in the class implementation
#define OFWeakRetainConcreteImplementation_IMPLEMENTATION	\
- (void)incrementWeakRetainCount;				\
{								\
    _OFWeakRetainIncrement(&weakRetainIvars, self);		\
}								\
- (void)decrementWeakRetainCount;				\
{								\
    _OFWeakRetainDecrement(&weakRetainIvars, self);		\
}								\
- (void)_releaseFromWeakRetainHelper;				\
{								\
    [super release];						\
}								\
- (id)strongRetain;						\
{								\
    return _OFStrongRetainIncrement(&weakRetainIvars, self);	\
}								\
- (void)release;						\
{								\
    _OFWeakRetainRelease(&weakRetainIvars, self);		\
}

#define OFWeakRetainConcreteImplementation_NULL_IMPLEMENTATION	\
- (void)incrementWeakRetainCount;				\
{								\
}								\
- (void)decrementWeakRetainCount;				\
{								\
}								\
- (id)strongRetain;						\
{								\
    return [self retain];					\
}								\
- (void)invalidateWeakRetains;					\
{								\
}

// Backwards compatibility macros
#define OFWeakRetainConcreteImplementation_INTERFACE
#define OFWeakRetainConcreteImplementation_DEALLOC

// Note: These convenience methods should only be sent to objects which conform to the OFWeakRetains protocol
@interface NSObject (OFWeakRetain)
- (id)weakRetain;
- (void)weakRelease;
- (id)weakAutorelease;
@end
