// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSObject-NSDraggingInfo-OAExtensions.h"

#import <OmniBase/OmniBase.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSObject-NSDraggingInfo-OAExtensions.m 68913 2005-10-03 19:36:19Z kc $")

@implementation NSObject (NSDraggingInfo_OAExtensions)

- (NSDragOperation)availableDragOperationFromDragOperations:(NSDragOperation)firstDragOperation, ...;
{
    OBASSERT([self conformsToProtocol:@protocol(NSDraggingInfo)]);
    
    va_list argList;
    va_start(argList, firstDragOperation);
    
    NSDragOperation draggingSourceOperationMask = [(id <NSDraggingInfo>)self draggingSourceOperationMask];
    NSDragOperation nextDragOperation = firstDragOperation;
    while (nextDragOperation != NSDragOperationNone) {
        if (nextDragOperation & draggingSourceOperationMask)
            break;
        nextDragOperation = va_arg(argList, NSDragOperation);
    }
    va_end(argList);
    
    return nextDragOperation;
}

@end
