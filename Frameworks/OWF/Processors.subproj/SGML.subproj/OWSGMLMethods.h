// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class OWSGMLDTD, OWSGMLTag;

typedef void (^OWSGMLMethodHandler)(id receiver, OWSGMLTag *tag);

@interface OWSGMLMethods : OFObject

- initWithParent:(OWSGMLMethods *)aParent;

- (void)registerTagName:(NSString *)tagName startHandler:(OWSGMLMethodHandler)handler;
- (void)registerTagName:(NSString *)tagName endHandler:(OWSGMLMethodHandler)handler;

- (NSDictionary *)implementationForTagDictionary;
- (NSDictionary *)implementationForEndTagDictionary;

@end

#define OWSGMLMethodStartHandler(cls, methodName, tagName) do { \
  [methods registerTagName:@#tagName startHandler:^(cls *processor, OWSGMLTag *tag){ \
        [processor process ## methodName ## Tag:tag]; \
  }]; \
} while(0)

#define OWSGMLMethodEndHandler(cls, methodName, tagName) do { \
    [methods registerTagName:@#tagName endHandler:^(cls *processor, OWSGMLTag *tag){ \
        [processor process ## methodName ## Tag:tag]; \
    }]; \
} while(0)

@interface OWSGMLMethods (DTD)
- (void)registerTagsWithDTD:(OWSGMLDTD *)aDTD;
@end
