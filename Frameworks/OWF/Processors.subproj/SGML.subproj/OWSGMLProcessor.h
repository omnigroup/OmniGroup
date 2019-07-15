// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWObjectStreamProcessor.h>

@class NSMutableArray, NSUserDefaults;
@class OWAddress, OWSGMLAppliedMethods, OWSGMLDTD, OWSGMLMethods, OWSGMLTag, OWSGMLTagType;

@interface OWSGMLProcessor : OWObjectStreamProcessor
{
    OWSGMLAppliedMethods *appliedMethods;
    OWAddress *baseAddress;
    unsigned int *openTags;
    unsigned int *implicitlyClosedTags;
    NSMutableArray *undoers;
}

+ (OWSGMLMethods *)sgmlMethods;
+ (OWSGMLDTD *)dtd;

+ (void)setDebug:(BOOL)newDebugSetting;

- (void)setBaseAddress:(OWAddress *)anAddress;

- (BOOL)hasOpenTagOfType:(OWSGMLTagType *)tagType;
- (void)openTagOfType:(OWSGMLTagType *)tagType;
- (void)closeTagOfType:(OWSGMLTagType *)tagType;

- (void)processContentForTag:(OWSGMLTag *)tag;
- (void)processUnknownTag:(OWSGMLTag *)tag;
- (void)processIgnoredContentsTag:(OWSGMLTag *)tag;
- (void)processTag:(OWSGMLTag *)tag;
- (BOOL)processEndTag:(OWSGMLTag *)tag;
- (void)processCData:(NSString *)cData;

- (OWAddress *)baseAddress;

@end

@interface OWSGMLProcessor (Tags)
- (OWAddress *)addressForAnchorTag:(OWSGMLTag *)tag;
- (void)processMeaninglessTag:(OWSGMLTag *)tag;
- (void)processBaseTag:(OWSGMLTag *)tag;
- (void)processMetaTag:(OWSGMLTag *)tag;
- (void)processHTTPEquivalent:(NSString *)header value:(NSString *)value;  // To be overridden by subclasses
- (void)processTitleTag:(OWSGMLTag *)tag;
@end

@interface OWSGMLProcessor (SubclassesOnly)
- (BOOL)_hasOpenTagOfTypeIndex:(NSUInteger)tagIndex;
- (void)_openTagOfTypeIndex:(NSUInteger)tagIndex;
- (void)_implicitlyCloseTagAtIndex:(NSUInteger)tagIndex;
- (BOOL)_closeTagAtIndexWasImplicit:(NSUInteger)tagIndex;
@end
