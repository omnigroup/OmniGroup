// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFMutableBijection.h>

#import "OFBijection-Internal.h"

#import <Foundation/NSMapTable.h>

RCS_ID("$Id$");

@implementation OFMutableBijection

- (void)setObject:(id)anObject forKey:(id)aKey;
{
    id previousObject = [self objectForKey:aKey];
    
    if (anObject == nil) {
        [self.keysToObjects removeObjectForKey:aKey];
        [self.objectsToKeys removeObjectForKey:previousObject];
    } else {
        [self.keysToObjects setObject:anObject forKey:aKey];
        
        [self.objectsToKeys removeObjectForKey:previousObject];
        [self.objectsToKeys setObject:aKey forKey:anObject];
    }
    
    OBINVARIANT_EXPENSIVE([self checkInvariants]); // Potentially called in a very tight loop
}

- (void)setKey:(id)aKey forObject:(id)anObject;
{
    id previousKey = [self keyForObject:anObject];
    
    if (aKey == nil) {
        [self.objectsToKeys removeObjectForKey:anObject];
        [self.keysToObjects removeObjectForKey:previousKey];
    } else {
        [self.objectsToKeys setObject:aKey forKey:anObject];
        
        [self.keysToObjects removeObjectForKey:previousKey];
        [self.keysToObjects setObject:anObject forKey:aKey];
    }
    
    OBINVARIANT_EXPENSIVE([self checkInvariants]); // Potentially called in a very tight loop
}

- (void)setObject:(id)anObject forKeyedSubscript:(id)aKey;
{
    // Documentation: "This method is identical to setObject:forKey:."
    [self setObject:anObject forKey:aKey];
}

- (void)invert;
{
    NSMapTable *tmp = [self.keysToObjects retain];
    self.keysToObjects = self.objectsToKeys;
    self.objectsToKeys = tmp;
    [tmp release];
}

@end
