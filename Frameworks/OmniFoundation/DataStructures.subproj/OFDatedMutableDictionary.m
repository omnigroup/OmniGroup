// Copyright 1998-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDatedMutableDictionary.h>

#import <OmniFoundation/NSDate-OFExtensions.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFDatedMutableDictionary.m 93428 2007-10-25 16:36:11Z kc $")

@interface OFDatedMutableDictionaryEntry : OFObject
{
    id object;
    NSDate *lastAccess;
}

- initWithObject:(id)object;
- (id)object;
- (id)objectWithNoAccessUpdate;
- (NSDate *)lastAccess;

@end


@implementation OFDatedMutableDictionary

- (id)init;
{
    [super init];
    _dictionary = [[NSMutableDictionary alloc] init];
    return self;
}

- (void)dealloc;
{
    [_dictionary release];
    [super dealloc];
}

- (void)setObject:(id)anObject forKey:(NSString *)aKey;
{
    OFDatedMutableDictionaryEntry *entry;

    entry = [[OFDatedMutableDictionaryEntry alloc] initWithObject:anObject];
    [_dictionary setObject:entry forKey:aKey];
    [entry release];
}

- (id)objectForKey:(NSString *)aKey;
{
    return [[_dictionary objectForKey:aKey] object];
}

- (void)removeObjectForKey:(NSString *)aKey;
{
    [_dictionary removeObjectForKey:aKey];
}

- (NSDate *)lastAccessForKey:(NSString *)aKey;
{
    return [[_dictionary objectForKey:aKey] lastAccess];
}

- (NSArray *)objectsOlderThanDate:(NSDate *)cutoffDate;
{
    NSArray *allKeys;
    NSMutableArray *oldObjects;
    unsigned int i, count;

    allKeys = [_dictionary allKeys];
    oldObjects = [[NSMutableArray alloc] init];
    
    for (i = 0, count = [allKeys count]; i < count; i++) {
        NSString *aKey;
        OFDatedMutableDictionaryEntry *entry;

        aKey = [allKeys objectAtIndex:i];
        entry = [_dictionary objectForKey:aKey];

        if ([cutoffDate isAfterDate:[entry lastAccess]])
            [oldObjects addObject:[entry objectWithNoAccessUpdate]];
    }

    return [oldObjects autorelease];
}

- (void)removeObjectsOlderThanDate:(NSDate *)cutoffDate;
{
    NSArray *allKeys;
    unsigned int i, count;

    allKeys = [_dictionary allKeys];
    
    for (i = 0, count = [allKeys count]; i < count; i++) {
        NSString *aKey;
        OFDatedMutableDictionaryEntry *entry;

        aKey = [allKeys objectAtIndex:i];
        entry = [_dictionary objectForKey:aKey];

        if ([cutoffDate isAfterDate:[entry lastAccess]])
            [_dictionary removeObjectForKey:aKey];
    }
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:_dictionary forKey:@"datedDictionary"];
    return debugDictionary;
}

@end

@implementation OFDatedMutableDictionaryEntry

- initWithObject:(id)anObject;
{
    [super init];
    object = [anObject retain];
    lastAccess = [[NSDate alloc] init];
    return self;
}

- (id)object;
{
    [lastAccess release];
    lastAccess = [[NSDate alloc] init];
    return object;
}

- (id)objectWithNoAccessUpdate;
{
    return object;
}

- (NSDate *)lastAccess;
{
    return lastAccess;
}

- (void)dealloc;
{
    [object release];
    [lastAccess release];
    [super dealloc];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:object forKey:@"object"];
    [debugDictionary setObject:lastAccess forKey:@"lastAccess"];
    return debugDictionary;
}

@end
