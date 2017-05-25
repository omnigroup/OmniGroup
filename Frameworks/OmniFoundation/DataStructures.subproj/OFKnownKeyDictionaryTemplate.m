// Copyright 1998-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFKnownKeyDictionaryTemplate.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

static NSLock              *Lock = nil;
static NSMutableDictionary *UniqueTable = nil;

@implementation OFKnownKeyDictionaryTemplate

+ (void) initialize;
{
    OBINITIALIZE;

    Lock = [[NSLock alloc] init];
    UniqueTable = [[NSMutableDictionary alloc] init];
}

+ (OFKnownKeyDictionaryTemplate *)templateWithKeys:(NSArray *)oldKeys;
{
    
    NSMutableArray *keys = [NSMutableArray arrayWithArray:oldKeys];
    [keys sortUsingComparator:^NSComparisonResult(id obj1, id obj2){ 
        if (obj1 < obj2)
            return NSOrderedAscending;
        else if (obj1 == obj2)
            return NSOrderedSame;
        else
            return NSOrderedDescending;
    }];

    __block OFKnownKeyDictionaryTemplate *template = nil;
    OFWithLock(Lock, ^{
        if (!(template = [UniqueTable objectForKey: keys])) {
            template = (OFKnownKeyDictionaryTemplate *)NSAllocateObject(self, sizeof(NSObject *) * [keys count], NULL);
            template = [template _initWithKeys:keys];
            [UniqueTable setObject:template forKey:keys];
            [template release];
        }
    });
    
    return template;
}

- (void)dealloc;
{
    OBRejectUnusedImplementation(self, _cmd);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
    [super dealloc]; // We know this won't be reached, but w/o this we get a warning about a missing call to super -dealloc
#pragma clang diagnostic pop
}

- (NSArray *)keys;
{
    return _keyArray;
}

#pragma mark - Private

- _initWithKeys:(NSArray *)keys;
{
    _keyArray = [keys retain];
    _keyCount = [keys count];
    
    for (NSUInteger keyIndex = 0; keyIndex < _keyCount; keyIndex++)
        _keys[keyIndex] = [keys objectAtIndex: keyIndex];
    
    return self;
}

@end
