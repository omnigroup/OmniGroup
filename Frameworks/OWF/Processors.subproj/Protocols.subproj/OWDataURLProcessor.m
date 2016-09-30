// Copyright 2000-2016 Omni Development, Inc. All rights reserved.
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

static NSData *decodeURLEscapedBytes(NSString *input)
{
    NSUInteger charCount = [input length];
    
    unichar *characters = (unichar *)malloc(charCount * sizeof(*characters));
    [input getCharacters:characters];
    
    unsigned char *bytes = malloc(charCount);
    NSUInteger byteCount = 0;
    NSUInteger charIndex = 0;
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
    
    free(characters);
    NSData *result = [NSData dataWithBytes:bytes length:byteCount];
    free(bytes);
    
    return result;
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
    NSString *dataString = [[sourceAddress url] schemeSpecificPart];
    NSRange comma = [dataString rangeOfString:@","];
    
    if (comma.length < 1) {
        [NSException raise:@"MalformedURL" reason:NSLocalizedStringFromTableInBundle(@"data: URL does not contain comma", @"OWF", [OWDataURLProcessor bundle], @"data: url error")];
    }
    
    OWContentType *header = [OWContentType contentTypeForString:@"text/plain"];

    NSString *headersString = [dataString substringToIndex:comma.location];
    NSArray *headers;
    NSUInteger headerIndex, headerCount;

    if ([headersString length] > 0) {
        headers = [headersString componentsSeparatedByString:@";"];
        headerCount = [headers count];
    } else {
        headers = nil;
        headerCount = 0;
    }
            
    OWParameterizedContentType *fullHeader = nil;
    BOOL isBase64 = NO;
    for (headerIndex = 0; headerIndex < headerCount; headerIndex ++) {
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
                fullHeader = [[OWParameterizedContentType alloc] initWithContentType:header];
            [fullHeader setObject:value forKey:parameter];
        }
    }
    
    NSString *part = [dataString substringFromIndex:NSMaxRange(comma)];
    NSData *body;
    if (isBase64) {
        body = [[NSData alloc] initWithBase64EncodedString:part options:NSDataBase64DecodingIgnoreUnknownCharacters];
    } else {
        body = decodeURLEscapedBytes(part);
    }
    
    OWDataStream *content = [[OWDataStream alloc] initWithLength:[body length]];
    [content writeData:body];
    [content dataEnd];

    OWContent *nContent = [OWContent contentWithDataStream:content isSource:YES];
    if (fullHeader)
        [nContent setFullContentType:fullHeader];
    else
        [nContent setContentType:header];
    [nContent markEndOfHeaders];
    
    [self.pipeline addContent:nContent fromProcessor:self flags:OWProcessorContentNoDiskCache|OWProcessorContentIsSource|OWProcessorTypeDerived];
}
    
@end

