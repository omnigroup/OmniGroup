// Copyright 2000-2005, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// This processor implements the data: url scheme described in RFC 2397

#import <OWF/OWDataURLProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWContent.h>
#import <OWF/OWContentType.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWParameterizedContentType.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

@implementation OWDataURLProcessor

/* hexDigit() is copied & pasted from OWURL, and decodeURLEscapedBytes() is very similar to some code in there. TODO: avoid unnecessary duplication of code. */
static inline unichar hexDigit(unichar digit)
{
    if (isdigit(digit))
	return digit - '0';
    else if (isupper(digit))
	return 10 + digit - 'A';
    else 
	return 10 + digit - 'a';
}

NSData *decodeURLEscapedBytes(NSString *input)
{
    OBFinishPorting; // 64->32 warnings -- if we even keep this framework
    return nil;
#if 0
    NSData *result;
    unichar *characters;
    unsigned char *bytes;
    unsigned int charCount, byteCount;
    unsigned int charIndex;
    
    charCount = [input length];
    
    characters = (unichar *)NSZoneMalloc(NULL, charCount * sizeof(*characters));
    [input getCharacters:characters];
    
    bytes = NSZoneMalloc(NULL, charCount);
    byteCount = 0;
    charIndex = 0;
    while(charIndex < charCount) {
        unsigned char byte;
        
        if (characters[charIndex] == '%' &&
            (charIndex+2 < charCount)) {
            byte = hexDigit(characters[charIndex+1]) << 4 | hexDigit(characters[charIndex+2]);
            charIndex += 3;
        } else {
            byte = characters[charIndex] & 0xFF;
            charIndex += 1;
        }
        
        bytes[byteCount++] = byte;
    }
    
    NSZoneFree(NULL, characters);
    result = [NSData dataWithBytes:bytes length:byteCount];
    NSZoneFree(NULL, bytes);
    
    return result;
#endif
}


+ (void)didLoad;
{
    [self registerProcessorClass:self fromContentType:[OWURL contentTypeForScheme:@"data"] toContentType:[OWContentType wildcardContentType] cost:1.0f producingSource:YES];
}


- (void)startProcessing
{
    [self processInThread];
}

- (void)process
{
    OBFinishPorting; // 64->32 warnings -- if we even keep this framework
#if 0
    NSString *dataString = [[sourceAddress url] schemeSpecificPart];
    NSRange comma;
    NSString *headersString;
    NSArray *headers;
    OWContentType *header;
    OWParameterizedContentType *fullHeader = nil;
    NSData *body;
    BOOL isBase64 = NO;
    int headerIndex, headerCount;
    NSString *part;
    OWDataStream *content;
    OWContent *nContent;
    
    comma = [dataString rangeOfString:@","];
    
    if (comma.length < 1) {
        [NSException raise:@"MalformedURL" reason:NSLocalizedStringFromTableInBundle(@"data: URL does not contain comma", @"OWF", [OWDataURLProcessor bundle], @"data: url error")];
    }
    
    header = [OWContentType contentTypeForString:@"text/plain"];

    headersString = [dataString substringToIndex:comma.location];
    
    if ([headersString length] > 0) {
        headers = [headersString componentsSeparatedByString:@";"];
        headerCount = [headers count];
    } else {
        headers = nil;
        headerCount = 0;
    }
            
    for(headerIndex = 0; headerIndex < headerCount; headerIndex ++) {
        NSString *part = [headers objectAtIndex:headerIndex];
        if ([part isEqualToString:@"base64"]) {
            isBase64 = YES;
            continue;
        } else if(headerIndex == 0 && ![part containsString:@"="] && [part containsString:@"/"]) {
            header = [OWContentType contentTypeForString:part];
        } else {
            NSRange equals = [part rangeOfString:@"="];
            NSString *parameter, *value;
            if (equals.length == 0) {
                [NSException raise:@"MalformedURL" reason:NSLocalizedStringFromTableInBundle(@"data: URL parameter has no value", @"OWF", [OWDataURLProcessor bundle], @"data: url error")];
            }
            parameter = [part substringToIndex:equals.location];
            value = [NSString decodeURLString:[part substringFromIndex:NSMaxRange(equals)]];
            if (!fullHeader)
                fullHeader = [[[OWParameterizedContentType alloc] initWithContentType:header] autorelease];
            [fullHeader setObject:value forKey:parameter];
        }
    }
    
    part = [dataString substringFromIndex:NSMaxRange(comma)];
    if (isBase64) {
        body = [NSData dataWithBase64String:part];
    } else {
        body = decodeURLEscapedBytes(part);
    }
    
    content = [[OWDataStream alloc] initWithLength:[body length]];
    [content writeData:body];
    [content dataEnd];

    nContent = [OWContent contentWithDataStream:content isSource:YES];
    [content release];
    if (fullHeader)
        [nContent setFullContentType:fullHeader];
    else
        [nContent setContentType:header];
    [nContent markEndOfHeaders];
    
    [pipeline addContent:nContent
           fromProcessor:self
                   flags:OWProcessorContentNoDiskCache|OWProcessorContentIsSource|OWProcessorTypeDerived];
#endif
}
    
@end

