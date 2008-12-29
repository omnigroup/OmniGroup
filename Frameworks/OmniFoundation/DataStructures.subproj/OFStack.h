// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFStack.h 98221 2008-03-04 21:06:19Z kc $

#import <Foundation/NSZone.h>
#import <objc/objc.h>

typedef struct {
    NSZone                     *stackZone;
    void                       *stackRoot;
    unsigned long               basePointer;
    unsigned long               stackPointer;
    unsigned long               stackSize;
    unsigned long               currentFrameSize;
    unsigned long               frameCount;
} OFStack;


#define OMNI_TYPE_OP(cType, strType)								\
        extern void OFStackPush ## strType (OFStack *stack, cType aVal);         \
        extern void OFStackPop ## strType (OFStack *stack, cType *aVal);         \
        extern void OFStackPeek ## strType (OFStack *stack,			\
                                                             unsigned long basePointer,		\
                                                             int offset, cType *aVal);		\
        extern void OFStackPoke ## strType (OFStack *stack,			\
                                                             unsigned long basePointer,		\
                                                             int offset, cType aVal);

OMNI_TYPE_OP(unsigned long, UnsignedLong)
OMNI_TYPE_OP(id,            Id)
OMNI_TYPE_OP(SEL,           SEL)
OMNI_TYPE_OP(void *,        Pointer)

#undef OMNI_TYPE_OP

extern void OFStackDebug(BOOL enableStackDebugging);

extern OFStack *OFStackAllocate(NSZone *zone);
extern void OFStackDeallocate(OFStack *stack);

extern void OFStackPushBytes(OFStack *stack,
                                            const void *bytes,
                                            unsigned long size);
extern void OFStackPopBytes(OFStack *stack,
                                           void *bytes,
                                           unsigned long size);

extern void OFStackPushFrame(OFStack *stack);
extern void OFStackPopFrame(OFStack *stack);

/* Advanced features */
extern unsigned long OFStackPreviousFrame(OFStack *stack, unsigned long framePointer);
extern void          OFStackDiscardBytes(OFStack *stack, unsigned long size);
extern void          OFStackPrint(OFStack *stack);

