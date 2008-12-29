// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OFForwardObject.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFRetainableObject.h>

@class NSInvocation;

//
// OFForwardObject simply turns calls to forward:: into calls to forwardInvocation:  It implements forwardInvocation: to raise an exception, so subclasses must implement a version of their own. 
//
// Note: This doesn't implement methodSignatureForSelector:which is necessary. this could probably be added later, but all the current subclasses of this have their own special implementations anyway. 
//

@class NSInvocation;

#import <objc/objc-class.h> /* For marg_list */

@interface OFForwardObject : OFRetainableObject
{
}

- forward:(SEL)sel :(marg_list)args;
- (void)forwardInvocation:(NSInvocation *)invocation;

@end
