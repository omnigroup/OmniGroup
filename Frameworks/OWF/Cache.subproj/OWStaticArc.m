// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWStaticArc.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>

#import <OWF/NSDate-OWExtensions.h>
#import <OWF/OWAddress.h>
#import <OWF/OWContent.h>
#import <OWF/OWContentCacheGroup.h>
#import <OWF/OWContentType.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWProcessor.h>

#ifdef DEBUG_kc
#define DEBUG_Invalidation
#endif

RCS_ID("$Id$");

@implementation OWStaticArcInitialization
@end

@implementation OWStaticArc

static OFPreference *proportionalValidityFactorPreference = nil;
static OFPreference *maximumValidityPeriodPreference = nil;

+ (void)initialize
{
    OBINITIALIZE;

    proportionalValidityFactorPreference = [OFPreference preferenceForKey:@"OWProportionalExpirationFactor"];
    maximumValidityPeriodPreference = [OFPreference preferenceForKey:@"OWMaximumValidityPeriod"];
}

+ (NSString *)stringFromInvalidityFlags:(unsigned)invalidityFlags;
{
    if (invalidityFlags == 0)
        return @"(0)";
    
    NSMutableArray *flagStrings = [NSMutableArray array];

#define AddStringForFlag(flag, flagName) \
    if ((invalidityFlags & flag) != 0) { \
        [flagStrings addObject:flagName]; \
        invalidityFlags &= ~flag; \
    }

    AddStringForFlag(OWCacheArcInvalidContext, NSSTRINGIFY(OWCacheArcInvalidContext));
    AddStringForFlag(OWCacheArcInvalidDate, NSSTRINGIFY(OWCacheArcInvalidDate));
    AddStringForFlag(OWCacheArcInvalidated, NSSTRINGIFY(OWCacheArcInvalidated));
    AddStringForFlag(OWCacheArcStale, NSSTRINGIFY(OWCacheArcStale));
    AddStringForFlag(OWCacheArcNeverValid, NSSTRINGIFY(OWCacheArcNeverValid));
    AddStringForFlag(OWCacheArcNotReusable, NSSTRINGIFY(OWCacheArcNotReusable));

#undef AddStringForFlag

    OBASSERT(invalidityFlags == 0);
    if (invalidityFlags != 0)
        [flagStrings addObject:[NSString stringWithFormat:@"0x%02x", invalidityFlags]];

    return [NSString stringWithFormat:@"(%@)", [flagStrings componentsJoinedByString:@" | "]];
}

// Serialization and deserialization

static const unsigned char Serialization_Magic_1[4] = { 'S', 'a', 'M', 0 };
static const unsigned char Serialization_Magic_2[4] = { 'S', 'a' | 0x80, 'M', 0 };
#define SerialFlags_isError			001
#define SerialFlags_isSource			002
#define SerialFlags_isLocal			004
#define SerialFlags_hasCreationDate		010
#define SerialFlags_hasExpirationDate		020
#define SerialFlags_hasArchivedProperties	040
#define SerialFlags_nonReusable                0100

static void appendDate(NSMutableData *buf, NSDate *date)
{
    UInt32 timet;

    if (date == nil)
        timet = UINT32_MAX;
    else {
        NSTimeInterval interval = [date timeIntervalSince1970];

        if (interval < 0 || interval >= UINT32_MAX)
            timet = UINT32_MAX;
        else
            timet = interval;
    }

    assert(sizeof(timet) == 4);
    [buf appendBytes:&timet length:4];
}

static NSDate *extractDate(void *from)
{
    UInt32 timet;

    bcopy(from, &timet, sizeof(timet));
    if (timet == UINT32_MAX)
        return nil;
    else
        return [NSDate dateWithTimeIntervalSince1970:timet];
}

+ (BOOL)deserializeProperties:(OWStaticArcInitialization *)i fromBuffer:(NSData *)buf;
{
    i.contextDependencies = nil;

    if ([buf length] < 4)
        return NO;

    unsigned char *cursor = (unsigned char *)[buf bytes];
    unsigned char arcFlags;
    unsigned offset;

    if (!memcmp([buf bytes], Serialization_Magic_1, 3)) {
        arcFlags = cursor[3];
        i.arcType = OWCacheArcRetrievedContent;
        offset = 4;
    } else if(!memcmp([buf bytes], Serialization_Magic_2, 3)) {
        unsigned char moreArcFlags;

        arcFlags = cursor[3];
        moreArcFlags = cursor[4];

        i.arcType = ( moreArcFlags & 0x0F );
        
        offset = 5;
    } else {
        arcFlags = SerialFlags_hasArchivedProperties;
        offset = 0;
    }
    
    i.resultIsSource   = (arcFlags & SerialFlags_isSource)? YES : NO;
    i.resultIsError    = (arcFlags & SerialFlags_isError)? YES : NO;
    i.shouldNotBeCachedOnDisk = (arcFlags & SerialFlags_isLocal)? YES : NO;
    i.nonReusable      = (arcFlags & SerialFlags_nonReusable)? YES : NO;

    if (arcFlags & SerialFlags_hasCreationDate) {
        i.creationDate = extractDate(cursor + offset);
        offset += 4;
    }
    if (arcFlags & SerialFlags_hasExpirationDate) {
        i.freshUntil = extractDate(cursor + offset);
        offset += 4;
    }

    NSKeyedUnarchiver *arch;
    if (arcFlags & SerialFlags_hasArchivedProperties) {
        NSRange archivedRange = { offset, [buf length] - offset };
        arch = [[NSKeyedUnarchiver alloc] initForReadingWithData:[buf subdataWithRange:archivedRange]];
    } else
        arch = nil;

    if ([arch containsValueForKey:@"context"])
        i.contextDependencies = [arch decodeObjectForKey:@"context"];
    if ([arch containsValueForKey:@"created"])
        i.creationDate = [arch decodeObjectForKey:@"created"];
    if ([arch containsValueForKey:@"expires"])
        i.freshUntil = [arch decodeObjectForKey:@"expires"];
    if ([arch containsValueForKey:@"src"])
        i.resultIsSource = [arch decodeBoolForKey:@"src"];
    if ([arch containsValueForKey:@"err"])
        i.resultIsError = [arch decodeBoolForKey:@"err"];
    if ([arch containsValueForKey:@"local"])
        i.shouldNotBeCachedOnDisk = [arch decodeBoolForKey:@"local"];

    return YES;
}

- (NSData *)serialize;
{
    unsigned char arcFlags = 0;
    unsigned char moreArcFlags;

    NSMutableData *buf = [[NSMutableData alloc] init];

    arcFlags = 0;
    if (resultIsError)
        arcFlags |= SerialFlags_isError;
    if (resultIsSource)
        arcFlags |= SerialFlags_isSource;
    if (shouldNotBeCachedOnDisk)
        arcFlags |= SerialFlags_isLocal;
    if (freshUntil != nil)
        arcFlags |= SerialFlags_hasExpirationDate;
    if (creationDate != nil)
        arcFlags |= SerialFlags_hasCreationDate;
    if ([contextDependencies count])
        arcFlags |= SerialFlags_hasArchivedProperties;
    if (nonReusable)
        arcFlags |= SerialFlags_nonReusable;

    if (arcType == OWCacheArcRetrievedContent) {
        [buf appendBytes:Serialization_Magic_1 length:3];
        [buf appendBytes:&arcFlags length:1];
    } else {
        [buf appendBytes:Serialization_Magic_2 length:3];
        [buf appendBytes:&arcFlags length:1];
        moreArcFlags = ( arcType & 0x0F );
        [buf appendBytes:&moreArcFlags length:1];
    }

    if (arcFlags & SerialFlags_hasCreationDate)
        appendDate(buf, creationDate);
    if (arcFlags & SerialFlags_hasExpirationDate)
        appendDate(buf, freshUntil);
    if (arcFlags & SerialFlags_hasArchivedProperties) {
        NSKeyedArchiver *arch = [[NSKeyedArchiver alloc] initForWritingWithMutableData:buf];
        if ([contextDependencies count])
            [arch encodeObject:contextDependencies forKey:@"context"];
        [arch finishEncoding];
    }

    return buf;
}

// Init and dealloc

- initWithArcInitializationProperties:(OWStaticArcInitialization *)initialProperties;
{
    if (!(self = [super init]))
        return nil;

    OBASSERT(initialProperties.arcType != 0);
    OBASSERT([initialProperties.subject endOfData]);
    OBASSERT([initialProperties.subject endOfHeaders]);
    OBASSERT([initialProperties.source endOfData]);
    OBASSERT([initialProperties.source endOfHeaders]);
    OBASSERT([initialProperties.object endOfData]);
    OBASSERT([initialProperties.object endOfHeaders]);

    arcType = initialProperties.arcType;
    subject = initialProperties.subject;
    source = initialProperties.source;
    object = initialProperties.object;

    if (initialProperties.contextDependencies != nil)
        contextDependencies = [initialProperties.contextDependencies copy];
    else
        contextDependencies = [[NSDictionary alloc] init];
    freshUntil = initialProperties.freshUntil;
    creationDate = initialProperties.creationDate;
    if (creationDate == nil)
        creationDate = [[NSDate alloc] init];

    resultIsSource = initialProperties.resultIsSource;
    resultIsError = initialProperties.resultIsError;
    shouldNotBeCachedOnDisk = initialProperties.shouldNotBeCachedOnDisk;
    nonReusable = initialProperties.nonReusable;

    return self;
}

// API

- (OWCacheArcType)arcType  { return arcType; }
- (OWContent *)subject   { return subject; }
- (OWContent *)source    { return source;  }
- (OWContent *)object    { return object;  }

- (NSArray *)entriesWithRelation:(OWCacheArcRelationship)relation
{
    switch(relation) {
        case OWCacheArcNoRelation:
            return [NSArray array];
        case OWCacheArcSubject:
            return [NSArray arrayWithObject:subject];
        case OWCacheArcSource:
            return [NSArray arrayWithObject:source];
        case OWCacheArcObject:
            return [NSArray arrayWithObject:object];
        default:
        {
            NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:3];
            if (relation & OWCacheArcSubject)
                [result addObject:subject];
            if (relation & OWCacheArcSource)
                [result addObject:source];
            if (relation & OWCacheArcObject)
                [result addObject:object];
            return result;
        }
    }
}

- (OWCacheArcRelationship)relationsOfEntry:(OWContent *)anEntry intern:(OWContent **)interned
{
    OWCacheArcRelationship relations;
    OWContent *match;
    BOOL matchesSource, matchesSubject;

    relations = OWCacheArcNoRelation;
    match = nil;
    
    matchesSource = source != nil && [anEntry isEqual:source];
    if (matchesSource) {
        relations |= OWCacheArcSource;
        match = source;
    }

    if (source == subject)
        matchesSubject = matchesSource;
    else
        matchesSubject = subject != nil && [anEntry isEqual:subject];

    if (matchesSubject) {
        relations |= OWCacheArcSubject;
        match = subject;
    }

    if (object && [anEntry isEqual:object]) {
        relations |= OWCacheArcObject;
        match = object;
    }

    if (interned) {
        if (match)
            *interned = match;
        else
            *interned = anEntry;
    }

    return relations;
}

- (unsigned)invalidInPipeline:(OWPipeline *)pipeline;
{
    unsigned invalidity = 0;

    NSString *cacheBehavior = [pipeline contextObjectForKey:OWCacheArcCacheBehaviorKey];
    if (cacheBehavior != nil) {
        if ([cacheBehavior isEqual:OWCacheArcPreferCache])
            return 0; // The target prefers cached content, whether or not it is invalid

        if (([cacheBehavior isEqual:OWCacheArcReload] || [cacheBehavior isEqual:OWCacheArcRevalidate]) &&
            arcType == OWCacheArcRetrievedContent)
            invalidity |= OWCacheArcStale;
    }

    OWCacheValidationBehavior cacheAggressiveness = (int)[[OWContentCacheGroup cacheValidationPreference] enumeratedValue];

    if (invalidated)
        invalidity |= OWCacheArcInvalidated;
    
    if (cacheAggressiveness == OWCacheValidation_Always && arcType == OWCacheArcRetrievedContent)
        invalidity |= OWCacheArcStale;

    if (nonReusable)
        invalidity |= OWCacheArcNotReusable | OWCacheArcStale;
    
    NSDate *pipelineFetchDate = [pipeline fetchDate];

    if (pipelineFetchDate != nil && arcType != OWCacheArcDerivedContent) {
        if (freshUntil) {
            if ([freshUntil compare:pipelineFetchDate] == NSOrderedAscending) {
#ifdef DEBUG_Invalidation
                NSLog(@"Arc %@: explicit expire %g ago", OBShortObjectDescription(self), [freshUntil timeIntervalSinceDate:pipelineFetchDate]);
#endif
                invalidity |= OWCacheArcInvalidDate;
            }
        } else if (cacheAggressiveness == OWCacheValidation_Infrequent) {
            NSTimeInterval arcAge;

            arcAge = [pipelineFetchDate timeIntervalSinceDate:creationDate];
            if (arcAge > [maximumValidityPeriodPreference floatValue])
                invalidity |= OWCacheArcInvalidDate;
        } else {
            OWContentType *resultType;
            NSTimeInterval arcAge, contentAgeAtFetch, maximumValidityPeriod;
            NSString *modDate;

            resultType = [object contentType];
            if (!resultType || ![resultType expirationTimeInterval]) {
                if ([object isSource])
                    resultType = [OWContentType sourceContentType];
                else if ([self resultIsError])
                    resultType = [OWContentType errorContentType];
            }
            if (!resultType || ![resultType expirationTimeInterval]) {
                resultType = [OWContentType wildcardContentType];
            }
            maximumValidityPeriod = [resultType expirationTimeInterval];
            if (maximumValidityPeriod <= 0.0 || maximumValidityPeriod > [maximumValidityPeriodPreference floatValue])
                maximumValidityPeriod = [maximumValidityPeriodPreference floatValue];

            OBINVARIANT(creationDate != nil);
            arcAge = [pipelineFetchDate timeIntervalSinceDate:creationDate];

            if (arcAge > maximumValidityPeriod) {
#ifdef DEBUG_Invalidation
                NSLog(@"Arc %@: implicit expire %g ago (%@ ivl=%g)", OBShortObjectDescription(self), arcAge - maximumValidityPeriod, [resultType contentTypeString], [resultType expirationTimeInterval]);
#endif
                invalidity |= OWCacheArcInvalidDate;
            }

            modDate = [object lastObjectForKey:OWEntityLastModifiedHeaderString];
            contentAgeAtFetch = 0;
            if (modDate != nil) {
                NSDate *lastModifiedDate = [NSDate dateWithHTTPDateString:modDate];
                if (lastModifiedDate == nil)
                    modDate = nil;
                else
                    contentAgeAtFetch = [creationDate timeIntervalSinceDate:lastModifiedDate];
            }
            
            if (modDate != nil &&
                arcAge > (contentAgeAtFetch * [proportionalValidityFactorPreference floatValue])) {
#ifdef DEBUG_Invalidation
                NSLog(@"Arc %@: implicit expire %g ago, age=%g, max is %g (%d%% of %g)", OBShortObjectDescription(self), arcAge - (contentAgeAtFetch * [proportionalValidityFactorPreference floatValue]), arcAge, (contentAgeAtFetch * [proportionalValidityFactorPreference floatValue]), (int)(100 * [proportionalValidityFactorPreference floatValue]), contentAgeAtFetch);
#endif
                invalidity |= OWCacheArcInvalidDate;
            }
        }
#ifdef DEBUG_Invalidation0
        {
            NSString *logDescription;

            if ([source isAddress])
                logDescription = [[source address] addressString];
            else
                logDescription = [source shortDescription];

            NSLog(@"-[%@ %s]: arc<%@> invalidity=%@, created %g ago", OBShortObjectDescription(self), _cmd, logDescription, [isa stringFromInvalidityFlags:invalidity], [pipelineFetchDate timeIntervalSinceDate:creationDate]);
        }
#endif
    }

    if (resultIsError) {
        NSNumber *useCachedErrorContent = [pipeline contextObjectForKey:OWCacheArcUseCachedErrorContentKey];
        if (useCachedErrorContent != nil && ![useCachedErrorContent boolValue])
            invalidity |= OWCacheArcNeverValid;
    }

    NSEnumerator *keyEnumerator = [contextDependencies keyEnumerator];
    NSString *contextKey;

    while ((contextKey = [keyEnumerator nextObject]) != nil) {
        id desiredValue, actualValue;

        desiredValue = [contextDependencies objectForKey:contextKey];
        if (desiredValue == [NSNull null])
            desiredValue = nil;
        actualValue = [pipeline contextObjectForKey:contextKey arc:self];
        if (desiredValue != actualValue &&
            (desiredValue == nil || ![desiredValue isEqual:actualValue])) {
#ifdef DEBUG_Invalidation
            NSLog(@"%@: mismatch key=%@ value=%@ value(%@)=%@",
                  [self shortDescription], contextKey, desiredValue, [pipeline shortDescription], actualValue);
#endif
            invalidity |= OWCacheArcInvalidContext;
            break;
        }
    }
    
    // TODO: Idempotence
#ifdef DEBUG_Invalidation
    {
        NSString *logDescription;

        if ([source isAddress])
            logDescription = [[source address] addressString];
        else
            logDescription = [source shortDescription];

        NSLog(@"-[%@ %@]: arc<%@> invalidity=%@, created %g ago", OBShortObjectDescription(self), NSStringFromSelector(_cmd), logDescription, [[self class] stringFromInvalidityFlags:invalidity], pipelineFetchDate != nil ? [pipelineFetchDate timeIntervalSinceDate:creationDate] : 0.0);
    }
#endif
    return invalidity;
}

- (OWCacheArcTraversalResult)traverseInPipeline:(OWPipeline *)context
{
    if (object)
        return OWCacheArcTraversal_HaveResult;
    else
        return OWCacheArcTraversal_Failed;
}

- (OWContentType *)expectedResultType;
{
    return [object contentType];
}

- (float)expectedCost
{
    return 0;
}

- (BOOL)abortArcTask
{
    return NO;
}

- (NSDate *)firstBytesDate;
{
    return nil;
}

- (NSUInteger)bytesProcessed;
{
    return [self totalBytes];
}

- (NSUInteger)totalBytes;
{
    if ([object isDataStream]) {
        OWDataStream *dataStream = [object objectValue];
        OBASSERT([dataStream knowsDataLength]); // Or asking for the -dataLength would block
        if ([dataStream knowsDataLength]) // Just to be safe, let's not rely on the above assertion...
            return [dataStream dataLength];
    }
    return 0;
}

- (enum _OWProcessorStatus)status;
{
    return OWProcessorRetired;
}

- (NSString *)statusString;
{
    return nil;
}

- (NSDate *)creationDate
{
    return creationDate;
}

- (BOOL)resultIsSource
{
    return resultIsSource;
}

- (BOOL)resultIsError
{
    return resultIsError;
}

- (BOOL)shouldNotBeCachedOnDisk
{
    return shouldNotBeCachedOnDisk;
}

- (BOOL)dominatesArc:(OWStaticArc *)anotherArc;
{
    NSComparisonResult order;
    NSEnumerator *myKeys;
    NSString *contextKey;

    /* Make sure that we're talking about the same thing. */
    if ([subject isAddress]) {
        if (![[anotherArc subject] isAddress])
            return NO;
        if (![[subject address] isSameDocumentAsAddress:[[anotherArc subject] address]])
            return NO;
    } else {
        if (![subject isEqual:[anotherArc subject]])
            return NO;
    }

    /* Older arcs can't supersede newer ones. */
    order = [anotherArc->creationDate compare:creationDate];
    if (order == NSOrderedDescending) {
        return NO;
    }

    if (anotherArc->invalidated && !invalidated)
        return YES;

    if ([contextDependencies count] == 0)
        return YES;

    myKeys = [contextDependencies keyEnumerator];
    while ( (contextKey = [myKeys nextObject]) != nil ) {
        id myValue, anotherArcValue;

        anotherArcValue = [anotherArc->contextDependencies objectForKey:contextKey];
        if (anotherArcValue == nil)
            return NO;
        myValue = [contextDependencies objectForKey:contextKey];
        if (![myValue isEqual:anotherArcValue])
            return NO;
    }

    return YES;
}

- (void)invalidate;  // for cache control, not for retain cycle breaking!
{
    invalidated = YES;
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setIntValue:arcType forKey:@"arcType"];
    if (source != nil && source != subject)
        [debugDictionary setValue:source forKey:@"source"];
    [debugDictionary setValue:subject forKey:@"subject"];
    [debugDictionary setValue:object forKey:@"object"];
    [debugDictionary setValue:contextDependencies forKey:@"contextDependencies"];
    [debugDictionary setValue:creationDate forKey:@"creationDate"];
    [debugDictionary setValue:freshUntil forKey:@"freshUntil"];
    [debugDictionary setValue:resultIsSource ? @"YES" : @"NO" forKey:@"resultIsSource"];
    [debugDictionary setValue:resultIsError ? @"YES" : @"NO" forKey:@"resultIsError"];
    [debugDictionary setValue:shouldNotBeCachedOnDisk ? @"YES" : @"NO" forKey:@"shouldNotBeCachedOnDisk"];
    [debugDictionary setValue:invalidated ? @"YES" : @"NO" forKey:@"invalidated"];

    return debugDictionary;
}

// Static arcs never produce any events, so they don't need to keep track of observers
- (void)addArcObserver:(OWPipeline *)anObserver
{
}

- (void)removeArcObserver:(OWPipeline *)anObserver
{
}

@end

