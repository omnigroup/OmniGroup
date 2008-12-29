// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLWhitespaceBehavior.h>

#import <OmniFoundation/CFDictionary-OFExtensions.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/XML/OFXMLWhitespaceBehavior.m 103418 2008-07-28 22:35:38Z wiml $");

@implementation OFXMLWhitespaceBehavior

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
    
    if (behavior == OFXMLWhitespaceBehaviorTypeAuto)
        CFDictionaryRemoveValue(_nameToBehavior, elementName);
    else {
        OFCFDictionarySetUIntegerValue(_nameToBehavior, elementName, behavior);
    }
}

- (OFXMLWhitespaceBehaviorType)behaviorForElementName:(NSString *)elementName;
{
    return OFCFDictionaryGetUIntegerValueWithDefault(_nameToBehavior, elementName, _defaultBehavior);
}

@end
