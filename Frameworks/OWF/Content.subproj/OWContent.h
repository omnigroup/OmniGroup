// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAbstractContent.h>

@class NSData, NSLock, NSConditionLock, NSMutableArray;
@class OFMultiValueDictionary;
@class OWAddress, OWContentInfo, OWContentType, OWParameterizedContentType;
@class OWDataStream, OWDataStreamCursor, OWObjectStreamCursor;
@class OWCacheControlSettings;

#import <OWF/OWDataStream.h>
#import <os/lock.h>

@interface OWContent : OFObject
{
    OWContentInfo *contentInfo;

    os_unfair_lock lock;
    NSConditionLock *metadataCompleteCondition;
    
    id <OWConcreteCacheEntry> concreteContent;
    
    // Caches which contain this content, and the handles they've provided us.
    NSMutableDictionary *containingCaches;

    OFMultiValueDictionary *metaData;
    NSUInteger metadataHash;  // 0 if not computed (incl. if !metadataComplete)
    NSUInteger contentHash;   // 0 if not computed (incl. if content is not complete)
    BOOL metadataComplete;
    unsigned char dataComplete;
    unsigned char hasValidator; // 0, 1, or '?' if not computed
    unsigned char smallConcreteType;
    
    OWParameterizedContentType *cachedContentType;
    NSArray *cachedContentEncodings;
}

// API --- convenient methods for creating an OWContent
+ (id)contentWithAddress:(OWAddress *)anAddress;  // calls -markEndOfHeaders
+ (id)contentWithAddress:(OWAddress *)newAddress redirectionFlags:(unsigned)flags interimContent:(OWContent *)interim;   // calls -markEndOfHeaders
+ (id)contentWithDataStream:(OWDataStream *)dataStream isSource:(BOOL)contentIsSource;  // NB: this one does NOT call -markEndOfHeaders
+ (id)contentWithData:(NSData *)someData headers:(OFMultiValueDictionary *)someMetadata;   // calls -markEndOfHeaders
+ (id)contentWithString:(NSString *)someText contentType:(NSString *)fullContentType isSource:(BOOL)contentIsSource;   // calls -markEndOfHeaders
+ (id)contentWithConcreteCacheEntry:(id <OWConcreteCacheEntry>)aCacheEntry;
+ (id)unknownContentFromContent:(OWContent *)mistypedContent;

// Initializers.
- (id)initWithContent:(id <OWConcreteCacheEntry>)someContent;
- (id)initWithContent:(id <OWConcreteCacheEntry>)someContent type:(NSString *)contentTypeString;
- (id)initWithName:(NSString *)typeString content:(id <OWConcreteCacheEntry>)someContent;  // D.I.

- (OWContentInfo *)contentInfo;

// Delayed availability. If the content isn't immediately available (e.g. if a filter bundle needs to be loaded, or the disk cache needs to be consulted, or a main-thread-only operation needs to happen) then this will return NO. Accessors will block; this method is provided for when a caller wants to avoid blocking or wants to control exactly when they block. (Note that a data stream may be "available" immediately even if none of its data has arrived --- for that, check the endOfData method.)
// If the content isn't available and will never be available (e.g. an unsupported encoding), -checkForAvailability:NO will return NO and -checkForAvailability:YES will raise an exception.
- (BOOL)checkForAvailability:(BOOL)loadNow;

// Data accessors. These will raise an exception if the receiver does not contain the appropriate type of data.
- (OWAddress *)address;
- (OWDataStreamCursor *)dataCursor;
- (OWObjectStreamCursor *)objectCursor;
- (id)objectValue;

- (NSUInteger)contentHash;  // This returns a hash that depends on the content, but not on any metadata
  // NB: -contentHash can currently raise if the data has been invalidated, e.g. by a processor abort

- (BOOL)isAddress;      // Returns YES if this content is an OWAddress.
- (BOOL)isDataStream;   // Returns YES if this content can provide a dataCursor.
- (BOOL)isException;    // Returns YES if this content is an error object.
- (BOOL)endOfData;      // Returns NO if this content is being incrementally generated.
- (BOOL)isHashable;     // Returns YES if this content is immutable (that is, is no longer being generated) and can produce a hash value. (An aborted data stream may return YES from endOfData but NO from isHashable; other than that, they generally produce the same result.)
- (BOOL)contentIsValid; // Returns YES if this content can be used
- (BOOL)isStorable;     // Returns YES if this content can be stored in a persistent cache (i.e., if we haven't seen a Cache-Control: no-store)

// Note that -endOfData only checks the concrete content; -isHashable also tests the metadata. A content should  be considered hashable if & only if isHashable returns YES. Otherwise, the hash and equality attributes may change as the content continues to be created.

// Metadata.

// Metadata mutators. The creator of the OWContent must call -markEndOfHeaders to indicate that no (more) headers will be added.
- (void)addHeader:(NSString *)headerName value:(id)headerValue;
- (void)addHeader:(NSString *)headerName values:(NSArray *)headerValues;
- (void)addHeaders:(OFMultiValueDictionary *)headers;
- (void)addHeadersFromPropertyList:(id)plist;
- (void)removeHeader:(NSString *)headerName;
- (void)markEndOfHeaders;

// Conveniences for above
- (void)setContentType:(OWContentType *)aType;
- (void)setFullContentType:(OWParameterizedContentType *)aType;
- (void)setContentTypeString:(NSString *)aString;
#define OWContentTypeHeaderString (@"Content-Type")
#define OWContentEncodingHeaderString (@"Content-Encoding")
#define OWContentDispositionHeaderString (@"Content-Disposition")
#define OWEntityTagHeaderString (@"ETag")
#define OWEntityLastModifiedHeaderString (@"last-modified")
- (void)setCharsetProvenance:(enum OWStringEncodingProvenance)provenance; 

// Metadata accessors
- (BOOL)endOfHeaders;
- (void)waitForEndOfHeaders;
- (OFMultiValueDictionary *)headers;
- (id)headersAsPropertyList;

- lastObjectForKey:(NSString *)headerKey;  // Equivalent to, but much faster than, [[foo headers] lastObjectForKey:headerKey]

- (OWCacheControlSettings *)cacheControlSettings;

// These parse the MIME type from the Content-Type header, or ask the content for its type
- (OWContentType *)contentType;
- (OWParameterizedContentType *)fullContentType;
- (NSArray *)contentEncodings;  // an array of OWContentTypes, each representing a content-encoding as RFC2616[14.11]
- (NSDictionary *)suggestedFileAttributesWithAddress:(OWAddress *)originAddress;
#define OWContentFileAttributeNameKey (@"filename")  // filename key in the above-returned dictionary

- (BOOL)isSource;
- (BOOL)hasValidator;

// These are used to maintain the containingCaches dictionary
- (void)useHandle:(id)anObject forCache:(id <OWCacheContentProvider>)aCache;
- (id)handleForCache:(id <OWCacheContentProvider>)aCache;

// This will efficiently copy the receiver with reopened metadata.
- (OWContent *)copyWithMutableHeaders;

@end

// Currently unused:
//extern  NSString * const OWContentHasNewMetadataNotificationName;

