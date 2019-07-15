// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTrieBucket.h>

@class NSArray, NSMutableArray;
@class OFTrie;
@class OWSGMLTag;

typedef enum {
    OWSGMLTagContentHandlingNormal, OWSGMLTagContentHandlingNonSGML, OWSGMLTagContentHandlingNonSGMLWithEntities,
} OWSGMLTagContentHandlingType;

@interface OWSGMLTagType : OFTrieBucket
{
@public
    NSString *name;
    unsigned int dtdIndex;
    OWSGMLTagType *masterAttributesTagType;
    NSMutableArray *attributeNames;
    OFTrie *attributeTrie;
    OWSGMLTagContentHandlingType contentHandling;

    OWSGMLTag *attributelessStartTag;
    OWSGMLTag *attributelessEndTag;
    /* TODO: attributelessEmptyTag for XML ? */
}

// Attributes common to all tags
+ (unsigned int)idAttributeIndex;
+ (unsigned int)classAttributeIndex;
+ (unsigned int)styleAttributeIndex;

// Init
- initWithName:(NSString *)aName dtdIndex:(unsigned int)anIndex;

// API
- (NSString *)name;
- (unsigned int)dtdIndex;
- (OWSGMLTagType *)masterAttributesTagType;
- (NSArray *)attributeNames;
- (OFTrie *)attributeTrie;

- (void)shareAttributesWithTagType:(OWSGMLTagType *)aTagType;
- (NSUInteger)addAttributeNamed:(NSString *)attributeName;
- (NSUInteger)indexOfAttribute:(NSString *)attributeName;
- (NSUInteger)attributeCount;
- (BOOL)hasAttributeNamed:(NSString *)attributeName;

- (void)setContentHandling:(OWSGMLTagContentHandlingType)contentHandling;
- (OWSGMLTagContentHandlingType)contentHandling;

- (OWSGMLTag *)attributelessStartTag;
- (OWSGMLTag *)attributelessEndTag;

@end

static inline unsigned int tagTypeDtdIndex(OWSGMLTagType *tagType)
{
    return tagType->dtdIndex;
}
