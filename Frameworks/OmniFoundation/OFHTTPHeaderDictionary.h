// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class OFMultiValueDictionary;

extern NSString * const OFHTTPContentDispositionHeaderKey;
extern NSString * const OFHTTPContentTypeHeaderKey;

@protocol OFHTTPHeaderDictionaryReadLineSource
- (NSString *)readLine;
@end

@interface OFHTTPHeaderDictionary : OFObject

// Parses a parameterized header such as Content-Type or Refresh.  Returns the simple value, and places parameters into the dictionary.  On error returns what it has so far (doesn't raise an exception).  okSet is the set of characters which can occur in an unquoted value.
+ (NSString *)parseParameterizedHeader:(NSString *)aHeader intoDictionary:(OFMultiValueDictionary *)parameters valueChars:(NSCharacterSet *)okSet;

- (NSArray <NSString *> *)stringArrayForKey:(NSString *)aKey;
- (NSString *)firstStringForKey:(NSString *)aKey;
- (NSString *)lastStringForKey:(NSString *)aKey;
- (OFMultiValueDictionary *)dictionarySnapshot;
- (NSEnumerator *)keyEnumerator;

- (void)addString:(NSString *)aString forKey:(NSString *)aKey;
- (void)addStringsFromDictionary:(OFMultiValueDictionary *)source;


- (NSString *)contentDispositionFilename;

- (NSArray *)formatRFC822HeaderLines;
- (void)readRFC822HeadersFromReadLineSource:(id <OFHTTPHeaderDictionaryReadLineSource>)readLineSource;
- (void)readRFC822HeadersFromString:(NSString *)string;

// Takes the contents of an OFMultiValueDictionary and produces a string which could be parsed by +parseParameterizedHeader:::. (Doesn't include the simple value, of course.)
+ (NSString *)formatHeaderParameter:(NSString *)name value:(NSString *)value;
+ (NSString *)formatHeaderParameters:(OFMultiValueDictionary *)parameters onlyLastValue:(BOOL)onlyLast;

// Divides a set of headers into their component values, as described in the last paragraph of RFC2616[4.2].
// Returns a new, autoreleased, mutable array for convenience.
+ (NSMutableArray *)splitHeaderValues:(NSArray *)headers;

@end
