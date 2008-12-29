// Copyright 1999-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <objc/objc-class.h>
#import <OmniBase/assertions.h>

// The ObjC 2 runtime doesn't have a bulk-add call, so this is pointless there
#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5

//
// This is useful for building up a list of methods and adding them all at once.
// The ObjC runtime loops through ALL of the classes in the runtime and flushes
// their method caches when you do a class_addMethods.  To minimize the effect
// of this, we can build up one big method list and add it all at once.  Also,
// this approach probably makes method lookup faster in the uncached case.
//

typedef struct _OFPendingMethodList {
    struct objc_method_list *list;
    unsigned int             size;
    Class                    targetClass;
} OFPendingMethodList;

#define OF_EMPTY_PENDING_METHOD_LIST {NULL,0,Nil}

static inline unsigned OFMethodListSize(unsigned int methodCount)
{
    // Actually, we could probably use methodCount-1 since the objc_method_list
    // struct already declares space for a method, but we were doing this before
    // and it will make me feel all warm and safe.
    return sizeof(struct objc_method_list) + sizeof(struct objc_method) * methodCount;
}


static inline void OFQueueMethod(OFPendingMethodList *list, Class aClass, SEL sel, IMP imp, const char *types)
{
    struct objc_method *method;

    OBPRECONDITION(list);
    OBPRECONDITION(aClass && sel && imp && types);
    OBPRECONDITION(!list->targetClass || (list->targetClass == aClass));

    if (!list->list) {
        list->targetClass = aClass;
        list->size = 32; // a reasonable default size
        list->list = (struct objc_method_list *) NSZoneMalloc(NSDefaultMallocZone(),
                                                              OFMethodListSize(list->size));
        list->list->method_count = 0;
    } else if ((unsigned)list->list->method_count == list->size) {
        list->size *= 2;
        list->list = (struct objc_method_list *) NSZoneRealloc(NSDefaultMallocZone(),
                                                               list->list,
                                                               OFMethodListSize(list->size));
    }

    method = &list->list->method_list[list->list->method_count];
    method->method_name  = sel;
    method->method_types = (char *)types;
    method->method_imp   = imp;

    list->list->method_count++;
}

static inline void OFAddPendingMethods(OFPendingMethodList *list, Class aClass)
{
    if (!list->list) {
        OBASSERT(!list->targetClass);
        OBASSERT(!list->size);

        // No methods were queued
        return;
    }

    OBASSERT(list->list);
    OBASSERT(list->targetClass);
    OBASSERT(list->targetClass == aClass);

    class_addMethods(list->targetClass, list->list);

    list->targetClass = nil;
    list->list      = NULL;
    list->size  = 0;
}

#endif
