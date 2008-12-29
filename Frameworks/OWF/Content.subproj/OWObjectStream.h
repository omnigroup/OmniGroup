// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OWF/OWAbstractObjectStream.h>

@class NSConditionLock, NSLock, NSMutableArray, NSRecursiveLock;

#define OWObjectStreamBuffer_BufferedObjectsLength 128

typedef struct _OWObjectStreamBuffer {
    unsigned int nextIndex;
    id objects[OWObjectStreamBuffer_BufferedObjectsLength];
    struct _OWObjectStreamBuffer *next;
} OWObjectStreamBuffer;


@interface OWObjectStream : OWAbstractObjectStream
{
    id *nextObjectInBuffer, *beyondBuffer;
    OWObjectStreamBuffer *first, *last;
    unsigned int count;
    BOOL endOfObjects;
    
    NSConditionLock *objectsLock;
    NSConditionLock *endOfDataLock;
}

@end
