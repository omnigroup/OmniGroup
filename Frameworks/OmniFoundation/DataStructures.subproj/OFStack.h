// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSZone.h>
#import <objc/objc.h>

typedef struct {
    NSZone *stackZone;
    void *stackRoot;
    size_t basePointer;
    size_t stackPointer;
    size_t stackSize;
    size_t currentFrameSize;
    size_t frameCount;
} OFStack;


#define OMNI_TYPE_OP(cType, strType) \
        extern void OFStackPush ## strType (OFStack *stack, cType aVal); \
        extern void OFStackPop ## strType (OFStack *stack, cType *aVal); \
        extern void OFStackPeek ## strType (OFStack *stack, size_t basePointer, ptrdiff_t offset, cType *aVal); \
        extern void OFStackPoke ## strType (OFStack *stack, size_t basePointer,	ptrdiff_t offset, cType aVal);

OMNI_TYPE_OP(uintptr_t, Unsigned)
OMNI_TYPE_OP(id, Id)
OMNI_TYPE_OP(SEL, SEL)
OMNI_TYPE_OP(void *, Pointer)

#undef OMNI_TYPE_OP

extern void OFStackDebug(BOOL enableStackDebugging);

extern OFStack *OFStackAllocate(NSZone *zone);
extern void OFStackDeallocate(OFStack *stack);

extern void OFStackPushBytes(OFStack *stack, const void *bytes, size_t size);
extern void OFStackPopBytes(OFStack *stack, void *bytes, size_t size);

extern void OFStackPushFrame(OFStack *stack);
extern void OFStackPopFrame(OFStack *stack);

/* Advanced features */
extern unsigned long OFStackPreviousFrame(OFStack *stack, size_t framePointer);
extern void          OFStackDiscardBytes(OFStack *stack, size_t size);
extern void          OFStackPrint(OFStack *stack);

