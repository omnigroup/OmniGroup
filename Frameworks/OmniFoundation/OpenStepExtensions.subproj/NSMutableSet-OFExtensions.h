// Copyright 2002-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSMutableSet-OFExtensions.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSSet.h>

@interface NSMutableSet (OFExtensions)

- (void) removeObjectsFromArray: (NSArray *) objects;
/*"
Removes all objects from the receiver which are in the specified array.
"*/

- (void) exclusiveDisjoinSet: (NSSet *) otherSet;
/*"
Modifies the receiver to contain only those objects in the receiver or the argument but not the objects originally in both sets. The odd name is for parallelism with Apple's -intersectSet:, -unionSet:, etc.
"*/

@end
