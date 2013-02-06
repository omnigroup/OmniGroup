// Copyright 1997-2005, 2011, 2013 Omni Development, Inc. All rights reserved.
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
{
    OWSGMLMethods *parent;
    NSMutableDictionary *implementationForTagDictionary;
    NSMutableDictionary *implementationForEndTagDictionary;
}

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

- (void)registerHandler:(OWSGMLMethodHandler)handler forTagName:(NSString *)tagName inDictionary:(NSMutableDictionary *)dictionary;
{
    if (!handler)
	return;
    
    handler = [handler copy];
    [dictionary setObject:handler forKey:[tagName lowercaseString]];
    [handler release];
}

- (void)registerTagName:(NSString *)tagName startHandler:(OWSGMLMethodHandler)handler;
{
    [self registerHandler:handler forTagName:tagName inDictionary:implementationForTagDictionary];
}

- (void)registerTagName:(NSString *)tagName endHandler:(OWSGMLMethodHandler)handler;
{
    [self registerHandler:handler forTagName:tagName inDictionary:implementationForEndTagDictionary];
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
