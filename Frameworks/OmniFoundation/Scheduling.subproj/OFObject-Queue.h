// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/Scheduling.subproj/OFObject-Queue.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSObject.h>

@protocol OFObjectQueue

+ (void)queueSelectorOnce:(SEL)aSelector;
- (void)queueSelector:(SEL)aSelector;
- (void)queueSelectorOnce:(SEL)aSelector;
- (void)queueSelector:(SEL)aSelector withObject:(id)anObject;
- (void)queueSelectorOnce:(SEL)aSelector withObject:(id)anObject;
- (void)queueSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2;
- (void)queueSelectorOnce:(SEL)aSelector withObject:(id)object1 withObject:(id)object2;
- (void)queueSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2 withObject:(id)object3;
- (void)queueSelector:(SEL)aSelector withBool:(BOOL)aBool;
- (void)queueSelector:(SEL)aSelector withInt:(int)anInt;
- (void)queueSelector:(SEL)aSelector withInt:(int)anInt withInt:(int)anotherInt;

+ (void)mainThreadPerformSelectorOnce:(SEL)aSelector;
- (void)mainThreadPerformSelector:(SEL)aSelector;
- (void)mainThreadPerformSelectorOnce:(SEL)aSelector;
- (void)mainThreadPerformSelector:(SEL)aSelector withObject:(id)anObject;
- (void)mainThreadPerformSelectorOnce:(SEL)aSelector withObject:(id)anObject;
- (void)mainThreadPerformSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2;
- (void)mainThreadPerformSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2 withObject:(id)object3;
- (void)mainThreadPerformSelector:(SEL)aSelector withBool:(BOOL)aBool;
- (void)mainThreadPerformSelector:(SEL)aSelector withInt:(int)anInt;
- (void)mainThreadPerformSelector:(SEL)aSelector withInt:(int)anInt withInt:(int)anInt2;

- (void)invokeSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2 withObject:(id)object3;

@end

@interface NSObject (Queue) <OFObjectQueue>
@end
