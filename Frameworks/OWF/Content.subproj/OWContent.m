// Copyright 2003-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWContent.h>

#import <Foundation/Foundation.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>

#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/OFUtilities.h>

#import <OWF/OWAddress.h>
#import <OWF/OWCacheControlSettings.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWContentType.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWDataStreamCursor.h>
#import <OWF/OWDataStreamCharacterProcessor.h>
#import <OWF/OWHeaderDictionary.h>
#import <OWF/OWObjectStream.h>
#import <OWF/OWParameterizedContentType.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWProcessor.h>
#import <OWF/NSDate-OWExtensions.h>

RCS_ID("$Id$");

@interface OWContent (Private)
- _invalidContentType:(SEL)accessor;
- (void)_locked_fillContent;
- (void)_shareHandles:(NSMutableDictionary *)otherContentHandles;
- (BOOL)_locked_addHeader:(NSString *)headerName values:(NSArray *)several value:(id)one;
@end

// Possible values of smallConcreteType
enum {
    ConcreteType_Unknown,
    ConcreteType_Address,
    ConcreteType_DataStream,
    ConcreteType_ObjectStream,
    ConcreteType_Exception,
    ConcreteType_Other,
    ConcreteType_SwappedOut
};

// Possible values of dataComplete
enum {
    Data_NotComplete = 0,
    Data_EndedMaybeInvalid,
    Data_EndedAndValid,
    Data_Invalid
};

@implementation OWContent

// API --- convenient methods for creating an OWContent
+ (id)contentWithAddress:(OWAddress *)anAddress;
{
    OWContent *result;

    result = [[OWContent alloc] initWithName:@"Address" content:anAddress];
    [result markEndOfHeaders];

    return result;
}

+ (id)contentWithAddress:(OWAddress *)newAddress redirectionFlags:(unsigned)flags interimContent:(OWContent *)interim;
{
    OWContent *result = [[OWContent alloc] initWithName:@"Redirect" content:newAddress];
    if (flags != 0)
        [result addHeader:OWContentRedirectionTypeMetadataKey value:[NSNumber numberWithUnsignedInt:flags]];
    if (interim != nil)
        [result addHeader:OWContentInterimContentMetadataKey value:[NSNumber numberWithUnsignedInt:flags]];
    [result markEndOfHeaders];
    return result;
}

+ (id)contentWithDataStream:(OWDataStream *)dataStream isSource:(BOOL)sourcey
{
    OWContent *result = [[OWContent alloc] initWithName:@"DataStream" content:dataStream];
    if (sourcey)
        [result addHeader:OWContentIsSourceMetadataKey value:[NSNumber numberWithBool:YES]];
    return result;
}

+ (id)contentWithData:(NSData *)someData headers:(OFMultiValueDictionary *)someMetadata;
{
    OWDataStream *dataStream = nil;

    if (someData != nil) {
        dataStream = [[OWDataStream alloc] initWithLength:[someData length]];
        [dataStream writeData:someData];
        [dataStream dataEnd];
    }

    OWContent *result = [self contentWithDataStream:dataStream isSource:NO];

    dataStream = nil;
    
    if (someMetadata)
        [result addHeaders:someMetadata];

    [result markEndOfHeaders];

    return result;
}

+ (id)contentWithString:(NSString *)someText contentType:(NSString *)fullContentType isSource:(BOOL)contentIsSource;   // calls -markEndOfHeaders
{
    OWParameterizedContentType *parameterizedContentType;
    CFStringEncoding encoding;
    NSStringEncoding nsEncoding;
    NSData *bytes;
    OWDataStream *dataStream;
    OWContent *content;

    parameterizedContentType = [OWParameterizedContentType contentTypeForString:fullContentType];
    OBASSERT(parameterizedContentType != nil); // Or you shouldn't use this method!
    encoding = [OWDataStreamCharacterProcessor stringEncodingForContentType:parameterizedContentType];
    if (encoding == kCFStringEncodingInvalidId) {
        if ([someText canBeConvertedToEncoding:NSASCIIStringEncoding]) {
            nsEncoding = NSASCIIStringEncoding;
        } else {
            nsEncoding = [someText smallestEncoding];
            encoding = CFStringConvertNSStringEncodingToEncoding(nsEncoding);
            [parameterizedContentType setObject:[OWDataStreamCharacterProcessor charsetForCFEncoding:encoding] forKey:@"charset"];
            fullContentType = [parameterizedContentType contentTypeString];
        }
    } else
        nsEncoding = CFStringConvertEncodingToNSStringEncoding(encoding);

    bytes = [someText dataUsingEncoding:nsEncoding allowLossyConversion:YES];
    dataStream = [[OWDataStream alloc] initWithLength:[bytes length]];
    [dataStream writeData:bytes];
    [dataStream dataEnd];

    content = [[self alloc] initWithContent:dataStream];

    [content addHeader:OWContentTypeHeaderString value:fullContentType];
    [content addHeader:OWContentIsSourceMetadataKey value:[NSNumber numberWithBool:contentIsSource]];
    [content markEndOfHeaders];

    OBPOSTCONDITION([content isHashable]);

    return content;
}

+ (id)contentWithConcreteCacheEntry:(id <OWConcreteCacheEntry>)aCacheEntry;
{
    OWContent *someContent = [[OWContent alloc] initWithContent:aCacheEntry];
    [someContent markEndOfHeaders];
    return someContent;
}

+ (id)unknownContentFromContent:(OWContent *)mistypedContent;
{
    OWContent *unknownContent = [mistypedContent copyWithMutableHeaders];
    [unknownContent removeHeader:OWContentTypeHeaderString];
    [unknownContent removeHeader:OWContentIsSourceMetadataKey];
    [unknownContent setContentType:[OWContentType unknownContentType]];
    [unknownContent markEndOfHeaders];
    return unknownContent;
}

- (id)initWithContent:(id <OWConcreteCacheEntry>)someContent;
{
    return [self initWithName:nil content:someContent];
}

- (id)initWithContent:(id <OWConcreteCacheEntry>)someContent type:(NSString *)contentTypeString;
{
    if (!(self = [self initWithName:nil content:someContent]))
        return nil;

    [self setContentTypeString:contentTypeString];

    return self;
}

- (id)initWithName:(NSString *)typeString content:(id <OWConcreteCacheEntry>)someContent;  // D.I.
{
    OBPRECONDITION(someContent != nil);

    if (!(self = [super init]))
        return nil;

    if (someContent != nil) {
        // someContent should never be nil, but it possibly is if we're using copyWithReplacementHeader: and the original object's content is swapped out.
        OBASSERT([someContent conformsToProtocol:@protocol(OWConcreteCacheEntry)]);
    }

    if (someContent == nil || ![someContent isKindOfClass:[OWAddress class]])
        contentInfo = [[OWContentInfo alloc] initWithContent:self typeString:typeString];
    else
        contentInfo = nil;  // For some reason, addresses don't deserve contentinfos
    lock = OS_UNFAIR_LOCK_INIT;
    metadataCompleteCondition = nil;
    metaData = [[OFMultiValueDictionary alloc] initWithCaseInsensitiveKeys:YES];
    metadataHash = 0;
    contentHash = 0;
    hasValidator = '?';
    concreteContent = someContent;
    cachedContentType = nil;
    cachedContentEncodings = nil;
    containingCaches = (NSMutableDictionary *) CFBridgingRelease(CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &OFNSObjectDictionaryValueCallbacks));

    if ([concreteContent isKindOfClass:[OWAddress class]])
        smallConcreteType = ConcreteType_Address;
    else if ([concreteContent isKindOfClass:[OWDataStream class]])
        smallConcreteType = ConcreteType_DataStream;
    else if ([concreteContent isKindOfClass:[OWAbstractObjectStream class]])
        smallConcreteType = ConcreteType_ObjectStream;
    else if ([concreteContent isKindOfClass:[NSException class]])
        smallConcreteType = ConcreteType_Exception;
    else if (concreteContent != nil)
        smallConcreteType = ConcreteType_Other;
    else
        smallConcreteType = ConcreteType_Unknown;

    return self;
}

- initWithName:(NSString *)aName
{
    return [self initWithName:aName content:nil];
}

#ifdef DEBUG_OWnContent_REFS
static void Thingy(id mememe, SEL wheee);

- retain
{
    Thingy(self, _cmd);
    return [super retain];
}

- (void)release
{
    Thingy(self, _cmd);
    [super release];
}

- autorelease
{
    Thingy(self, _cmd);
    return [super autorelease];
}

static void Thingy(id mememe, SEL wheee)
{
    // breakpoint
    // fprintf(stderr, "<%s %p> %s, rc=%d\n", mememe->isa->name, mememe, wheee, [mememe retainCount]);
}
#endif

- (void)dealloc
{
    NSEnumerator *cacheEnumerator;
    id <OWCacheContentProvider> aCache;
    
    [contentInfo nullifyContent];
    contentInfo = nil;

    cacheEnumerator = [containingCaches keyEnumerator];
    while( (aCache = [cacheEnumerator nextObject]) != nil ) {
        [aCache adjustHandle:[containingCaches objectForKey:aCache] reference:-1];
    }
    containingCaches = nil;
}

- (OWContentInfo *)contentInfo;
{
    return contentInfo;
}

- (BOOL)checkForAvailability:(BOOL)loadNow
{
    NSArray *codings;
    NSUInteger codingIndex, codingCount;

    // Check whether we have any content-encodings whose filters aren't loaded
    codings = [self contentEncodings];
    if (codings && (codingCount = [codings count])) {
        for(codingIndex = 0; codingIndex < codingCount; codingIndex ++) {
            OWContentType *coding = [codings objectAtIndex:codingIndex];
            BOOL coderLoaded;

            coderLoaded = [OWDataStreamCursor availableEncoding:coding apply:NO remove:YES tryLoad:loadNow];
            
            if (!coderLoaded && !loadNow)
                return NO;
            if (!coderLoaded && loadNow)
                [NSException raise:OWDataStreamCursor_UnknownEncodingException format:@"Unknown or unsupported content encoding: \"%@\"", [coding readableString]];
        }
    }

    // right now the only kind of non-availability we have is unloaded content-encoding filters.
    return YES;
}

- (OWContentType *)contentType;
{
    OWContentType *contentType;

    // Note that the concreteContent's content type overrides any content type derived from the metadata; this is necessary for things like error responses and HEAD responses.

    if (concreteContent && [concreteContent respondsToSelector:@selector(contentType)])
        contentType = [(OWContent *)concreteContent contentType];
    else
        contentType = [[self fullContentType] contentType];
    if (contentType == nil)
        contentType = [OWContentType unknownContentType];

    OBPOSTCONDITION(contentType != nil);
    return contentType;
}

- (OWParameterizedContentType *)fullContentType;
{
    if (concreteContent && [concreteContent respondsToSelector:@selector(fullContentType)])
        return [(id)concreteContent fullContentType];

    os_unfair_lock_lock(&lock);

    if (cachedContentType != nil) {
        OWParameterizedContentType *parameterizedContentType = cachedContentType;
        os_unfair_lock_unlock(&lock);
        return parameterizedContentType;
    }

    NSString *ctString = [metaData lastObjectForKey:OWContentTypeHeaderString];
    BOOL maybeStash = metadataComplete;
    
    os_unfair_lock_unlock(&lock);

    OWParameterizedContentType *parameterizedContentType = [OWParameterizedContentType contentTypeForString:ctString];
    if (parameterizedContentType == nil)
        parameterizedContentType = [[OWParameterizedContentType alloc] initWithContentType:[OWContentType unknownContentType]];

    if (maybeStash) {
        os_unfair_lock_lock(&lock);
        // Someone else may have come along and cached a content-type and/or modified the metadata
        if (cachedContentType == nil &&
            [ctString isEqual:[metaData lastObjectForKey:OWContentTypeHeaderString]]) {
            cachedContentType = parameterizedContentType;
        }
        os_unfair_lock_unlock(&lock);
    }

    OBPOSTCONDITION(parameterizedContentType != nil);
    return parameterizedContentType;
}

- (NSArray *)contentEncodings
{
    NSArray *codingHeaders, *codingHeadersCopy;
    NSMutableArray *codingTokens, *codings;
    BOOL shouldCache;

    os_unfair_lock_lock(&lock);

    if (metadataComplete && cachedContentEncodings != nil) {
        os_unfair_lock_unlock(&lock);
        return cachedContentEncodings;
    }
    shouldCache = metadataComplete;
    
    codingHeaders = [metaData arrayForKey:OWContentEncodingHeaderString];
    if (codingHeaders != nil && [codingHeaders count] > 0)
        codingHeadersCopy = [[NSArray alloc] initWithArray:codingHeaders];
    else
        codingHeadersCopy = nil;
    
    os_unfair_lock_unlock(&lock);
    
    if (codingHeadersCopy == nil)
        return nil;

    codingTokens = [OWHeaderDictionary splitHeaderValues:codingHeadersCopy];

    codings = [[NSMutableArray alloc] initWithCapacity:[codingTokens count]];
    while ([codingTokens count]) {
        NSString *codingName = [OWHeaderDictionary parseParameterizedHeader:[codingTokens lastObject] intoDictionary:nil valueChars:nil];
        OWContentType *encoding = [OWContentType contentEncodingForString:codingName];
        if (encoding != nil && encoding != [OWContentType contentEncodingForString:@"identity"])
            [codings insertObject:encoding atIndex:0];
        [codingTokens removeLastObject];
    }

    if (shouldCache) {
        os_unfair_lock_lock(&lock);
        if (cachedContentEncodings == nil)
            cachedContentEncodings = [[NSArray alloc] initWithArray:codings];
        os_unfair_lock_unlock(&lock);
    }

    return codings;
}

- (BOOL)isAddress
{
    if (smallConcreteType == ConcreteType_Address)
        return YES;
    else
        return NO;
}

- (OWAddress *)address
{
    if (smallConcreteType == ConcreteType_Address)
        return (OWAddress *)concreteContent;
    else
        return [self _invalidContentType:_cmd];
}

- (BOOL)isDataStream
{
    if (smallConcreteType == ConcreteType_DataStream)
        return YES;
    else
        return NO;
}

- (OWDataStreamCursor *)dataCursor
{
    OWDataStreamCursor *cursor;
    NSArray *encodings;
    NSUInteger encodingIndex, encodingCount;
    
    if (smallConcreteType != ConcreteType_DataStream)
        return [self _invalidContentType:_cmd];

    os_unfair_lock_lock(&lock);
    OWDataStream *thisDataStream = (OWDataStream *)concreteContent;
    os_unfair_lock_unlock(&lock);
    NS_DURING {
        cursor = [thisDataStream createCursor];
        if ([thisDataStream endOfData]) {
            BOOL contentIsValid = [thisDataStream contentIsValid];
            os_unfair_lock_lock(&lock);
            if (contentIsValid)
                dataComplete = Data_EndedAndValid;
            else
                dataComplete = Data_Invalid;
            os_unfair_lock_unlock(&lock);
        }
    } NS_HANDLER {
        if ([[localException name] isEqualToString:OWDataStreamNoLongerValidException]) {
            os_unfair_lock_lock(&lock);
            dataComplete = Data_Invalid;
            os_unfair_lock_unlock(&lock);
        }
        [localException raise];
        cursor = nil; // compiler pacification
    } NS_ENDHANDLER;

    // Add filters to remove any content-encodings which may have been applied, starting at the last (outermost) encoding and working back.
    encodings = [self contentEncodings];
    encodingCount = [encodings count];
    for(encodingIndex = 0; encodingIndex < encodingCount; encodingIndex ++) {
        OWContentType *contentEncoding = [encodings objectAtIndex:(encodingCount - encodingIndex - 1)];
        cursor = [OWDataStreamCursor cursorToRemoveEncoding:contentEncoding fromCursor:cursor];
    }

    return cursor;
}

- (OWObjectStreamCursor *)objectCursor;
{
    if (smallConcreteType == ConcreteType_ObjectStream)
        return [(OWAbstractObjectStream *)concreteContent createCursor];
    else
        return [self _invalidContentType:_cmd];
}

- (id)objectValue
{
    if (smallConcreteType != ConcreteType_Address)
        return concreteContent;
    else
        return [self _invalidContentType:_cmd];
}

- (BOOL)isException;
{
    if (smallConcreteType == ConcreteType_Exception)
        return YES;
    else
        return NO;
}

- (BOOL)endOfData
{
    unsigned char dataStatus;
    BOOL dataEnded;

    os_unfair_lock_lock(&lock);
    dataStatus = dataComplete;
    os_unfair_lock_unlock(&lock);

    if (dataStatus == Data_NotComplete) {

        dataEnded = [concreteContent endOfData];

        if (dataEnded) {
            os_unfair_lock_lock(&lock);
            if (dataComplete == Data_NotComplete)
                dataComplete = Data_EndedMaybeInvalid;
            dataStatus = dataComplete;
            os_unfair_lock_unlock(&lock);
        }
    }

    return (dataStatus != Data_NotComplete);
}

- (BOOL)isHashable
{
    unsigned char dataCompleteCopy;
    
    os_unfair_lock_lock(&lock);
    if (!metadataComplete) {
        os_unfair_lock_unlock(&lock);
        return NO;
    }
    dataCompleteCopy = dataComplete;
    os_unfair_lock_unlock(&lock);
    switch (dataCompleteCopy) {
        case Data_EndedAndValid:
            return YES;
        default:
        case Data_Invalid:
            return NO;
        case Data_NotComplete:
            if (![concreteContent endOfData])
                return NO;
            // FALLTHROUGH
        case Data_EndedMaybeInvalid:
            @try {
                [self contentHash];
            } @catch (NSException *exc) {
                OB_UNUSED_VALUE(exc);
                os_unfair_lock_lock(&lock);
                dataComplete = Data_Invalid;
                os_unfair_lock_unlock(&lock);
                return NO;
            }
            os_unfair_lock_lock(&lock);
            dataComplete = Data_EndedAndValid;
            os_unfair_lock_unlock(&lock);
            return YES;
    }
}

- (BOOL)contentIsValid;
{
    return [concreteContent contentIsValid];
}

- (BOOL)isStorable;
{
    OWCacheControlSettings *cacheControlSettings = [self cacheControlSettings];
    return cacheControlSettings->noStore == NO;
}

- (BOOL)isSource;
{
    id isSourceHeader = [self lastObjectForKey:OWContentIsSourceMetadataKey];

    return isSourceHeader? [isSourceHeader boolValue] : NO;
}

- (BOOL)hasValidator
{
    if (hasValidator == '?') {
        NSString *validator;
        BOOL validatorSeen = NO;

        os_unfair_lock_lock(&lock);

        validator = [metaData lastObjectForKey:OWEntityTagHeaderString];
        if (validator && [validator isKindOfClass:[NSString class]] && ![NSString isEmptyString:validator])
            validatorSeen = YES;
        if (!validatorSeen) {
            validator = [metaData lastObjectForKey:OWEntityLastModifiedHeaderString];
            if (validator && [validator isKindOfClass:[NSString class]] && ![NSString isEmptyString:validator])
                validatorSeen = YES;
        }

        if (metadataComplete)
            hasValidator = validatorSeen;

        os_unfair_lock_unlock(&lock);
        
        return validatorSeen;
    }

    if (hasValidator == 1)
        return YES;
    else
        return NO;
}

- (void)addHeader:(NSString *)headerName value:(id)headerValue;
{
    NSNotification *note;

    note = nil;

    OBASSERT(!metadataComplete);
    OBASSERT(headerValue != nil);

    os_unfair_lock_lock(&lock);
    [self _locked_addHeader:headerName values:nil value:headerValue];
/*
    if ([self _locked_addHeader:headerName values:nil value:headerValue])
        note = [NSNotification notificationWithName:OWContentHasNewMetadataNotificationName object:self];
*/
    os_unfair_lock_unlock(&lock);
/*
    if (note)
        [OWPipeline lockAndPostNotification:note];
*/        
}

- (void)addHeader:(NSString *)headerName values:(NSArray *)values
{
    NSNotification *note;

    note = nil;

    OBASSERT(!metadataComplete);

    os_unfair_lock_lock(&lock);

    [self _locked_addHeader:headerName values:values value:nil];
/*
    if ([self _locked_addHeader:headerName values:values value:nil])
        note = [NSNotification notificationWithName:OWContentHasNewMetadataNotificationName object:self];
*/
    os_unfair_lock_unlock(&lock);
/*
    if (note)
        [OWPipeline lockAndPostNotification:note];
*/        
}


- (void)addHeaders:(OFMultiValueDictionary *)headers;
{
    NSNotification *note;
    NSArray *newHeaders;
    NSString *headerName;
    NSUInteger newHeaderIndex, newHeaderCount;
    
    note = nil;

    OBASSERT(!metadataComplete);

    os_unfair_lock_lock(&lock);

    newHeaders = [headers allKeys];
    newHeaderCount = [newHeaders count];
    for(newHeaderIndex = 0; newHeaderIndex < newHeaderCount; newHeaderIndex ++) {
        headerName = [newHeaders objectAtIndex:newHeaderIndex];

        [self _locked_addHeader:headerName values:[headers arrayForKey:headerName] value:nil];
//        BOOL changed = [self _locked_addHeader:headerName values:[headers arrayForKey:headerName] value:nil];
/*        
        if (changed && !note) {
            note = [NSNotification notificationWithName:OWContentHasNewMetadataNotificationName object:self];
        }
*/        
    }

    os_unfair_lock_unlock(&lock);
/*    
    if (note)
        [OWPipeline lockAndPostNotification:note];
*/        
}

- (void)removeHeader:(NSString *)headerName;
{
    NSNotification *note;

    note = nil;

    OBASSERT(!metadataComplete);

    os_unfair_lock_lock(&lock);

    if ([metaData lastObjectForKey:headerName] != nil) {
        [metaData setObjects:nil forKey:headerName];
//        note = [NSNotification notificationWithName:OWContentHasNewMetadataNotificationName object:self];

        if (cachedContentType != nil &&
            [headerName caseInsensitiveCompare:OWContentTypeHeaderString] == NSOrderedSame) {
            cachedContentType = nil;
        }
    }

    os_unfair_lock_unlock(&lock);
/*
    if (note)
        [OWPipeline lockAndPostNotification:note];
*/        
}

- (void)setContentTypeString:(NSString *)aString
{
    [self addHeader:OWContentTypeHeaderString value:aString];
}

- (void)setContentType:(OWContentType *)aType;
{
    [self addHeader:OWContentTypeHeaderString value:[aType contentTypeString]];
}

- (void)setFullContentType:(OWParameterizedContentType *)aType;
{
    [self setContentTypeString:[aType contentTypeString]];

    os_unfair_lock_lock(&lock);

    if (cachedContentType == nil) {
        cachedContentType = aType;
    } else {
        OBASSERT([cachedContentType isEqual:aType]);
    }

    os_unfair_lock_unlock(&lock);
}

- (void)setCharsetProvenance:(enum OWStringEncodingProvenance)provenance;
{
    [self addHeader:OWContentEncodingProvenanceMetadataKey value:[NSNumber numberWithInt:provenance]];
}

- (void)markEndOfHeaders;
{
    os_unfair_lock_lock(&lock);
//    BOOL wasEnded = metadataComplete;
    metadataComplete = YES;
    if (metadataCompleteCondition) {
        [metadataCompleteCondition lock];
        [metadataCompleteCondition unlockWithCondition:metadataComplete];
    }
    os_unfair_lock_unlock(&lock);

/*
    if (!wasEnded) {
        [OWPipeline lockAndPostNotification:[NSNotification notificationWithName:OWContentHasNewMetadataNotificationName object:self]];
    }
*/    
}

- (BOOL)endOfHeaders
{
    BOOL eoh;
    os_unfair_lock_lock(&lock);
    eoh = metadataComplete;
    os_unfair_lock_unlock(&lock);
    return eoh;
}

- (void)waitForEndOfHeaders
{
    os_unfair_lock_lock(&lock);

    if (metadataComplete) {
        os_unfair_lock_unlock(&lock);
        return;
    }

    if (metadataCompleteCondition == nil) {
        metadataCompleteCondition = [[NSConditionLock alloc] initWithCondition:metadataComplete];
    }

    NSConditionLock *waitCondition = metadataCompleteCondition;

    os_unfair_lock_unlock(&lock);

    [waitCondition lockWhenCondition:YES];
    [waitCondition unlock];
    waitCondition = nil;

#ifdef OMNI_ASSERTIONS_ON
    os_unfair_lock_lock(&lock);
    OBASSERT(metadataComplete);
    os_unfair_lock_unlock(&lock);
#endif
}

- (OFMultiValueDictionary *)headers
{
    OFMultiValueDictionary *result;

    os_unfair_lock_lock(&lock);
    if (metadataComplete)
        result = metaData;
    else
        result = [metaData mutableCopy];
    os_unfair_lock_unlock(&lock);

    return result;
}

- lastObjectForKey:(NSString *)headerKey
{
    id result;

    os_unfair_lock_lock(&lock);
    result = [metaData lastObjectForKey:headerKey];
    os_unfair_lock_unlock(&lock);
    return result;
}

- (OWCacheControlSettings *)cacheControlSettings;
{
    return [OWCacheControlSettings cacheSettingsForMultiValueDictionary:[self headers]];
}

- (id)headersAsPropertyList
{
    NSDictionary *result;
    
    os_unfair_lock_lock(&lock);
    if (metadataComplete)
        result = [metaData dictionary];
    else
        result = [metaData dictionary];
    os_unfair_lock_unlock(&lock);

    return result;
}

- (void)addHeadersFromPropertyList:(id)plist
{
    if (plist == nil)
        return;
    
    {OFForEachObject([plist keyEnumerator], NSString *, aKey) {
        [metaData addObjects:[plist objectForKey:aKey] forKey:aKey];
    }}
}

- (NSDictionary *)suggestedFileAttributesWithAddress:(OWAddress *)originAddress;
{
    NSMutableDictionary *fileAttributes = [NSMutableDictionary dictionary];
    BOOL hfsTypesInContentDisposition = NO;

    OWContentType *mimeType = [self contentType];

    OFMultiValueDictionary *contentDispositionParameters = [[OFMultiValueDictionary alloc] init];
    [OWHeaderDictionary parseParameterizedHeader:[self lastObjectForKey:OWContentDispositionHeaderString] intoDictionary:contentDispositionParameters valueChars:nil];
    
    // Extract and sanitize the filename parameter
    NSString *filename = [contentDispositionParameters lastObjectForKey:@"filename"];
    if (filename && ![filename containsString:[NSString stringWithCharacter:0]]) {
        filename = [[filename lastPathComponent] stringByRemovingSurroundingWhitespace];
        if ([filename hasPrefix:@"."] || [filename hasPrefix:@"~"])
            filename = [@"_" stringByAppendingString:[filename substringFromIndex:1]];
        if (![NSString isEmptyString:filename])
            [fileAttributes setObject:filename forKey:OWContentFileAttributeNameKey];
    }
    
    // Nonstandard but widely used Content-Disposition parameters for storing HFS types.
    NSString *value = [contentDispositionParameters lastObjectForKey:@"x-mac-creator"];
    if (value) {
        OSType fourcc = [value hexValue];
        if (fourcc != 0) {
            [fileAttributes setObject:[NSNumber numberWithUnsignedLong:fourcc] forKey:NSFileHFSCreatorCode];
            hfsTypesInContentDisposition = YES;
        }
    }
    value = [contentDispositionParameters lastObjectForKey:@"x-mac-type"];
    if (value) {
        OSType fourcc = [value hexValue];
        if (fourcc != 0) {
            [fileAttributes setObject:[NSNumber numberWithUnsignedLong:fourcc] forKey:NSFileHFSTypeCode];
            hfsTypesInContentDisposition = YES;
        }
    }
    
    // Copy out some timestamps.
    value = [contentDispositionParameters lastObjectForKey:@"creation-date"];
    if (value) {
        NSDate *creationDate = [NSDate dateWithHTTPDateString:value];
        if (creationDate)
            [fileAttributes setObject:creationDate forKey:NSFileCreationDate];
    }

    // If not found in Content-Disposition, copy the HFS types from the Content-Type.
    if (mimeType && !hfsTypesInContentDisposition) {
        OSType macType;

        macType = [mimeType hfsType];
        if (macType != 0)
            [fileAttributes setObject:[NSNumber numberWithUnsignedLong:macType] forKey:NSFileHFSTypeCode];
        macType = [mimeType hfsCreator];
        if (macType != 0)
            [fileAttributes setObject:[NSNumber numberWithUnsignedLong:macType] forKey:NSFileHFSCreatorCode];
    }
    
    // If not found in Content-Disposition, try to cons up a filename from the address.
    if (![fileAttributes objectForKey:OWContentFileAttributeNameKey]) {
        filename = [originAddress suggestedFilename];
        if (![NSString isEmptyString:filename]) {
            filename = [mimeType pathForEncodings:[self contentEncodings] givenOriginalPath:filename];
            if (filename)
                [fileAttributes setObject:filename forKey:OWContentFileAttributeNameKey];
        }
    }

    return fileAttributes;
}

- (BOOL)isEqual:(id)anotherObject;
{
    OWContent *other;
    OFMultiValueDictionary *otherHeaders;
    BOOL handleMatch, locked;

    // NB: The pipeline lock is not necessarily held at this point.

    if (anotherObject == self)
        return YES;

    if (anotherObject == nil || [anotherObject class] != [self class])
        return NO;

    other = anotherObject;

    @try {
        if (![self isHashable] || ![other isHashable])
            return NO;

        if ([self hash] != [other hash])
            return NO;

    } @catch (NSException *exc) {
        OB_UNUSED_VALUE(exc);
        return NO;
    }

    locked = NO;
    @try {

        otherHeaders = [other headers];
    
        os_unfair_lock_lock(&lock);
        locked = YES;
    
        if (![metaData isEqual:otherHeaders]) {
            os_unfair_lock_unlock(&lock);
            return NO;
        }
    
        NSArray *cacheKeys = [containingCaches allKeys];
    
        locked = NO;
        os_unfair_lock_unlock(&lock);
    
        handleMatch = NO;
        NSUInteger keyCount = [cacheKeys count];
        NSUInteger keyIndex;
        
        for (keyIndex = 0; keyIndex < keyCount; keyIndex++) {
            id <OWCacheContentProvider> aCache = (id)CFArrayGetValueAtIndex((CFArrayRef)cacheKeys, keyIndex);
            id otherHandle;
    
            otherHandle = [other handleForCache:aCache];
    
            if (otherHandle == nil)
                continue;
            if (![otherHandle isEqual:[self handleForCache:aCache]])
                return NO;
            else {
                handleMatch = YES;
                break;
            }
        }
    
        if (!handleMatch) {
            BOOL contentMatch;
    
    #warning TODO LESS-BROKEN equality tests.
            // problems here:
            // 1. thread safety of access to concreteContent
            // 2. either our content or theirs may be missing atm.
            if (smallConcreteType == ConcreteType_DataStream)
                contentMatch = [(OWDataStream *)concreteContent isEqualToDataStream:[other objectValue]];
            else
                contentMatch = [concreteContent isEqual:other->concreteContent];
    
            if (!contentMatch)
                return NO;
        }
    
        // If we reach this point, we've decided we're equivalent to the other content (all our values are equal). Share any cache handles with the other content for efficiency's sake.
        os_unfair_lock_lock(&lock);
        locked = YES;
        [other _shareHandles:containingCaches];
        locked = NO;
        os_unfair_lock_unlock(&lock);
    
    } @catch (NSException *exc) {
        if (locked)
            os_unfair_lock_unlock(&lock);
        if ([exc name] != OWDataStreamNoLongerValidException)
            NSLog(@"-[%@ %@]: %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), [exc description]);
        return NO;
    }


    return YES;
}

- (NSUInteger)hash
{
    if (!metadataComplete)
        [NSException raise:NSInternalInconsistencyException format:@"Cannot compute hash of %@", [self description]];

    NSUInteger myContentHash = [self contentHash];

    if (metadataHash == 0) {
        NSUInteger hashAccum = 0xfaded;
        
        OFForEachObject([metaData keyEnumerator], NSString *, aKey) {
            hashAccum ^= ( [aKey hash] | 1 ) * ( [[metaData lastObjectForKey:aKey] hash] | 1 );
        }
        
        if (hashAccum == 0)  // Highly unlikely, but ...
            hashAccum = 1;

        metadataHash = hashAccum;
    }

    return myContentHash ^ metadataHash;
}

- (NSUInteger)contentHash
{
    if (contentHash == 0) {
        NSUInteger myContentHash;
        NSEnumerator *cacheEnumerator;
        id <OWCacheContentProvider> aCache;
        id valueToHash;

        valueToHash = nil;
        NS_DURING {
            os_unfair_lock_lock(&lock);
    
            if (concreteContent == nil) {
                cacheEnumerator = [containingCaches keyEnumerator];
                while( (aCache = [cacheEnumerator nextObject]) != nil) {
                    id handle = [containingCaches objectForKey:aCache];
                    os_unfair_lock_unlock(&lock);
                    myContentHash = [aCache contentHashForHandle:handle];
                    handle = nil;
                    if (myContentHash != 0) {
                        contentHash = myContentHash;
                        NS_VALUERETURN(myContentHash, NSUInteger);
                    }
                    os_unfair_lock_lock(&lock);
                }
    
                [self _locked_fillContent];
            }
    
            if (dataComplete == Data_NotComplete) {
                if ([concreteContent endOfData])
                    dataComplete = Data_EndedMaybeInvalid;
                else
                    [NSException raise:NSInternalInconsistencyException format:@"Cannot compute hash of unfinished %@", [self shortDescription]];
            }
            if (dataComplete == Data_EndedMaybeInvalid) {
                if (smallConcreteType == ConcreteType_DataStream) {
                    if ([concreteContent contentIsValid])
                        dataComplete = Data_EndedAndValid;
                    else
                        dataComplete = Data_EndedMaybeInvalid;
                }
            }
            if (dataComplete == Data_Invalid) {
                [NSException raise:NSInternalInconsistencyException format:@"Cannot compute hash of invalidated %@", [self shortDescription]];
            }
    
            valueToHash = concreteContent;

            os_unfair_lock_unlock(&lock);
        } NS_HANDLER {
            os_unfair_lock_unlock(&lock);
            [localException raise];
        } NS_ENDHANDLER;

        if ([valueToHash respondsToSelector:@selector(contentHash)]) {
            myContentHash = [valueToHash contentHash];
        } else if ([valueToHash respondsToSelector:@selector(md5Signature)]) {
            NSData *md5 = [valueToHash md5Signature];
            OBASSERT([md5 length] >= sizeof(NSUInteger));
            myContentHash = (NSUInteger)CFSwapInt64BigToHost(*(NSUInteger *)[md5 bytes]); // Will truncate to 32 bits under 32-bit ABI.
        } else {
            myContentHash = [valueToHash hash];
        }
        
        if (myContentHash == 0)
            myContentHash = 1;

        contentHash = myContentHash;
    }

    return contentHash;
}

- (void)useHandle:(id)newHandle forCache:(id <OWCacheContentProvider>)aCache;
{
    OBASSERT(newHandle != nil);
    OBASSERT(aCache != nil);

    os_unfair_lock_lock(&lock);

    CFMutableDictionaryRef handles = (__bridge CFMutableDictionaryRef)containingCaches;
    id incrementHandle = nil;
    id decrementHandle = nil;

    id oldHandle = CFDictionaryGetValue(handles, (__bridge const void *)(aCache));
    if (oldHandle != newHandle) {
        incrementHandle = newHandle;
        if (oldHandle != nil)
            decrementHandle = oldHandle;
        CFDictionarySetValue(handles, CFBridgingRetain(aCache), CFBridgingRetain(newHandle));
    }

    os_unfair_lock_unlock(&lock);

    if (incrementHandle != nil) {
        [aCache adjustHandle:incrementHandle reference:+1];
    }

    if (decrementHandle != nil) {
        [aCache adjustHandle:decrementHandle reference:-1];
    }
}

- (id)handleForCache:(id <OWCacheContentProvider>)aCache;
{
    id handle;
    
    os_unfair_lock_lock(&lock);
    handle = [containingCaches objectForKey:aCache];
    os_unfair_lock_unlock(&lock);

    return handle;
}

- (OWContent *)copyWithMutableHeaders;
{
    OWContent *newContent;

    os_unfair_lock_lock(&lock);
    newContent = [[[self class] alloc] initWithContent:concreteContent];
    // Direct access is OK here because nobody has a reference to the new content except us.
    newContent->contentHash = contentHash;
    [newContent addHeaders:metaData];
    os_unfair_lock_unlock(&lock);

    return newContent;
}

#warning OWContentHasNewMetadata notifications are commented out because they are currently unused
//NSString * const OWContentHasNewMetadataNotificationName = @"OWContentHasNewMetadata";

@end


@implementation OWContent (Private)

- _invalidContentType:(SEL)accessor
{
    [NSException raise:NSInvalidArgumentException format:@"Accessor -%@ invoked on %@ with content type %@",
        NSStringFromSelector(accessor), [self shortDescription], [concreteContent class]];
    return nil;
}

- (void)_locked_fillContent;
{
    NSEnumerator *cacheEnumerator;
    id <OWCacheContentProvider> aCache;

    OBPRECONDITION(concreteContent == nil);

    cacheEnumerator = [containingCaches keyEnumerator];
    while ( (aCache = [cacheEnumerator nextObject]) != nil ) {
        concreteContent = [aCache contentForHandle:[containingCaches objectForKey:aCache]];
        if (concreteContent != nil)
            break;
    }

    OBPOSTCONDITION([concreteContent conformsToProtocol:@protocol(OWConcreteCacheEntry)]);
    OBPOSTCONDITION(concreteContent != nil);
}

- (void)_shareHandles:(NSMutableDictionary *)otherContentHandles;
{
    NSEnumerator *cacheEnumerator;
    id <OWCacheContentProvider> aCache;
    id aHandle;

    // It's possible, though unlikely, for us to be deadlocking here (since the other content's lock will also be held at the moment). So we don't exchange handles if it would cause a block.
    if (!os_unfair_lock_trylock(&lock))
        return;

    cacheEnumerator = [otherContentHandles keyEnumerator];
    while( (aCache = [cacheEnumerator nextObject]) != nil ) {
        if ([containingCaches objectForKey:aCache] == nil) {
            aHandle = [otherContentHandles objectForKey:aCache];
            [aCache adjustHandle:aHandle reference:+1];
            CFDictionarySetValue((CFMutableDictionaryRef)containingCaches, CFBridgingRetain(aCache), CFBridgingRetain(aHandle));
        }
    }
    cacheEnumerator = [containingCaches keyEnumerator];
    while( (aCache = [cacheEnumerator nextObject]) != nil ) {
        if ([otherContentHandles objectForKey:aCache] == nil) {
            aHandle = [containingCaches objectForKey:aCache];
            [aCache adjustHandle:aHandle reference:+1];
            CFDictionarySetValue((CFMutableDictionaryRef)otherContentHandles, CFBridgingRetain(aCache), CFBridgingRetain(aHandle));
        }
    }

    os_unfair_lock_unlock(&lock);
}

- (BOOL)_locked_addHeader:(NSString *)headerName values:(NSArray *)several value:(id)one
{

    if (several && [several count]) {
        if (one) {
            several = [several arrayByAddingObject:one];
            one = nil;
        } else if ([several count] == 1) {
            one = [several objectAtIndex:0];
            several = nil;
        }
    } else {
        several = nil;
        if (one == nil)
            return NO;
    }

    if (one) {
        id oldValue = [metaData lastObjectForKey:headerName];

        if (oldValue == one && [oldValue isEqual:one])
            return NO;

        [metaData addObject:one forKey:headerName];
    } else {
        [metaData addObjects:several forKey:headerName];
    }

    if (cachedContentType != nil &&
        [headerName caseInsensitiveCompare:OWContentTypeHeaderString] == NSOrderedSame) {
        cachedContentType = nil;
    }

    return YES;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    // NOTE: Not thread-safe
    
    if (metadataComplete)
        [debugDictionary setObject:metaData forKey:@"metaData"];
    else
        [debugDictionary setObject:@"INCOMPLETE" forKey:@"metaData"];

    if (concreteContent) {
        if ([concreteContent isKindOfClass:[OWAddress class]])
            [debugDictionary setObject:[(OWAddress *)concreteContent addressString] forKey:@"concreteContent"];
        else
            [debugDictionary setObject:concreteContent forKey:@"concreteContent"];
    }

    return debugDictionary;
}

@end

