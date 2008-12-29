// Copyright 2003-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/XML/OFXMLWhitespaceBehavior.h 102870 2008-07-15 05:53:56Z bungi $

#import <Foundation/NSObject.h>

typedef enum _OFXMLWhitespaceBehaviorType {
    OFXMLWhitespaceBehaviorTypeAuto,     // do whatever the parent node did -- the default
    OFXMLWhitespaceBehaviorTypeIgnore,   // whitespace is irrelevant
    OFXMLWhitespaceBehaviorTypePreserve, // whitespace is important -- leave it as is
} OFXMLWhitespaceBehaviorType;

@interface OFXMLWhitespaceBehavior : NSObject
{
    OFXMLWhitespaceBehaviorType _defaultBehavior;
    CFMutableDictionaryRef _nameToBehavior;
}

+ (OFXMLWhitespaceBehavior *)ignoreWhitespaceBehavior;

- initWithDefaultBehavior:(OFXMLWhitespaceBehaviorType)defaultBehavior;

- (OFXMLWhitespaceBehaviorType)defaultBehavior;

- (void)setBehavior:(OFXMLWhitespaceBehaviorType)behavior forElementName:(NSString *)elementName;
- (OFXMLWhitespaceBehaviorType)behaviorForElementName:(NSString *)elementName;

@end
