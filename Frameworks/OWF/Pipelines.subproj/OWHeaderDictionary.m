// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWHeaderDictionary.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContentType.h>
#import <OWF/OWDataStreamCharacterCursor.h>
#import <OWF/OWParameterizedContentType.h>
#import <OWF/OWUnknownDataStreamProcessor.h>

RCS_ID("$Id$")

@implementation OWHeaderDictionary

static BOOL debugHeaderDictionary = NO;

+ (void)setDebug:(BOOL)debugMode;
{
    debugHeaderDictionary = debugMode;
}

- init;
{
    if (!(self = [super init]))
	return nil;

    parameterizedContentTypeLock = [[NSLock alloc] init];
    parameterizedContentType = nil;

    return self;
}

- (void)addString:(NSString *)aString forKey:(NSString *)aKey;
{
    if (parameterizedContentType && [aKey compare:OFHTTPContentTypeHeaderKey options: NSCaseInsensitiveSearch] == NSOrderedSame) {
        [parameterizedContentTypeLock lock];
        parameterizedContentType = nil;
        [parameterizedContentTypeLock unlock];
    }
    [super addString:aString forKey:aKey];
}

- (void)parseRFC822Header:(NSString *)aHeader;
{
    NSRange colonRange;
    NSString *key, *value;

    // Use rangeOfString: rather than having a 8k character set to hold a single character
    colonRange = [aHeader rangeOfString: @":"];
    if (colonRange.length == 0)
	return;

    key = [aHeader substringToIndex:colonRange.location];
    value = [[aHeader substringFromIndex:NSMaxRange(colonRange)] stringByRemovingSurroundingWhitespace];
    [self addString:value forKey:key];
}

- (void)readRFC822HeadersFrom:(id)readLineSource;
{
    NSString *header = nil;

    do {
	NSString *newLine;

	newLine = [readLineSource readLine];
        if ([newLine isEqualToString:@"."])
            break;
	if (debugHeaderDictionary)
	    NSLog(@"%@", newLine);
	if ([newLine hasLeadingWhitespace])
	    header = [header stringByAppendingString:newLine];
	else {
	    if (header)
		[self parseRFC822Header:header];
	    header = newLine;
	}
    } while (header && [header length] > 0);	
}

- (void)readRFC822HeadersFromDataCursor:(OFDataCursor *)aCursor;
{
    [self readRFC822HeadersFrom:aCursor];
}

- (void)readRFC822HeadersFromCursor:(OWDataStreamCursor *)aCursor;
{
    OWDataStreamCharacterCursor *characterCursor = [[OWDataStreamCharacterCursor alloc] initForDataCursor:aCursor encoding:kCFStringEncodingISOLatin1];
    [self readRFC822HeadersFrom:characterCursor];
    [characterCursor discardReadahead];
}

- (void)readRFC822HeadersFromScanner:(OWDataStreamScanner *)aScanner;
{
    [self readRFC822HeadersFrom: aScanner];
}

- (void)readRFC822HeadersFromSocketStream:(ONSocketStream *)aSocketStream;
{
    [self readRFC822HeadersFrom:aSocketStream];
}

- (OWParameterizedContentType *)parameterizedContentType;
{
    OWParameterizedContentType *returnValue;
    
    [parameterizedContentTypeLock lock];
    if (parameterizedContentType == nil)
        [self _locked_parseParameterizedContentType];
    returnValue = parameterizedContentType;
    [parameterizedContentTypeLock unlock];
    return returnValue;
}

- (OWContentType *)contentEncoding;
{
    NSString *headerString = [self lastStringForKey:@"content-encoding"];
    if (headerString == nil || [headerString isEqualToString:@""])
	return nil;
    OWContentType *contentEncoding = [OWContentType contentTypeForString:[@"encoding/" stringByAppendingString:headerString]];
    return contentEncoding;
}


#pragma mark - Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
        
    if (parameterizedContentType)
        [dict setObject:parameterizedContentType forKey:@"parameterizedContentType"];
    
    return dict;
}

#pragma mark - Private

- (void)_locked_parseParameterizedContentType;
{
    if (parameterizedContentType != nil)
        return;

    parameterizedContentType = [OWParameterizedContentType contentTypeForString:[self lastStringForKey:OFHTTPContentTypeHeaderKey]];
    if (parameterizedContentType == nil)
        parameterizedContentType = [[OWParameterizedContentType alloc] initWithContentType:[OWContentType unknownContentType]];
}

@end
