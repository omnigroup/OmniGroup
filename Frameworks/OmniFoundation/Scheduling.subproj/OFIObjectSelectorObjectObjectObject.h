// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/Scheduling.subproj/OFIObjectSelectorObjectObjectObject.h 98770 2008-03-17 22:25:33Z kc $

#import <OmniFoundation/OFIObjectSelector.h>

@interface OFIObjectSelectorObjectObjectObject : OFIObjectSelector
{
    id object1;
    id object2;
    id object3;
}

- initForObject:(id)targetObject selector:(SEL)aSelector withObject:(id)anObject1 withObject:(id)anObject2 withObject:(id)anObject3;

@end
