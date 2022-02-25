// Copyright 2003-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLWhitespaceBehavior.h>

#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OFXMLWhitespaceBehavior

+ (OFXMLWhitespaceBehavior *)autoWhitespaceBehavior;
{
    static OFXMLWhitespaceBehavior *whitespace = nil;
    
    if (!whitespace)
        whitespace = [[OFXMLWhitespaceBehavior alloc] initWithDefaultBehavior:OFXMLWhitespaceBehaviorTypeAuto];
    
    return whitespace;
}

+ (OFXMLWhitespaceBehavior *)ignoreWhitespaceBehavior;
{
    static OFXMLWhitespaceBehavior *whitespace = nil;
    
    if (!whitespace)
        whitespace = [[OFXMLWhitespaceBehavior alloc] initWithDefaultBehavior:OFXMLWhitespaceBehaviorTypeIgnore];
    
    return whitespace;
}

// Init and dealloc

- initWithDefaultBehavior:(OFXMLWhitespaceBehaviorType)defaultBehavior;
{
    if (!(self = [super init]))
        return nil;

    _defaultBehavior = defaultBehavior;

    return self;
}

- init;
{
    return [self initWithDefaultBehavior:OFXMLWhitespaceBehaviorTypeAuto];
}

- (void)dealloc;
{
    if (_nameToBehavior)
        CFRelease(_nameToBehavior);
    [super dealloc];
}

- (OFXMLWhitespaceBehaviorType)defaultBehavior;
{
    return _defaultBehavior;
}

- (void)setBehavior:(OFXMLWhitespaceBehaviorType)behavior forElementName:(NSString *)elementName;
{
    OBPRECONDITION(OFXMLWhitespaceBehaviorTypeAuto == 0);
    
    if (behavior == OFXMLWhitespaceBehaviorTypeAuto) {
        if (_nameToBehavior) {
            CFDictionaryRemoveValue(_nameToBehavior, (__bridge CFStringRef)elementName);
        }
    } else {
        if (!_nameToBehavior) {
            _nameToBehavior = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &OFIntegerDictionaryValueCallbacks);
        }
        OFCFDictionarySetUIntegerValue(_nameToBehavior, (__bridge CFStringRef)elementName, behavior);
    }
}

- (OFXMLWhitespaceBehaviorType)behaviorForElementName:(NSString *)elementName;
{
    if (_nameToBehavior) {
        return (OFXMLWhitespaceBehaviorType)OFCFDictionaryGetUIntegerValueWithDefault(_nameToBehavior, (__bridge CFStringRef)elementName, _defaultBehavior);
    } else {
        return _defaultBehavior;
    }
}

@end

NS_ASSUME_NONNULL_END
