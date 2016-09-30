// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
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
#import <OWF/OWSGMLProcessor.h>

RCS_ID("$Id$")

@implementation OWSGMLAppliedMethods
{
    __strong OWSGMLMethodHandler *_tagHandlers;
    __strong OWSGMLMethodHandler *_endTagHandlers;
    NSUInteger _tagCount;
}

static OWSGMLMethodHandler UnknownTagHandler;

+ (void)initialize;
{
    OBINITIALIZE;
    
    UnknownTagHandler = [^void(OWSGMLProcessor *processor, OWSGMLTag *tag){
        [processor processUnknownTag:tag];
    } copy];
}

void sgmlAppliedMethodsInvokeTag(OWSGMLAppliedMethods *self, unsigned int tagIndex, id target, OWSGMLTag *tag)
{
    if (tagIndex >= self->_tagCount)
        return;
    
    OWSGMLMethodHandler handler = self->_tagHandlers[tagIndex];
    handler(target, tag);
}

inline BOOL sgmlAppliedMethodsInvokeEndTag(OWSGMLAppliedMethods *self, unsigned int tagIndex, id target, OWSGMLTag *tag)
{
    if (tagIndex >= self->_tagCount)
        return NO;

    OWSGMLMethodHandler handler = self->_endTagHandlers[tagIndex];
    if (!handler)
        return NO;

    handler(target, tag);
    return YES;
}

- initFromSGMLMethods:(OWSGMLMethods *)sgmlMethods dtd:(OWSGMLDTD *)dtd forTargetClass:(Class)targetClass;
{
    if (!(self = [super init]))
        return nil;

    _tagCount = [dtd tagCount];
    if (_tagCount > 0) {
        _tagHandlers = (__strong OWSGMLMethodHandler *)calloc(_tagCount, sizeof(*_tagHandlers));
        _endTagHandlers = (__strong OWSGMLMethodHandler *)calloc(_tagCount, sizeof(*_tagHandlers));
    }
    
    for (NSUInteger tagIndex = 0; tagIndex < _tagCount; tagIndex++) {
        _tagHandlers[tagIndex] = UnknownTagHandler;
        _endTagHandlers[tagIndex] = NULL; // No default for end tags
    }

    [[sgmlMethods implementationForTagDictionary] enumerateKeysAndObjectsUsingBlock:^(NSString *tagName, OWSGMLMethodHandler handler, BOOL *stop) {
        if (![dtd hasTagTypeNamed:tagName]) {
#if DEBUG
            NSLog(@"OWSGMLAppliedMethods: <%@> isn't in dtd", tagName);
#endif // DEBUG
            return;
        }
	NSUInteger tagIndex = [[dtd tagTypeNamed:tagName] dtdIndex];
        OBASSERT(tagIndex < _tagCount);
	_tagHandlers[tagIndex] = handler;
    }];
    
    [[sgmlMethods implementationForEndTagDictionary] enumerateKeysAndObjectsUsingBlock:^(NSString *tagName, OWSGMLMethodHandler handler, BOOL *stop) {
        if (![dtd hasTagTypeNamed:tagName]) {
            NSLog(@"OWSGMLAppliedMethods: <%@> isn't in dtd", tagName);
            return;
        }
	NSUInteger tagIndex = [[dtd tagTypeNamed:tagName] dtdIndex];
        OBASSERT(tagIndex < _tagCount);
	_endTagHandlers[tagIndex] = handler;
    }];

    return self;
}

- (void)dealloc;
{
    if (_tagHandlers)
        free(_tagHandlers);
    if (_endTagHandlers)
        free(_endTagHandlers);
}

@end
