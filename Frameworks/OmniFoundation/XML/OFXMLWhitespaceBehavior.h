// Copyright 2003-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <CoreFoundation/CFDictionary.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSInteger, OFXMLWhitespaceBehaviorType) {
    OFXMLWhitespaceBehaviorTypeAuto,     // do whatever the parent node did -- the default
    OFXMLWhitespaceBehaviorTypeIgnore,   // whitespace is irrelevant
    OFXMLWhitespaceBehaviorTypePreserve, // whitespace is important -- leave it as is
};

@interface OFXMLWhitespaceBehavior : NSObject
{
    OFXMLWhitespaceBehaviorType _defaultBehavior;
    CFMutableDictionaryRef _nameToBehavior;
}

@property(nonatomic,readonly,class) OFXMLWhitespaceBehavior *autoWhitespaceBehavior;
@property(nonatomic,readonly,class) OFXMLWhitespaceBehavior *ignoreWhitespaceBehavior;

- initWithDefaultBehavior:(OFXMLWhitespaceBehaviorType)defaultBehavior;

@property(nonatomic,readonly) OFXMLWhitespaceBehaviorType defaultBehavior;

- (void)setBehavior:(OFXMLWhitespaceBehaviorType)behavior forElementName:(NSString *)elementName;
- (OFXMLWhitespaceBehaviorType)behaviorForElementName:(NSString *)elementName;

@end

NS_ASSUME_NONNULL_END
