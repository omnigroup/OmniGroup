// Copyright 1998-2005, 2007, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFKnownKeyDictionaryTemplate.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

static NSLock              *lock = nil;
static NSMutableDictionary *uniqueTable = nil;

@interface OFKnownKeyDictionaryTemplate (PrivateAPI)
- _initWithKeys:(NSArray *)keys;
@end

@implementation OFKnownKeyDictionaryTemplate

+ (void)becomingMultiThreaded;
{
    lock = [[NSLock alloc] init];
}

+ (void) initialize;
{
    OBINITIALIZE;

    uniqueTable = [[NSMutableDictionary alloc] init];
}

+ (OFKnownKeyDictionaryTemplate *)templateWithKeys:(NSArray *)oldKeys;
{
    OFKnownKeyDictionaryTemplate *template;
    
    NSMutableArray *keys = [NSMutableArray arrayWithArray:oldKeys];
    [keys sortUsingComparator:^NSComparisonResult(id obj1, id obj2){ 
        if (obj1 < obj2)
            return NSOrderedAscending;
        else if (obj1 == obj2)
            return NSOrderedSame;
        else
            return NSOrderedDescending;
    }];

    [lock lock];
    @try {
        if (!(template = [uniqueTable objectForKey: keys])) {
            template = (OFKnownKeyDictionaryTemplate *)NSAllocateObject(self, sizeof(NSObject *) * [keys count], NULL);
            template = [template _initWithKeys: keys];
            [uniqueTable setObject: template forKey: keys];
            [template release];
        }
    } @finally {
        [lock unlock];
    }
    
    return template;
}

- (NSArray *)keys;
{
    return _keyArray;
}

- (id)retain
{
    return self;
}

- (id)autorelease;
{
    return self;
}

- (oneway void)release;
{
}

@end

@implementation OFKnownKeyDictionaryTemplate (PrivateAPI)

- _initWithKeys:(NSArray *)keys;
{
    NSUInteger keyIndex;
    
    _keyArray = [keys retain];
    _keyCount = [keys count];
    for (keyIndex = 0; keyIndex < _keyCount; keyIndex++)
        _keys[keyIndex] = [keys objectAtIndex: keyIndex];
    return self;
}

@end
