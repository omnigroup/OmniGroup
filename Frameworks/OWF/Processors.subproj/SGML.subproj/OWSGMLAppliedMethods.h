// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class OWSGMLDTD, OWSGMLMethods, OWSGMLTag;

@interface OWSGMLAppliedMethods : OFObject

- initFromSGMLMethods:(OWSGMLMethods *)sgmlMethods dtd:(OWSGMLDTD *)dtd forTargetClass:(Class)targetClass;

@end

extern void sgmlAppliedMethodsInvokeTag(OWSGMLAppliedMethods *self, unsigned int tagIndex, id target, OWSGMLTag *tag);
extern BOOL sgmlAppliedMethodsInvokeEndTag(OWSGMLAppliedMethods *self, unsigned int tagIndex, id target, OWSGMLTag *tag);

