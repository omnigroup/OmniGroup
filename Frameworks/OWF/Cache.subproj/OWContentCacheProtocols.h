// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSString.h>
#import <OmniFoundation/OFObject.h>

@class /* Foundation */ NSDate, NSNotification;
@class /* OWF */ OWContent, OWContentType, OWPipeline, OWStaticArc, OWURL;
@protocol /* OWF */ OWConcreteCacheEntry, OWCacheArc, OWCacheArcProvider;

/*
These are the relationships an arc may have to content. In general, an arc describes a relationship between a 'subject' (e.g., a URL) and an 'object' (e.g., the data fetched from that URL). In some cases, one piece of content may describe a relation between two other pieces of content (directory listings provide metadata about other resources), in which case the 'source' and the 'subject' may be different.

OWCacheArcRelationship is a bitmask.
*/
typedef enum {
    OWCacheArcNoRelation  = 0,
    OWCacheArcAnyRelation = 7,
    OWCacheArcSubject     = 1,
    OWCacheArcSource      = 2,
    OWCacheArcObject      = 4
} OWCacheArcRelationship;

/* These are the possible results of calling -traverseInPipeline: */
typedef enum {
    OWCacheArcTraversal_Failed,          /* Unable to traverse the arc - e.g., it's not applicable, cache expired, etc. */
    OWCacheArcTraversal_HaveResult,      /* The result (arc object) is immediately available */
    OWCacheArcTraversal_WillNotify       /* OWCacheArcHasResultNotification will be posted when object is available */
} OWCacheArcTraversalResult;

/* Cache validation policy. */
typedef enum {
    // These enumeration values must match the tags in the OmniWeb preferences pane popup.
    OWCacheValidation_Always = 1,
    OWCacheValidation_UnlessCacheControl = 2,
    OWCacheValidation_Infrequent = 3,

    OWCacheValidation_DefaultBehavior = OWCacheValidation_UnlessCacheControl
} OWCacheValidationBehavior;

typedef enum {
    OWCacheArcRetrievedContent = 1,
    OWCacheArcDerivedContent,
    OWCacheArcInformationalHint,
} OWCacheArcType;    

/* There are three protocols which are of most interest to users of the cache system. <OWCacheArc> represents an actual cache relation, typically connecting input data to output data. Objects conforming to <OWCacheArcProvider> are able to produce cache arcs when queried. Objects conforming to <OWCacheContentProvider> are able to accept arcs given to them and store those arcs for later retrieval. For example, the disk cache is an <OWCacheContentProvider>, but the processor cache (which generates arcs on demand by invoking processors) is only an <OWCacheArcProvider>. */

@protocol OWCacheArcProvider <NSObject>

// This returns the list of all arcs contained in the cache
- (NSArray <id <OWCacheArc>> *)allArcs;

// This returns a list of arcs in the cache which have the specified relation to the specified entry. (It may return nil instead of an empty array if there are no relevant arcs.) The pipeline argument, if non-nil, serves as a hint that arcs that aren't valid in the given pipeline need not be included.
- (NSArray <id <OWCacheArc>> *)arcsWithRelation:(OWCacheArcRelationship)relation toEntry:(OWContent *)anEntry inPipeline:(OWPipeline *)aPipeline;  // pipeline is just a hint, may be nil

// The cost of querying the cache for arcs. Traversing an arc may have its own cost; you'll need to query the individual arc for that.
- (float)cost;

@end

@protocol OWCacheContentProvider <NSObject>

// For adding content to the cache
- (BOOL)canStoreContent:(OWContent *)someContent;
- (OWContent *)storeContent:(OWContent *)someContent;

// For referring to the concrete content without necessarily retrieving it from the cache, and for keeping the cache informed about what content it needs to retain
- (void)adjustHandle:(id)aHandle reference:(int)plusOrMinus;
- (unsigned)contentHashForHandle:(id)aHandle;
- (id <OWConcreteCacheEntry>)contentForHandle:(id)aHandle;

// For adding and removing relations between content. This could be broken out into a subprotocol of OWCacheArcProvider, but at the moment there's no reason to.
- (BOOL)canStoreArc:(id <OWCacheArc>)anArc;
- (id <OWCacheArc>)addArc:(OWStaticArc *)anArc;

// Objects conforming to OWCacheContentProvider can register for cache-related notifications.
- (void)invalidateResource:(OWURL *)resource beforeDate:(NSDate *)invalidationDate;
- (void)invalidateArc:(id <OWCacheArc>)cacheArc;

//- (void)removeArcsWithRelation:(OWCacheArcRelationship)relation toEntry:(OWContent *)anEntry;
//- (void)removeAllArcs;

@end

@protocol OWCacheArc <NSObject>

/* Returns all entries with the given relationship(s) to this arc. 'relation' may be a combination of several relationships, since it's a bitmask. */
/* NB - In an earlier draft of the design, arcs were expected to be able to have multiple 'object' entries and possibly other multiple entries. Currently there are no such situations. -entriesWithRelation: may go away at some point since in most situations it's easier to call one of the acessors below. (Or we may find a use for it and keep it.) */
- (NSArray *)entriesWithRelation:(OWCacheArcRelationship)relation;

/* More convenient and efficient ways to get related content */
- (OWContent *)subject;
- (OWContent *)source;
- (OWContent *)object;

/* What kind of relationship this arc represents. (Somewhat experimental.) */
- (OWCacheArcType)arcType;

- (unsigned)invalidInPipeline:(OWPipeline *)context;
- (OWCacheArcTraversalResult)traverseInPipeline:(OWPipeline *)context;

- (OWContentType *)expectedResultType;
- (float)expectedCost;
- (BOOL)abortArcTask;  // Called when the user hits the 'stop' button. Returns YES if there was anything to abort; NO otherwise.

- (NSDate *)firstBytesDate;
- (NSUInteger)bytesProcessed;
- (NSUInteger)totalBytes;

- (enum _OWProcessorStatus)status;
- (NSString *)statusString;
- (NSDate *)creationDate;

- (BOOL)resultIsSource;
- (BOOL)resultIsError;
- (BOOL)shouldNotBeCachedOnDisk;

// Flags returned by -invalidInPipeline:.
// #define OWCacheArcInvalidRelation    001
#define OWCacheArcInvalidContext     0002
#define OWCacheArcInvalidDate        0004
#define OWCacheArcInvalidated        0010
#define OWCacheArcStale              0020
#define OWCacheArcNeverValid         0040
#define OWCacheArcNotReusable        0100

// Adding and removing observers.
// Right now the only observers of arcs are OWPipelines, so there's no need to make a separate protocol for arc observers just yet.
- (void)addArcObserver:(OWPipeline *)anObject;
- (void)removeArcObserver:(OWPipeline *)anObject;

// Notifications emitted by an OWCacheArc, and their info dictionary keys
extern NSString *OWCacheArcHasResultNotification;
#define OWCacheArcObjectNotificationInfoKey (@"OWCacheArcObject")
#define OWCacheArcObjectIsErrorNotificationInfoKey (@"objectIsError")
#define OWCacheArcObjectIsSourceNotificationInfoKey (@"objectIsSource")
#define OWCacheArcInhibitDiskCacheNotificationInfoKey (@"inhibitDiskCache")

extern NSString *OWCacheArcProcessorStatusNotification;
#define OWCacheArcStatusStringNotificationInfoKey (@"StatusString")  // Value is a localized string
#define OWCacheArcIsFinishedNotificationInfoKey (@"Finished")  // Value is a bool NSNumber
#define OWCacheArcHasThreadChangeInfoKey (@"HasThreadChange") // Value is a NSNumber +1 or -1 for thread usage
#define OWCacheArcErrorNameNotificationInfoKey (OWPipelineHasErrorNotificationErrorNameKey)
#define OWCacheArcErrorReasonNotificationInfoKey (OWPipelineHasErrorNotificationErrorReasonKey)
#define OWCacheArcErrorProcessorNotificationInfoKey (OWPipelineHasErrorNotificationProcessorKey)

// Valid keys for -contextObjectForKey:. Any registered preference key can be used as well, and will return the site-specific value if there is one.
#define OWCacheArcSourceAddressKey           (@"sourceAddress")           // OWAddress *
#define OWCacheArcSourceURLKey               (@"sourceURL")               // OWURL *, derived from above
#define OWCacheArcReferringAddressKey        (@"referringAddress")
#define OWCacheArcReferringContentKey        (@"referringContentInfo")
#define OWCacheArcHistoryAddressKey          (@"HistoryAddress")
#define OWCacheArcCacheBehaviorKey           (@"cache behavior")          // see below for values
#define OWCacheArcEncodingOverrideKey        OWEncodingOverrideContextKey // NSNumber containing a CFStringEncoding
#define OWCacheArcTargetTypesKey             (@"accept-types")            // Dictionary mapping OWContentTypes to target's costs
#define OWCacheArcUseCachedErrorContentKey   (@"useCachedErrorContent")   // arcs which are cached error content will return NO from -isValidInPipeline: if useCachedErrorContent is false
#define OWCacheArcApplicableCookiesContentKey (@"cookies")  // An NSArray of OWCookie objects
#define OWCacheArcConditionalKey             (@"condition")               // 3-element array

// The OWCacheArcConditionalKey is a 3-element array:
//  [0]   The validator being used, e.g. "ETag" or "Last-Modified" (string, case-insensitive)
//  [1]   The value, e.g. the ETag itself (protocol-dependent)
//  [2]   NSNumber containing a boolean YES for if-changed, NO for if-same

// The OWCacheArcCacheBehaviorKey may have one of the following values; semantics are largely as for HTTP/1.1

#define OWCacheArcForbidNetwork               (@"only-if-cached")
    // Indicates whether the pipeline is allowed to use processors which use the network
#define OWCacheArcReload                      (@"no-cache")
    // Indicates that the content must be re-retrieved from the origin
#define OWCacheArcRevalidate                  (@"revalidate")
    // Indicates that the content must be re-validated with the origin (equiv to max-age=0)
#define OWCacheArcPreferCache                 (@"x-prefer-cache")
    // Indicates that cached content is preferred (e.g., when revisiting a page from history)

@end

extern NSString * const OWContentCacheFlushNotification;
#define OWContentCacheInvalidateOrRemoveNotificationInfoKey (@"action")
#define     OWContentCacheFlush_Invalidate (@"invalidate")
#define     OWContentCacheFlush_Remove (@"remove")

// NOTE: The OWContentCacheInvalidateResourceNotification is the *wrong* way to implement the function it performs, but I'm in a hurry. In the year 2525, if man is still alive, we should fix it, and get rid of that notification.


#define OWCacheValidationBehaviorPreferenceKey (@"OWCacheValidation")

@protocol OWConcreteCacheEntry <NSObject>

- (BOOL)endOfData;
    // For mutable (incrementally created) cache entries such as streams, this indicates whether the cache entry has finished being created. For entries which are created all at once (such as OWAddresses), this should always return YES.

- (BOOL)contentIsValid;
    // Returns YES if this content can be used.  Can be called from any thread, so the recipient must manage its own locks.

@end
