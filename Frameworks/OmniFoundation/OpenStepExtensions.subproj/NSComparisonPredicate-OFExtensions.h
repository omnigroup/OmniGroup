// Copyright 2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4

#import <Foundation/NSComparisonPredicate.h>

@interface NSComparisonPredicate (OFExtensions)
+ (NSPredicate *)isKindOfClassPredicate:(Class)cls;
+ (NSPredicate *)conformsToProtocolPredicate:(Protocol *)protocol;
@end

#endif
