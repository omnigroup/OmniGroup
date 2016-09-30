// Copyright 2000-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWDataStreamCharacterProcessor.h>

#import <Foundation/Foundation.h>
#import <CoreFoundation/CFString.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContent.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWDataStreamCursor.h>
#import <OWF/OWDataStreamCharacterCursor.h>
#import <OWF/OWHeaderDictionary.h>
#import <OWF/OWParameterizedContentType.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWSitePreference.h>

RCS_ID("$Id$")

@implementation OWDataStreamCharacterProcessor

NSString *OWEncodingDefaultContextKey = @"EncodingDefault";
NSString *OWEncodingOverrideContextKey = @"EncodingOverride";

static OFPreference *cp1252OverridePref = nil;

+ (void)initialize
{
    OBINITIALIZE;

    cp1252OverridePref = [OFPreference preferenceForKey:@"OWUseCP1252ForLatin1"];
}

+ (CFStringEncoding)stringEncodingForAddress:(OWAddress *)anAddress;
{
    CFStringEncoding cfEncoding = [self stringEncodingForDefault:[[OWSitePreference preferenceForKey:@"OWIncomingStringEncoding" address:anAddress] stringValue]];
    switch (cfEncoding) {
        case kCFStringEncodingInvalidId: // If unset, use ISO Latin 1
        case kCFStringEncodingISOLatin1:
            return [cp1252OverridePref boolValue] ? kCFStringEncodingWindowsLatin1 : kCFStringEncodingISOLatin1;
        case kCFStringEncodingBig5:
            return kCFStringEncodingDOSChineseTrad;
        default:
            return cfEncoding;
    }
}

+ (CFStringEncoding)defaultStringEncoding;
{
    return [self stringEncodingForAddress:nil];
}

+ (CFStringEncoding)stringEncodingForDefault:(NSString *)encodingName;
{
    // Note that this default can be either a string or an integer. Integers refer to NSStringEncoding values. Strings consist of a prefix, a space, and a string whose meaning depends on the prefix. Currently understood prefixes are "ietf" (indicating an IETF charset name) and "cf" (indicating a CoreFoundation encoding number). Previously understood prefixes were the names of OWStringDocoder-conformant classes, but we don't do that any more.
    
    CFStringEncoding cfEncoding = kCFStringEncodingInvalidId;
    if ([encodingName hasPrefix:@"iana "]) {
        NSString *ietfName = [encodingName substringFromIndex:5];
        cfEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)ietfName);
    } else if ([encodingName hasPrefix:@"cf "]) {
        cfEncoding = [[encodingName substringFromIndex:3] intValue];
    } else if ([encodingName hasPrefix:@"omni "]) {
            return kCFStringEncodingInvalidId;
    }
    
    if (cfEncoding != kCFStringEncodingInvalidId)
        return cfEncoding;
    
    NSStringEncoding stringEncoding = [encodingName intValue];
    // Note that 0 is guaranteed never to be a valid encoding by the semantics of +[NSString availableStringEncodings]. (0 used to be used for the Unicode string encoding.)
    if (stringEncoding != 0)
        return CFStringConvertNSStringEncodingToEncoding(stringEncoding);
    
    return kCFStringEncodingInvalidId;
}

+ (NSString *)defaultForCFEncoding:(CFStringEncoding)anEncoding;
{
    NSString *encodingName;
    
    switch(anEncoding) {
        case kCFStringEncodingInvalidId:
            return @"0";
        default:
            break;
    }
        
    encodingName = (NSString *)CFStringConvertEncodingToIANACharSetName(anEncoding);
    if (encodingName != nil && ![encodingName hasPrefix:@"x-"] && ![encodingName hasPrefix:@"X-"])
        return [@"iana " stringByAppendingString:encodingName];
    
    return [NSString stringWithFormat:@"cf %d", anEncoding];
}

+ (CFStringEncoding)stringEncodingForIANACharSetName:(NSString *)charset;
{
    CFStringEncoding cfEncoding;
    
    // First normalize away common errors.
    if (![charset hasPrefix:@"iso"]) {
        // Some web sites incorrectly specify (e.g.) ISO-8859-1. We don't want to lowercase all charsets, since some of them are in fact uppercase or mixed case, at least according to CoreFoundation. But all the ISO-Latin charsets seem to be lower case in CF's view.
        NSRange findRange;
        
        findRange = [charset rangeOfString:@"iso" options:NSCaseInsensitiveSearch];
        if (findRange.length != 0 && findRange.location == 0)
            charset = [charset lowercaseString];
    }
    if ([charset hasPrefix:@"iso8859-"]) {
        // Some web sites use iso8859 rather than iso-8859.
        charset = [@"iso-" stringByAppendingString:[charset substringFromIndex:3]];
    }
    
    // Actually look up the encoding.
    
    if ([charset hasPrefix:@"x-mac-cf-"]) {
        cfEncoding = [[charset substringFromIndex:9] intValue];
        if (!CFStringIsEncodingAvailable(cfEncoding))
            cfEncoding = kCFStringEncodingInvalidId;
    } else if ([charset caseInsensitiveCompare:@"visual"] == NSOrderedSame) {
        // In Internet Explorer, "Visual" (for "Visual Hebrew") is an alias for iso-8859-8 (or, more likely, a windows-specific Hebrew code-page?)
        cfEncoding = kCFStringEncodingISOLatinHebrew;
    } else {
        cfEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)charset);
    }

    // Override so that stupid Microsoft web authoring tools that use CP1252 but don't include a charset tag will work.
    
    switch (cfEncoding) {
        case kCFStringEncodingISOLatin1:
            // Windows-1252 (Windows Latin 1) is a superset of iso-8859-1 (ISO Latin 1), and unfortunately many web sites request iso-8859-1 when they actually use characters that only exist in windows-1252, like '\226'.
            return [cp1252OverridePref boolValue] ? kCFStringEncodingWindowsLatin1 : cfEncoding;
        case kCFStringEncodingBig5:
            // kc@omni 2001/12/18: We now return code page 950 when a page asks for "Big5", since Big5 has several variants and authors seem to generally expect this one (as it's the one used by DOS/Windows).
            return kCFStringEncodingDOSChineseTrad;
        case kCFStringEncodingInvalidId:
            NSLog(@"Warning: Cannot convert charset \"%@\" to string encoding; using default encoding instead", charset);
            return cfEncoding;
        default:
            return cfEncoding;
    }
}

+ (CFStringEncoding)stringEncodingForContentType:(OWParameterizedContentType *)aType;
{
    NSString *charset;
    
    if (aType == nil)
        return kCFStringEncodingInvalidId;
    
    charset = [aType objectForKey:@"charset"];
    if (charset != nil)
        return [self stringEncodingForIANACharSetName:charset];
    else
        return kCFStringEncodingInvalidId;
}

+ (NSString *)charsetForCFEncoding:(CFStringEncoding)anEncoding
{
    if (anEncoding == kCFStringEncodingInvalidId)
        return nil;
        
    NSString *charsetName = (NSString *)CFStringConvertEncodingToIANACharSetName(anEncoding);
    if (charsetName != nil)
        return charsetName;
    
    return [NSString stringWithFormat:@"x-mac-cf-%d", anEncoding];
}

// Init and dealloc

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    self = [super initWithContent:initialContent context:aPipeline];
    if (self == nil)
        return nil;

    OWDataStreamCursor *dataCursor = [initialContent dataCursor];
    if (dataCursor == nil) {
        self = nil;
        return nil;
    }
    OBASSERT([dataCursor isKindOfClass:[OWDataStreamCursor class]]);

    CFStringEncoding stringEncoding = [self chooseStringEncoding:dataCursor content:initialContent];

    characterCursor = [[OWDataStreamCharacterCursor alloc] initForDataCursor:dataCursor encoding:stringEncoding];

    return self;
}

// OWProcessor subclass

- (void)abortProcessing;
{
    [characterCursor abort];
    [super abortProcessing];
}

// Overridable by subclasses

- (CFStringEncoding)chooseStringEncoding:(OWDataStreamCursor *)dataCursor content:(OWContent *)sourceContent
{
    NSNumber *encodingOverrideNumber;
    CFStringEncoding specifiedEncoding;

    specifiedEncoding = [[self class] stringEncodingForContentType:[sourceContent fullContentType]];
    encodingOverrideNumber = [self.pipeline contextObjectForKey:OWEncodingOverrideContextKey];
    if (encodingOverrideNumber != nil) {
        NSNumber *oldEncodingProvenance;
        CFStringEncoding encodingOverride;

        oldEncodingProvenance = [sourceContent lastObjectForKey:OWContentEncodingProvenanceMetadataKey];
        encodingOverride = [encodingOverrideNumber intValue];
        if (oldEncodingProvenance == nil || specifiedEncoding == kCFStringEncodingInvalidId ||
            [oldEncodingProvenance intValue] <= OWStringEncodingProvenance_WindowPreference)
            return encodingOverride;
    }

    if (specifiedEncoding == kCFStringEncodingInvalidId) {
        NSNumber *encodingDefaultNumber;

        encodingDefaultNumber = [self.pipeline contextObjectForKey:OWEncodingDefaultContextKey];
        if (encodingDefaultNumber != nil) {
            CFStringEncoding encodingDefault;
            
            encodingDefault = [encodingDefaultNumber intValue];
            if (encodingDefault != kCFStringEncodingInvalidId)
                return encodingDefault;
        }
        return [[self class] defaultStringEncoding];
    } else
        return specifiedEncoding;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    if (characterCursor)
        [debugDictionary setObject:characterCursor forKey:@"characterCursor"];

    return debugDictionary;
}

@end
