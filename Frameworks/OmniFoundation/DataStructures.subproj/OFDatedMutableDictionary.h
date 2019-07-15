// Copyright 1998-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSArray, NSDate;

@interface OFDatedMutableDictionary : OFObject
{
    NSMutableDictionary *_dictionary;
}

- (void)setObject:(id)anObject forKey:(NSString *)aKey;
- (id)objectForKey:(NSString *)aKey;
- (void)removeObjectForKey:(NSString *)aKey;
- (NSDate *)lastAccessForKey:(NSString *)aKey;

- (NSArray *)objectsOlderThanDate:(NSDate *)aDate;
- (void)removeObjectsOlderThanDate:(NSDate *)aDate;

@end
