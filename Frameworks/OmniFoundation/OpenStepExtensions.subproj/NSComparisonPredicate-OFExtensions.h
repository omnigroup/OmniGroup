// Copyright 2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSComparisonPredicate-OFExtensions.h 68950 2005-10-03 21:53:41Z kc $

#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4

#import <Foundation/NSComparisonPredicate.h>

@interface NSComparisonPredicate (OFExtensions)
+ (NSPredicate *)isKindOfClassPredicate:(Class)cls;
+ (NSPredicate *)conformsToProtocolPredicate:(Protocol *)protocol;
@end

#endif
