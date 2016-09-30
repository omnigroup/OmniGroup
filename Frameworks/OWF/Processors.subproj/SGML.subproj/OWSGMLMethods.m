// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
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

    parent = aParent;
    implementationForTagDictionary = [[NSMutableDictionary alloc] init];
    implementationForEndTagDictionary = [[NSMutableDictionary alloc] init];

    return self;
}

- init;
{
    return [self initWithParent:nil];
}

// API

- (void)registerHandler:(OWSGMLMethodHandler)handler forTagName:(NSString *)tagName inDictionary:(NSMutableDictionary *)dictionary;
{
    if (handler == nil)
	return;
    
    handler = [handler copy];
    [dictionary setObject:handler forKey:[tagName lowercaseString]];
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
    if (parent == nil)
        return implementationForTagDictionary;

    NSMutableDictionary *mergedDictionary = [[parent implementationForTagDictionary] mutableCopy];
    [mergedDictionary addEntriesFromDictionary:implementationForTagDictionary];
    return mergedDictionary;
}

- (NSDictionary *)implementationForEndTagDictionary;
{
    if (parent == nil)
        return implementationForEndTagDictionary;

    NSMutableDictionary *mergedDictionary = [[parent implementationForEndTagDictionary] mutableCopy];
    [mergedDictionary addEntriesFromDictionary:implementationForEndTagDictionary];
    return mergedDictionary;
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
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
    NSEnumerator *tagNameEnumerator = [implementationForTagDictionary keyEnumerator];

    NSString *tagName;
    while ((tagName = [tagNameEnumerator nextObject]) != nil)
        [aDTD tagTypeNamed:tagName];
    tagNameEnumerator = [implementationForEndTagDictionary keyEnumerator];
    while ((tagName = [tagNameEnumerator nextObject]) != nil)
        [aDTD tagTypeNamed:tagName];
}

@end
