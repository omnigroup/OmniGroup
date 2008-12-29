// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OWSGMLDTD, OWSGMLTag;

@interface OWSGMLMethods : OFObject
{
    OWSGMLMethods *parent;
    NSMutableDictionary *implementationForTagDictionary;
    NSMutableDictionary *implementationForEndTagDictionary;
}

- initWithParent:(OWSGMLMethods *)aParent;

- (void)registerSelector:(SEL)selector forTagName:(NSString *)tagName;
- (void)registerSelector:(SEL)selector forEndTagName:(NSString *)tagName;
- (void)registerMethod:(NSString *)name forTagName:(NSString *)tagName;
- (void)registerMethod:(NSString *)name forEndTagName:(NSString *)tagName;

- (NSDictionary *)implementationForTagDictionary;
- (NSDictionary *)implementationForEndTagDictionary;

@end

@interface OWSGMLMethods (DTD)
- (void)registerTagsWithDTD:(OWSGMLDTD *)aDTD;
@end
