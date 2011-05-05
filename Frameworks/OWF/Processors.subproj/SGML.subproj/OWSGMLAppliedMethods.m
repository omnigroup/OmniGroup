// Copyright 1997-2005, 2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWSGMLAppliedMethods.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWSGMLDTD.h>
#import <OWF/OWSGMLMethods.h>
#import <OWF/OWSGMLTagType.h>

RCS_ID("$Id$")

@implementation OWSGMLAppliedMethods

- initFromSGMLMethods:(OWSGMLMethods *)sgmlMethods dtd:(OWSGMLDTD *)dtd forTargetClass:(Class)targetClass;
{
    unsigned int tagIndex;
    NSDictionary *implementationForTagDictionary;
    NSDictionary *implementationForEndTagDictionary;
    NSEnumerator *tagNameEnumerator;
    NSString *tagName;
    SEL unknownTagSelector;
    voidIMP unknownTagImplementation;
    NSZone *myZone;

    if (!(self = [super init]))
        return nil;

    myZone = [self zone];
    
    tagCount = [dtd tagCount];

    if (tagCount > 0) {
        tagImplementation = NSZoneMalloc(myZone, tagCount * sizeof(voidIMP));
        endTagImplementation = NSZoneMalloc(myZone, tagCount * sizeof(voidIMP));
        tagSelector = NSZoneMalloc(myZone, tagCount * sizeof(SEL));
        endTagSelector = NSZoneMalloc(myZone, tagCount * sizeof(SEL));
    }

    unknownTagSelector = @selector(processUnknownTag:);
    unknownTagImplementation = (voidIMP)[targetClass instanceMethodForSelector:unknownTagSelector];
    for (tagIndex = 0; tagIndex < tagCount; tagIndex++) {
        tagImplementation[tagIndex] = unknownTagImplementation;
	tagSelector[tagIndex] = unknownTagSelector;
	endTagImplementation[tagIndex] = NULL;
	tagSelector[tagIndex] = unknownTagSelector;
    }

    implementationForTagDictionary = [sgmlMethods implementationForTagDictionary];
    implementationForEndTagDictionary = [sgmlMethods implementationForEndTagDictionary];
    tagNameEnumerator = [implementationForTagDictionary keyEnumerator];
    while ((tagName = [tagNameEnumerator nextObject])) {
	OFImplementationHolder *implementationHolder;
	SEL selector;

        if (![dtd hasTagTypeNamed:tagName]) {
#if DEBUG
            NSLog(@"OWSGMLAppliedMethods: <%@> isn't in dtd", tagName);
#endif // DEBUG
            continue;
        }
	implementationHolder = [implementationForTagDictionary objectForKey:tagName];
	selector = [implementationHolder selector];
	tagIndex = [[dtd tagTypeNamed:tagName] dtdIndex];
	tagImplementation[tagIndex] = (voidIMP)[targetClass instanceMethodForSelector:selector];
	tagSelector[tagIndex] = selector;
    }
    tagNameEnumerator = [implementationForEndTagDictionary keyEnumerator];
    while ((tagName = [tagNameEnumerator nextObject])) {
	OFImplementationHolder *implementationHolder;
	SEL selector;

        if (![dtd hasTagTypeNamed:tagName]) {
            NSLog(@"OWSGMLAppliedMethods: <%@> isn't in dtd", tagName);
            continue;
        }
	implementationHolder = [implementationForEndTagDictionary objectForKey:tagName];
	selector = [implementationHolder selector];
	tagIndex = [[dtd tagTypeNamed:tagName] dtdIndex];
	endTagImplementation[tagIndex] = (voidIMP)[targetClass instanceMethodForSelector:selector];
	endTagSelector[tagIndex] = selector;
    }

    return self;
}

- (void)dealloc;
{
    if (tagCount > 0) {
        NSZone *myZone = NSZoneFromPointer(tagImplementation);
        NSZoneFree(myZone, tagImplementation);
        NSZoneFree(myZone, tagSelector);
        NSZoneFree(myZone, endTagImplementation);
        NSZoneFree(myZone, endTagSelector);
    }

    [super dealloc];
}

- (void)invokeTagAtIndex:(unsigned int)tagIndex forTarget:(id)target withObject:(id)anObject;
{
    sgmlAppliedMethodsInvokeTag(self, tagIndex, target, anObject);
}

- (BOOL)invokeEndTagAtIndex:(unsigned int)tagIndex forTarget:(id)target withObject:(id)anObject;
{
    return sgmlAppliedMethodsInvokeEndTag(self, tagIndex, target, anObject);
}

@end
