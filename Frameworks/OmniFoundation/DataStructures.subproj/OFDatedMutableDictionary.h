// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFDatedMutableDictionary.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class NSArray, NSDate;

@interface OFDatedMutableDictionary : OFObject
{
    NSMutableDictionary *_dictionary;
}

- (id)init;
- (void)dealloc;

- (void)setObject:(id)anObject forKey:(NSString *)aKey;
- (id)objectForKey:(NSString *)aKey;
- (void)removeObjectForKey:(NSString *)aKey;
- (NSDate *)lastAccessForKey:(NSString *)aKey;

- (NSArray *)objectsOlderThanDate:(NSDate *)aDate;
- (void)removeObjectsOlderThanDate:(NSDate *)aDate;

// Debugging

- (NSMutableDictionary *)debugDictionary;

@end
