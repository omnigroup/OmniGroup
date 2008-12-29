// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OWSGMLDTD, OWSGMLMethods;

#import <OmniFoundation/OFImplementationHolder.h> /* For voidIMP */

@interface OWSGMLAppliedMethods : OFObject
{
@public
    voidIMP *tagImplementation;
    SEL *tagSelector;
    voidIMP *endTagImplementation;
    SEL *endTagSelector;
    unsigned int tagCount;
}

- initFromSGMLMethods:(OWSGMLMethods *)sgmlMethods dtd:(OWSGMLDTD *)dtd forTargetClass:(Class)targetClass;

- (void)invokeTagAtIndex:(unsigned int)tagIndex forTarget:(id)target withObject:(id)anObject;
- (BOOL)invokeEndTagAtIndex:(unsigned int)tagIndex forTarget:(id)target withObject:(id)anObject;

@end

static inline void sgmlAppliedMethodsInvokeTag(OWSGMLAppliedMethods *methods, unsigned int tagIndex, id target, id anObject)
{
    if (tagIndex < methods->tagCount)
        methods->tagImplementation[tagIndex](target, methods->tagSelector[tagIndex], anObject);
}

static inline BOOL sgmlAppliedMethodsInvokeEndTag(OWSGMLAppliedMethods *methods, unsigned int tagIndex, id target, id anObject)
{
    if (tagIndex > methods->tagCount || !methods->endTagImplementation[tagIndex])
        return NO;
    methods->endTagImplementation[tagIndex](target, methods->tagSelector[tagIndex], anObject);
    return YES;
}
