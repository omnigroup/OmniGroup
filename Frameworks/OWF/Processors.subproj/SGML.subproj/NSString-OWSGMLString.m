// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/NSString-OWSGMLString.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWHTMLToSGMLObjects.h>   // for +entityNameForCharacter:

RCS_ID("$Id$")

@interface NSString (OWSGMLStringPrivate)
+ (NSCharacterSet *)needsEscapeCharacterSet;
@end

@implementation NSString (OWSGMLString)

- (NSString *)stringWithEntitiesQuoted;
{
    return [self stringWithEntitiesQuoted:SGMLQuoting_NamedEntities];
}

- (NSString *)stringWithEntitiesQuoted:(int)tFlags;
{
    OFDataBuffer dataBuffer;
    NSString *escapedString;
    NSString *numericFormat;
    const short flags = tFlags;

    if (![self rangeOfCharacterFromSet:[NSString needsEscapeCharacterSet]].length)
        return self;

    // Set up output buffer
    OFDataBufferInit(&dataBuffer);
    OFDataBufferAppendUnicodeByteOrderMark(&dataBuffer);
    
    if (flags & SGMLQuoting_HexadecimalEntities)
        numericFormat = @"&#x%04x;";
    else
        numericFormat = @"&#%d;";

    OFStringStartLoopThroughCharacters(self, ch) {
        if (((ch == '"') && !(flags & SGMLQuoting_AllowAttributeMetas)) ||
            ((ch == '<' || ch == '>') && !(flags & SGMLQuoting_AllowPCDATAMetas)) ||
            (ch == '&') ||
            ((ch > 0x007F) && !(flags & SGMLQuoting_AllowNonASCII))) {
            
            if (flags & SGMLQuoting_NamedEntities) {
                NSString *entityName = [OWHTMLToSGMLObjects entityNameForCharacter:ch];
                
                if (entityName) {
                    OFDataBufferAppendUnichar(&dataBuffer, '&');
                    OFDataBufferAppendUnicodeString(&dataBuffer, (__bridge CFStringRef)entityName);
                    OFDataBufferAppendUnichar(&dataBuffer, ';');
                    continue;
                }
            }
            
            OFDataBufferAppendUnicodeString(&dataBuffer, (__bridge CFStringRef)[NSString stringWithFormat:numericFormat, ch]);
        } else
            OFDataBufferAppendUnichar(&dataBuffer, ch);
    } OFStringEndLoopThroughCharacters;
    
    // Slurp data into string
    CFDataRef data = NULL;
    OFDataBufferRelease(&dataBuffer, kCFAllocatorDefault, &data);
    escapedString = [[NSString alloc] initWithData:CFBridgingRelease(data) encoding:NSUnicodeStringEncoding];

    return escapedString;
}

// OWSGMLToken protocol

- (NSString *)sgmlString;
{
    return [self stringWithEntitiesQuoted];
}

- (NSString *)sgmlStringWithQuotingFlags:(int)flags;
{
    return [self stringWithEntitiesQuoted:flags];
}

- (NSString *)string;
{
    return self;
}

- (OWSGMLTokenType)tokenType;
{
    return OWSGMLTokenTypeCData;
}

@end

@implementation NSString (OWSGMLStringPrivate)

OBDidLoad(^{
    Class self = [NSString class];
    
    // Ensure +needsEscapeCharacterSet gets set up before we go multithreaded, since then we'd have to deal with leaks or locks.
    [self needsEscapeCharacterSet];
});

+ (NSCharacterSet *)needsEscapeCharacterSet;
{
    static NSMutableCharacterSet *needsEscapeCharacterSet = nil;

    if (needsEscapeCharacterSet)
        return needsEscapeCharacterSet;

    needsEscapeCharacterSet = [[NSMutableCharacterSet alloc] init];
    [needsEscapeCharacterSet addCharactersInRange:NSMakeRange(0, 128)];
    [needsEscapeCharacterSet invert];
    [needsEscapeCharacterSet addCharactersInString:@"&<>\""];

    return needsEscapeCharacterSet;
}

@end
