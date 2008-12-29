// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFStack.h>

#define OMNI_STACK_START_SIZE NSPageSize()
#define OMNI_STACK_DEBUG

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFStack.m 104581 2008-09-06 21:18:23Z kc $")

static BOOL _stackDebug = NO;

void OFStackDebug(BOOL enableStackDebugging)
{
    if (_stackDebug != enableStackDebugging)
        fprintf(stderr, "OFStack: Debugging %s.\n", enableStackDebugging ? "enabled" : "disabled");
    _stackDebug = enableStackDebugging;
}

OFStack *OFStackAllocate(NSZone *zone)
{
    OFStack *stack;

    stack = (OFStack *)NSZoneCalloc(zone, 1, sizeof(OFStack));
    stack->stackZone = zone;
    return stack;
}

void OFStackDeallocate(OFStack *stack)
{
    if (!stack)
	return;
    if (stack->stackRoot)
	NSZoneFree(stack->stackZone, stack->stackRoot);
    NSZoneFree(stack->stackZone, stack);
}

static inline void _OFStackEnsurePushSpace(OFStack *stack, unsigned long aSize)
{
    while (stack->stackSize - stack->stackPointer < aSize) {
	if (!stack->stackSize) {
	    stack->stackSize = OMNI_STACK_START_SIZE;
	    stack->stackRoot = NSZoneMalloc(stack->stackZone, stack->stackSize);

	} else {
	    stack->stackSize += stack->stackSize;
	    stack->stackRoot = NSZoneRealloc(stack->stackZone, stack->stackRoot, stack->stackSize);
	}

	if (!stack->stackRoot) {
            fprintf(stderr, "OFStack:Couldn't grow stack! (requested size was %ld bytes)\n",
		    stack->stackSize);
	    abort();
	}

#ifdef OMNI_STACK_DEBUG
        if (_stackDebug) {
            fprintf(stderr, "OFStack:Growing stack to size of %ld\n", stack->stackSize);
            fprintf(stderr, "OFStack:Stack now located at %p\n", stack->stackRoot);
	    fprintf(stderr, "\tformat -> [    sp    |    bp    |   frame  ] type size value\n");
	}
#endif

    }
}

static inline void _OFStackEnsurePopSpace(OFStack *stack, unsigned long aSize)
{
    if (aSize > stack->currentFrameSize) {
        fprintf(stderr, "OFStack: UnderFlow! (wanted %ld bytes, but had only %ld)\n",
		aSize, stack->currentFrameSize);
	abort();
    }
}

/* Note that this assumes that unaligned access to longs, and such is ok */

#ifdef OMNI_STACK_DEBUG
#define OMNI_DEBUG_OP(cType, size, op, value, format)					\
    do {										\
        if (_stackDebug)								\
	    fprintf(stderr, "\t%s   -> [0x%08lx|0x%08lx|0x%08lx] %s %d " format "\n",	\
		    op, stack->stackPointer, stack->basePointer,			\
		    stack->currentFrameSize,						\
		    #cType, (int)size, value);						\
    } while (NO)



#else
#define OMNI_DEBUG_OP(cType, size, op, value, format)
#endif

#define OMNI_TYPE_OP(cType, strType, format)							\
    void OFStackPush ## strType (OFStack *stack, cType aVal)				        \
    {												\
        _OFStackEnsurePushSpace(stack, sizeof(aVal));						\
	*(cType *)((char *)stack->stackRoot + stack->stackPointer) = aVal;			\
	stack->stackPointer += sizeof(aVal);							\
	stack->currentFrameSize += sizeof(aVal);						\
	OMNI_DEBUG_OP(cType, sizeof(aVal), "push", aVal, format);				\
    }												\
									    			\
    void OFStackPeek ## strType (OFStack *stack, unsigned long basePointer,			\
                                   int offset, cType *aVal)					\
    {												\
        OBASSERT(basePointer >= abs(offset));							\
        OBASSERT(stack->stackPointer >= basePointer + offset + sizeof(*aVal));	\
        *aVal = *(cType *)((char *)stack->stackRoot + basePointer + offset);			\
        OMNI_DEBUG_OP(cType, sizeof(aVal), "peek", *aVal, format);				\
    }												\
                                                                                                \
    void OFStackPoke ## strType (OFStack *stack, unsigned long basePointer,			\
                                   int offset, cType aVal)					\
    {												\
        OBASSERT(basePointer >= abs(offset));							\
        OBASSERT(stack->stackPointer >= basePointer + offset + sizeof(aVal));	\
        *(cType *)((char *)stack->stackRoot + basePointer + offset) = aVal;			\
        OMNI_DEBUG_OP(cType, sizeof(aVal), "poke", aVal, format);				\
    }												\
												\
    static void _OFStackPop ## strType (OFStack *stack, cType *aVal)			        \
    {												\
	stack->currentFrameSize -= sizeof(*aVal);						\
	stack->stackPointer -= sizeof(*aVal);							\
	*aVal = *(cType *)((char *)stack->stackRoot + stack->stackPointer);			\
	OMNI_DEBUG_OP(cType, sizeof(aVal), "pop ", *aVal, format);				\
    }												\
									    			\
    void OFStackPop ## strType (OFStack *stack, cType *aVal)				        \
    {												\
        _OFStackEnsurePopSpace(stack, sizeof(*aVal));						\
        _OFStackPop ## strType (stack, aVal);							\
    }

OMNI_TYPE_OP(unsigned long, UnsignedLong, "0x%08lx")
OMNI_TYPE_OP(id,            Id,           "%p")
OMNI_TYPE_OP(SEL,           SEL,          "%p")
OMNI_TYPE_OP(void *,        Pointer,      "%p")

#undef OMNI_TYPE_OP

void OFStackPushBytes(OFStack *stack, const void *bytes, unsigned long size)
{
    _OFStackEnsurePushSpace(stack, size);
    stack->currentFrameSize += size;
    memmove((char *)stack->stackRoot + stack->stackPointer, bytes, size);
    stack->stackPointer += size;
}

void OFStackPopBytes(OFStack *stack, void *bytes, unsigned long size)
{
    _OFStackEnsurePopSpace(stack, size);
    stack->currentFrameSize -= size;
    memmove(bytes, (char *)stack->stackRoot + stack->stackPointer, size);
    stack->stackPointer -= size;
}

void OFStackPushFrame(OFStack *stack)
{
    OFStackPushUnsignedLong(stack, stack->basePointer);
    stack->basePointer = stack->stackPointer;
    stack->currentFrameSize = 0;
    stack->frameCount++;
}

void OFStackPopFrame(OFStack *stack)
{
    if (!stack->basePointer) {
        fprintf(stderr, "OFStack: Attempt to pop a non-existant frame!\n");
	abort();
    }

    stack->stackPointer -= stack->currentFrameSize;
    stack->currentFrameSize = sizeof(unsigned long);

    stack->stackPointer = stack->basePointer;
    _OFStackPopUnsignedLong(stack, &stack->basePointer);
    stack->currentFrameSize = stack->stackPointer - stack->basePointer;

    stack->frameCount--;
}

unsigned long OFStackPreviousFrame(OFStack *stack, unsigned long basePointer)
{
    unsigned long previousFrame;

    OFStackPeekUnsignedLong(stack, basePointer, -4, &previousFrame);
    return previousFrame;
}

void OFStackDiscardBytes(OFStack *stack, unsigned long size)
{
    _OFStackEnsurePopSpace(stack, size);
    stack->currentFrameSize -= size;
    stack->stackPointer -= size;
}

void OFStackPrint(OFStack *stack)
{
    unsigned long nextFrame = stack->basePointer;
    unsigned long stackIndex;

    fprintf(stderr, "fp = 0x%08lx\n", stack->basePointer);
    fprintf(stderr, "sp = 0x%08lx\n", stack->stackPointer);

    nextFrame = stack->basePointer - sizeof(unsigned long);
    stackIndex = stack->stackPointer;

    while (stackIndex) {
	unsigned long value;

	OBASSERT(stackIndex <= stack->stackPointer);

	stackIndex -= sizeof(unsigned long);
	value = *(unsigned long *)((char *)stack->stackRoot + stackIndex);

	if (stackIndex == nextFrame) {
	    fprintf(stderr, "frame->[0x%08lx] : 0x%08lx\n", stackIndex, value);
	    nextFrame = value - sizeof(unsigned long);
	} else
	    fprintf(stderr, "       [0x%08lx] : 0x%08lx\n", stackIndex, value);
    }
}
