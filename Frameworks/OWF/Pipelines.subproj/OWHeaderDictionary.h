// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFHTTPHeaderDictionary.h>

@class NSArray, NSCharacterSet, NSLock, NSMutableArray;
@class OFDataCursor, OFMultiValueDictionary;
@class ONSocketStream;
@class OWContentType, OWParameterizedContentType, OWDataStreamCursor, OWDataStreamScanner;

@interface OWHeaderDictionary : OFHTTPHeaderDictionary
{
    NSLock *parameterizedContentTypeLock;
    OWParameterizedContentType *parameterizedContentType;
}

- (void)parseRFC822Header:(NSString *)aHeader;
- (void)readRFC822HeadersFromDataCursor:(OFDataCursor *)aCursor;
- (void)readRFC822HeadersFromCursor:(OWDataStreamCursor *)aCursor;
- (void)readRFC822HeadersFromScanner:(OWDataStreamScanner *)aScanner;
- (void)readRFC822HeadersFromSocketStream:(ONSocketStream *)aSocketStream;

- (OWParameterizedContentType *)parameterizedContentType;
- (OWContentType *)contentEncoding;

@end

@interface OWHeaderDictionary (Debugging)
+ (void)setDebug:(BOOL)debugMode;
@end
