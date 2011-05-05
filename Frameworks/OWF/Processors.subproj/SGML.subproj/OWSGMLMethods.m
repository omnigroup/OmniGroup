// Copyright 1997-2005, 2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWSGMLMethods.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWSGMLTag.h>

RCS_ID("$Id$")

@implementation OWSGMLMethods

// Init and dealloc

- initWithParent:(OWSGMLMethods *)aParent;
{
    if (!(self = [super init]))
        return nil;

    parent = [aParent retain];
    implementationForTagDictionary = [[NSMutableDictionary alloc] init];
    implementationForEndTagDictionary = [[NSMutableDictionary alloc] init];

    return self;
}

- init;
{
    return [self initWithParent:nil];
}

- (void)dealloc;
{
    [parent release];
    [implementationForTagDictionary release];
    [implementationForEndTagDictionary release];
    [super dealloc];
}

// API

- (void)registerSelector:(SEL)selector forTagName:(NSString *)tagName inDictionary:(NSMutableDictionary *)dictionary;
{
    OFImplementationHolder *implementation;

    if (!selector)
	return;
    implementation = [[OFImplementationHolder alloc] initWithSelector:selector];
    [dictionary setObject:implementation forKey:[tagName lowercaseString]];
    [implementation release];
}

- (void)registerSelector:(SEL)selector forTagName:(NSString *)tagName;
{
    [self registerSelector:selector forTagName:tagName inDictionary:implementationForTagDictionary];
}

- (void)registerMethod:(NSString *)name forTagName:(NSString *)tagName;
{
    NSString *methodName;
    SEL selector;

    methodName = [NSString stringWithFormat:@"process%@Tag:", name];
    selector = NSSelectorFromString(methodName);
    if (selector != NULL) {
        [self registerSelector:selector forTagName:tagName];
    } else {
        NSLog(@"OWSGMLMethods warning:  Could not find selector for method named %@", methodName);
    }
}

- (void)registerSelector:(SEL)selector forEndTagName:(NSString *)tagName;
{
    [self registerSelector:selector forTagName:tagName inDictionary:implementationForEndTagDictionary];
}

- (void)registerMethod:(NSString *)name forEndTagName:(NSString *)tagName;
{
    NSString *methodName;
    SEL selector;

    methodName = [NSString stringWithFormat:@"process%@Tag:", name];
    selector = NSSelectorFromString(methodName);
    if (selector != NULL) {
        [self registerSelector:selector forEndTagName:tagName];
    } else {
        NSLog(@"OWSGMLMethods warning:  Could not find selector for method named %@", methodName);
    }
}

- (NSDictionary *)implementationForTagDictionary;
{
    NSMutableDictionary *mergedDictionary;

    if (!parent)
        return implementationForTagDictionary;
    mergedDictionary = [[parent implementationForTagDictionary] mutableCopy];
    [mergedDictionary addEntriesFromDictionary:implementationForTagDictionary];
    return [mergedDictionary autorelease];
}

- (NSDictionary *)implementationForEndTagDictionary;
{
    NSMutableDictionary *mergedDictionary;

    if (!parent)
        return implementationForEndTagDictionary;
    mergedDictionary = [[parent implementationForEndTagDictionary] mutableCopy];
    [mergedDictionary addEntriesFromDictionary:implementationForEndTagDictionary];
    return [mergedDictionary autorelease];
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (parent)
        [debugDictionary setObject:parent forKey:@"parent"];
    if (implementationForTagDictionary)
	[debugDictionary setObject:implementationForTagDictionary forKey:@"implementationForTagDictionary"];
    if (implementationForEndTagDictionary)
	[debugDictionary setObject:implementationForEndTagDictionary forKey:@"implementationForEndTagDictionary"];
    return debugDictionary;
}

@end

#import <OWF/OWSGMLDTD.h>

@implementation OWSGMLMethods (DTD)

- (void)registerTagsWithDTD:(OWSGMLDTD *)aDTD;
{
    NSEnumerator *tagNameEnumerator;
    NSString *tagName;

    tagNameEnumerator = [implementationForTagDictionary keyEnumerator];
    while ((tagName = [tagNameEnumerator nextObject]))
        [aDTD tagTypeNamed:tagName];
    tagNameEnumerator = [implementationForEndTagDictionary keyEnumerator];
    while ((tagName = [tagNameEnumerator nextObject]))
        [aDTD tagTypeNamed:tagName];
}

@end
