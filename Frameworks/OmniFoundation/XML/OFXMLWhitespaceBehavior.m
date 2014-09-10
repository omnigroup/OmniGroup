// Copyright 2003-2005, 2007-2008, 2010-2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLWhitespaceBehavior.h>

#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

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
    _nameToBehavior = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &OFIntegerDictionaryValueCallbacks);
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
        CFDictionaryRemoveValue(_nameToBehavior, (__bridge CFStringRef)elementName);
    } else {
        OFCFDictionarySetUIntegerValue(_nameToBehavior, (__bridge CFStringRef)elementName, behavior);
    }
}

- (OFXMLWhitespaceBehaviorType)behaviorForElementName:(NSString *)elementName;
{
    return (OFXMLWhitespaceBehaviorType)OFCFDictionaryGetUIntegerValueWithDefault(_nameToBehavior, (__bridge CFStringRef)elementName, _defaultBehavior);
}

@end
