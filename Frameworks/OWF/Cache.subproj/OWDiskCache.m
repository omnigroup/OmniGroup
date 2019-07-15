// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWDiskCache.h"

#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniSQLite/OmniSQLite.h>
#import <OWF/OWAddress.h>
#import <OWF/OWContent.h>
#import <OWF/OWContentCacheGroup.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWURL.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWStaticArc.h>


#import "OWDiskCacheInternal.h"

RCS_ID("$Id$");

// OWDiskCache maintains a small LRU cache of retrieved objects
// TODO: Do some profiling to tune these parameters.
#define LRUContentHighWater  24
#define LRUContentLowWater    5

// OX wants a hint as to how many pages of the database to keep in-core at a given time. Greg says 100 is a reasonable number (and that at some point in the future OX should be able to figure this out for itself).
#define OmniIndexPagesInCache (100)

// Maximum number of bytes long a Content's value can be before it's stored in a blob. 
#define MAXIMUM_INTUPLE_DATA_SIZE (100)

#define TOTAL_CONTENT_SIZE_FILE_INFO_INDEX (20)

@interface OWDiskCache (Private) <OFWeakRetain>

// BOOL OWDiskCacheDeferLoadingContent = YES;

+ (BOOL)_initializeDatabase:(OSLDatabaseController *)newDB;
+ (NSString *)_indexFilenameForBundlePath:(NSString *)aBundlePath;
- (NSString *)_indexFilename;
- (id)_initWithDatabaseController:(OSLDatabaseController *)aDatabaseController bundle:(NSString *)aBundlePath;
- (NSNumber *)_keyForContent:(OWContent *)someContent insert:(BOOL)shouldInsert;
- (OWContent *)_contentForKey:(NSNumber *)contentID;
- (id <OWConcreteCacheEntry>)_r_concreteContentFromRow:(NSDictionary *)row;
- (NSDictionary *)_r_rowForId:(id)aHandle;
- (OWContent *)_contentFromRow:(NSDictionary *)row;
- (void)_pullArcsIntoMutableArray:(NSMutableArray *)targetArray contentId:(NSNumber *)contentId column:(NSString *)columnName;
- (OWStaticArc *)_r_arcFromRow:(NSDictionary *)row;
- (void)controllerWillTerminate:(OFController *)controller;
- (void)_flushCache:(NSNotification *)note;
- (int)_deleteContentRow:(NSDictionary *)contentRow andReferences:(BOOL)mayHaveReferences;
- (int)_deleteOldestContent;
- (void)_deletePendingArcs;
- (void)_deleteArcID:(NSNumber *)anArcId;
- (void)_reduceCacheSize;
- (void)_lockedCancelPreenEvent;
- (void)_preenCache;

static enum OWDiskCacheConcreteContentType concreteTypeOfContent(OWContent *content);

@end

static NSString *CorruptDatabaseException = @"CorruptDatabaseException";

@implementation OWDiskCache

+ (OWDiskCache *)createCacheAtPath:(NSString *)newBundlePath;
{
    NSDictionary *dirAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt: 0711], NSFilePosixPermissions,
        [NSNumber numberWithBool:YES], NSFileExtensionHidden,
        nil];

    NSDictionary *pubAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt: 0644], NSFilePosixPermissions,
        nil];

    NSDictionary *privAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt: 0700], NSFilePosixPermissions,
        nil];
    
    NSString *contents = [newBundlePath stringByAppendingPathComponent:@"Contents"];
    NSString *dataDir = [contents stringByAppendingPathComponent:@"Data"];
    NSString *indexFile = [self _indexFilenameForBundlePath:newBundlePath];

    NSMutableDictionary *infoPlist = [[NSMutableDictionary alloc] init];
    /* Note - CFBundleInfoDictionaryVersion is the version of the Info.plist format, as controlled by Apple. The version of the cache bundle, as controlled by Omni, is indicated by OWDiskCache_DBVersion. */
    [infoPlist setObject:@"6.0" forKey:@"CFBundleInfoDictionaryVersion"];
    [infoPlist setObject:@"English" forKey:@"CFBundleDevelopmentRegion"];
    [infoPlist setObject:@"BNDL" forKey:@"CFBundlePackageType"];
    [infoPlist setObject:@"OWEB" forKey:@"CFBundleSignature"];
    [infoPlist setObject:@"OmniWeb Cache File" forKey:@"CFBundleName"];
    [infoPlist setIntValue:OWDiskCache_DBVersion forKey:OWDiskCache_DBVersion_Key];

    NSData *infoPlistXml = (NSData *)CFPropertyListCreateXMLData(kCFAllocatorDefault, infoPlist);
    [infoPlist release];
    [infoPlistXml autorelease];

    NSMutableData *pkgInfo = [[NSMutableData alloc] initWithCapacity:8];
    [pkgInfo autorelease];
    [pkgInfo appendBytes:"BNDL" length:4];
    [pkgInfo appendBytes:"OWEB" length:4];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:newBundlePath])
        [fileManager removeFileAtPath:newBundlePath handler:nil];

    BOOL ok = [fileManager createDirectoryAtPath:newBundlePath attributes:dirAttrs];
    if (!ok)
        return nil;

    ok = [fileManager createDirectoryAtPath:contents attributes:dirAttrs];
    if (!ok)
        return nil;

    ok = [fileManager createFileAtPath:[contents stringByAppendingPathComponent:@"Info.plist"] contents:infoPlistXml attributes:pubAttrs];
    if (!ok)
        return nil;
    ok = [fileManager createFileAtPath:[contents stringByAppendingPathComponent:@"PkgInfo"] contents:pkgInfo attributes:pubAttrs];
    if (!ok)
        return nil;
    
    ok = [fileManager createDirectoryAtPath:dataDir attributes:privAttrs];
    if (!ok)
        return nil;

    NSDictionary *lockinfo = [fileManager lockFileAtPath:indexFile overridingExistingLock:NO];
    if (lockinfo != nil)
        return nil;

    OSLDatabaseController *newDB = [[OSLDatabaseController alloc] initWithDatabasePath:indexFile];
    if (newDB == nil || ![self _initializeDatabase:newDB]) {
        [newDB deleteDatabase];
        [fileManager unlockFileAtPath:indexFile];
        return nil;
    }

    OWDiskCache *result = [[self alloc] _initWithDatabaseController:newDB bundle:newBundlePath];
    [newDB release];
    return [result autorelease];
}

+ (OWDiskCache *)openCacheAtPath:(NSString *)oldBundlePath;
{
    NSString *contents = [oldBundlePath stringByAppendingPathComponent:@"Contents"];
    NSString *plistFile = [contents stringByAppendingPathComponent:@"Info.plist"];
    NSString *indexFile = [self _indexFilenameForBundlePath:oldBundlePath];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *fileAttributes = [fileManager fileAttributesAtPath:oldBundlePath traverseLink:YES];
    if (![[fileAttributes fileType] isEqualToString:NSFileTypeDirectory])
        return nil;
    fileAttributes = [fileManager fileAttributesAtPath:plistFile traverseLink:NO];
    if (![[fileAttributes fileType] isEqualToString:NSFileTypeRegular])
        return nil;

    NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    if (!infoPlist)
        return nil;
    id cacheBundlePlistVersion = [infoPlist objectForKey:@"CFBundleInfoDictionaryVersion"];
    if (cacheBundlePlistVersion == nil || [cacheBundlePlistVersion intValue] != 6)
        return nil;

    if ([infoPlist intForKey:OWDiskCache_DBVersion_Key] != OWDiskCache_DBVersion)
        return nil;

    NSDictionary *lockInfo = [fileManager lockFileAtPath:indexFile overridingExistingLock:NO];
    if (lockInfo)
        return nil;

    OSLDatabaseController *aDatabaseController;
    NS_DURING {
        aDatabaseController = [[OSLDatabaseController alloc] initWithDatabasePath:indexFile];
    } NS_HANDLER {
        NSLog(@"Unable to open disk cache %@: OSLDatabaseController init: %@", oldBundlePath, [localException reason]);
        aDatabaseController = nil;
    } NS_ENDHANDLER;
    if (!aDatabaseController) {
        [fileManager unlockFileAtPath:indexFile];
        return nil;
    }

    OWDiskCache *result = [[self alloc] _initWithDatabaseController:aDatabaseController bundle:oldBundlePath];
    [aDatabaseController release];
    return [result autorelease];
}

- (void)close
{
    [OWContentCacheGroup removeContentCacheObserver:self];
    
    if (databaseController != nil) {
        [dbLock lock];
        [self _lockedCancelPreenEvent];
        // [databaseController commitTransaction];
        [databaseController release];
        databaseController = nil;
        [dbLock unlock];
        [[NSFileManager defaultManager] unlockFileAtPath:[self _indexFilename]];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OWContentCacheFlushNotification object:nil];
    [self close];

    OBASSERT(databaseController == nil); // This was done by -close
    [dbLock release];
    dbLock = nil;
    [bundlePath release];
    bundlePath = nil;
    
    [arcsToRemove release];
    [contentToGC release];
    
    [super dealloc];
}

- (BOOL)canStoreContent:(OWContent *)someContent;
{
    if (![someContent isHashable] || ![someContent isStorable])
        return NO;
        
    switch (concreteTypeOfContent(someContent)) {
        case OWDiskCacheBytesConcreteType:
            if ([[someContent objectValue] hasThrownAwayData])
                return NO;
            /* FALL THROUGH */
        default:
            return YES;
        case OWDiskCacheUnknownConcreteType:
            return NO;
    }
}

- (BOOL)canStoreArc:(id <OWCacheArc>)anArc;
{
    if (anArc == nil)
        return NO;

    if ([anArc shouldNotBeCachedOnDisk])
        return NO;

    if ([anArc arcType] == OWCacheArcDerivedContent)
        return NO;

    NSArray *relatedContent = [anArc entriesWithRelation:OWCacheArcAnyRelation];
    unsigned int relatedContentCount = [relatedContent count];
    unsigned int relatedContentIndex;
    for (relatedContentIndex = 0; relatedContentIndex < relatedContentCount; relatedContentIndex++) {
        if (![self canStoreContent:[relatedContent objectAtIndex:relatedContentIndex]])
            return NO;
    }

    return YES;
}

- (id <OWCacheArc>)addArc:(OWStaticArc *)anArc;
{
    NSNumber *subjHandle, *srcHandle, *objHandle;
    NSData *arcInfo;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    // The serialize call sometimes raises, so do it before we start the database transaction
    arcInfo = [anArc serialize];
    if (!arcInfo)
        return nil;

    [self removeEntriesDominatedByArc:anArc];
    
    [dbLock lock];

    NS_DURING {
        [databaseController beginTransaction];
        [self _reduceCacheSize];
        
        subjHandle = [self _keyForContent:[anArc subject] insert:YES];
        srcHandle  = [self _keyForContent:[anArc source ] insert:YES];
        objHandle  = [self _keyForContent:[anArc object ] insert:YES];

        OBASSERT(subjHandle && srcHandle && objHandle);
        OBASSERT(arcInfo != nil);
        if (!(subjHandle && srcHandle && objHandle && arcInfo)) {
            [databaseController rollbackTransaction];
            [dbLock unlock];
            NS_VALUERETURN(nil, id);
        }

        // CREATE TABLE Arc (arc_id integer primary key, source integer, subject integer, object integer, metadata);
        OSLPreparedStatement *insertStatement = [databaseController prepareStatement:@"insert into Arc values (?, ?, ?, ?, ?);"];

        [insertStatement bindNull]; // arc_id
        [insertStatement bindInt:[srcHandle unsignedIntValue]]; // source
        [insertStatement bindInt:[subjHandle unsignedIntValue]]; // subject
        [insertStatement bindInt:[objHandle unsignedIntValue]]; // object
        [insertStatement bindBlob:arcInfo]; // metadata
        [insertStatement step];
        [insertStatement reset];

        [contentToGC removeObject:subjHandle];
        [contentToGC removeObject:srcHandle];
        [contentToGC removeObject:objHandle];

    } NS_HANDLER {
#ifdef DEBUG
        NSLog(@"-[%@ %s], caught exception %@", OBShortObjectDescription(self), _cmd, [localException reason]);
#endif
        [databaseController rollbackTransaction];
        [localException retain];
        [pool release];
        [localException autorelease];
        [dbLock unlock];
        if ([[localException name] isEqualToString:CorruptDatabaseException])
            [self _flushCache:nil];
        [localException raise];
    } NS_ENDHANDLER;

    [databaseController commitTransaction];
    [pool release];
    [dbLock unlock];
    

    [preenEvent invokeLater];

    return anArc;
}

- (NSArray *)allArcs;
{
    NSMutableArray *allArcs = [[NSMutableArray alloc] init];
    OSLPreparedStatement *selectStatement = [databaseController prepareStatement:@"select * from Arc;\n"];
    NSDictionary *arcRow;
    while ((arcRow = [selectStatement step]) != nil) {
        OWStaticArc *arc = [self _r_arcFromRow:arcRow];
        [allArcs addObject:arc];
        [arc release];
    }
    [selectStatement reset];
    return [allArcs autorelease];
}

- (NSArray *)arcsWithRelation:(OWCacheArcRelationship)relation toEntry:(OWContent *)anEntry inPipeline:(OWPipeline *)pipe;
{
    NSMutableArray *arcs;
    id handle;
    NSString *cacheControl;
    NSAutoreleasePool *pool;

    // This method can block on disk I/O and take a while...
    OBASSERT(![OWPipeline isLockHeldByCallingThread]);

    // minor optimization
    cacheControl = [pipe contextObjectForKey:OWCacheArcCacheBehaviorKey];
    if (cacheControl &&
        ([cacheControl isEqual:OWCacheArcReload] || [cacheControl isEqual:OWCacheArcRevalidate]))
        return nil;    

    pool = [[NSAutoreleasePool alloc] init];
    [dbLock lock];
    NS_DURING {
        handle = [self _keyForContent:anEntry insert:NO];
    } NS_HANDLER {
#ifdef DEBUG
        NSLog(@"-[%@ %s]: %@", OBShortObjectDescription(self), _cmd, [localException description]);
#endif
        if ([[localException name] isEqualToString:CorruptDatabaseException])
            [self _flushCache:nil];
        handle = nil;
    } NS_ENDHANDLER;

    if (!handle) {
        // The source content wasn't found in our database
        [pool release];
        [dbLock unlock];
        return nil;
    }
    
    OBASSERT([handle isKindOfClass:[NSNumber class]]);

    arcs = [[NSMutableArray alloc] init];

    NS_DURING {
    
        if (relation & OWCacheArcSubject)
            [self _pullArcsIntoMutableArray:arcs contentId:handle column:@"subject"];
        if (relation & OWCacheArcObject)
            [self _pullArcsIntoMutableArray:arcs contentId:handle column:@"object"];
        if (relation & OWCacheArcSource)
            [self _pullArcsIntoMutableArray:arcs contentId:handle column:@"source"];

    } NS_HANDLER {
#ifdef DEBUG
        NSLog(@"-[%@ %s]: %@", OBShortObjectDescription(self), _cmd, [localException description]);
#endif
        if ([[localException name] isEqualToString:CorruptDatabaseException]) {
            [arcs removeAllObjects];
            [localException retain];
            [pool release];
            [localException autorelease];
            [dbLock unlock];
            [self _flushCache:nil];
            [localException raise];
        }
    } NS_ENDHANDLER;

    // Try not to let database objects dealloc outside of the lock.
    [pool release];
    [dbLock unlock];
    
#ifdef DEBUG_wiml
    if ([arcs count])
        NSLog(@"%@ found %d arcs with relation 0x%02x to entry %@",
              OBShortObjectDescription(self), [arcs count], relation, OBShortObjectDescription(anEntry));
#endif

    return [arcs autorelease];
}

- (float)cost;
{
    return 0.25;  // moderate cost --- cheaper than firing off a processor, but more expensive than the memory cache
}

// For referring to the concrete content without necessarily retrieving it from the cache, and for keeping the cache informed about what content it needs to retain
- (void)adjustHandle:(id)aHandle reference:(int)referenceCountOffset;
{
    OBASSERT([aHandle isKindOfClass:[NSNumber class]]);

    OFSimpleLock(&retainedHandlesLock);

    while (referenceCountOffset > 0) {
        [retainedHandles addObject:aHandle];
        referenceCountOffset--;
    }
    while (referenceCountOffset < 0) {
        [retainedHandles removeObject:aHandle];
        referenceCountOffset++;
    }

    OFSimpleUnlock(&retainedHandlesLock);
}

- (unsigned)contentHashForHandle:(id)aHandle;
{
    NSDictionary *row;
    NSNumber *resultNumber;

    [dbLock lock];
    resultNumber = nil;
    NS_DURING {
        row = [self _r_rowForId:aHandle];
        OBASSERT(row != nil);
        resultNumber = [row objectForKey:@"valuehash"];
    } NS_HANDLER {
        [dbLock unlock];
        if ([[localException name] isEqualToString:CorruptDatabaseException])
            [self _flushCache:nil];
        [localException raise];
    } NS_ENDHANDLER;
    [dbLock unlock];

    OBASSERT(resultNumber != nil);
    if (resultNumber == nil) // should only happen if row == nil, which should never actually happen
        return 0;
    else
        return [resultNumber unsignedIntValue];
}

- (id <OWConcreteCacheEntry>)contentForHandle:(id)aHandle;
{
    NSAutoreleasePool *pool;
    id <OWConcreteCacheEntry> result = nil;

    pool = [[NSAutoreleasePool alloc] init];
    [dbLock lock];
    NS_DURING {
        NSDictionary *row = [self _r_rowForId:aHandle];

        if (row == nil)  // should never actually happen
            NS_VALUERETURN(nil, id);

        result = [self _r_concreteContentFromRow:row];
        time_t newAccessTime = time(NULL);
        [databaseController executeSQL:[NSString stringWithFormat:@"update Content set time = %u where content_id = %llu;\n", newAccessTime, [aHandle unsignedLongLongValue]] withCallback:NULL context:NULL];
    } NS_HANDLER {
        [pool release];
        [dbLock unlock];
        if ([[localException name] isEqualToString:CorruptDatabaseException])
            [self _flushCache:nil];
        [localException raise];
    } NS_ENDHANDLER;
    [pool release];
    [dbLock unlock];
    return [result autorelease];
}

- (OWContent *)storeContent:(OWContent *)someContent;
{
    id handle;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    [dbLock lock];
    handle = nil;
    NS_DURING {
        [databaseController beginTransaction];
        
        [self _reduceCacheSize];
        handle = [self _keyForContent:someContent insert:YES];
        [databaseController commitTransaction];
    } NS_HANDLER {
        [databaseController rollbackTransaction];
        [localException retain];
        [pool release];
        [localException autorelease];
        [dbLock unlock];
        if ([[localException name] isEqualToString:CorruptDatabaseException])
            [self _flushCache:nil];
        [localException raise];
    } NS_ENDHANDLER;
    [pool release];
    [dbLock unlock];
    if (handle)
        return someContent;
    else
        return nil;
}

- (NSArray *)_contentRowsForResource:(OWURL *)resourceIdentifier;
{
    OSLPreparedStatement *selectStatement = [databaseController prepareStatement:@"select content_id from URI where uri = ?;\n"];
    [selectStatement bindString:[[resourceIdentifier urlWithoutUsernamePasswordOrFragment] compositeString]];

    NSMutableArray *contentIds = [NSMutableArray array];
    NSDictionary *uriRow;
    while ((uriRow = [selectStatement step]) != nil) {
        [contentIds addObject:[uriRow objectForKey:@"content_id"]];
    }
    [selectStatement reset];

    NSMutableArray *contents = [[NSMutableArray alloc] initWithCapacity:[contentIds count]];
    [contents autorelease];
    OFForEachInArray(contentIds, NSNumber *, contentId, {
        [contents addObject:[self _r_rowForId:contentId]];
    });
        
    return contents;
}

- (void)invalidateResource:(OWURL *)resource beforeDate:(NSDate *)invalidationDate;
{
    if (invalidationDate == nil)
        invalidationDate = [NSDate date];

#ifdef DEBUG_wiml
    NSLog(@"%@ invalidation note: %@", [self shortDescription], [resource description]);
#endif

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [dbLock lock];

    NS_DURING {
        [databaseController beginTransaction];

        NSArray *addresses = [self _contentRowsForResource:resource];
    
#ifdef DEBUG_wiml
        NSLog(@"%@ deleting arcs from %d addresses", [self shortDescription], [addresses count]);
#endif
    
        // This is really the sledgehammer method. We should be cleverer than this! (i.e., pay attention to invalidationDate, and keep any resources that are re-validatable.)
        OFForEachInArray(addresses, NSDictionary *, addressRow, {
            [self _deleteContentRow:addressRow andReferences:YES];
        });

        [databaseController commitTransaction];
        [pool release];
        [dbLock unlock];
    } NS_HANDLER {
        BOOL shouldFlushCache = [[localException name] isEqualToString:CorruptDatabaseException];
#ifdef DEBUG
        NSLog(@"-[%@ %s]: transaction failed: %@", [self shortDescription], _cmd, localException);
#endif
        NS_DURING {
            [databaseController rollbackTransaction];
        } NS_HANDLER {
#ifdef DEBUG
            NSLog(@"-[%@ %s]: rollback failed: %@", [self shortDescription], _cmd, localException);
#endif
        } NS_ENDHANDLER;
        [pool release];  // blows away localException
        [dbLock unlock];
        if (shouldFlushCache)
            [self _flushCache:nil];
    } NS_ENDHANDLER;
}

- (void)removeEntriesDominatedByArc:(OWStaticArc *)newArc;
{
    NSArray *sourceIds;
    NSMutableDictionary *relatedArcs;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    [dbLock lock];

    NS_DURING {

        if ([[newArc subject] isAddress]) {
            OWURL *url = [[[newArc subject] address] url];
            NSArray *addresses = [self _contentRowsForResource:url];
            sourceIds = [addresses arrayByPerformingSelector:@selector(objectForKey:) withObject:@"content_id"];
        } else {
            NSNumber *sourceId = [self _keyForContent:[newArc source] insert:NO];
            sourceIds = [NSArray arrayWithObjects:sourceId, nil]; // sourceId may be nil
        }
    
#if defined(DEBUG_wiml) || defined(DEBUG_kc0)
        NSLog(@"%@ checking arcs for possible domination: source content ids %@", [self shortDescription], [sourceIds description]);
#endif
    
        relatedArcs = [[NSMutableDictionary alloc] init];
        [relatedArcs autorelease];
        
        OFForEachInArray(sourceIds, NSNumber *, sourceId, {
            OSLPreparedStatement *selectStatement = [databaseController prepareStatement:@"select * from Arc where source = ?;\n"];
            if (selectStatement == nil)
                continue;
    
            [selectStatement bindLongLongInt:[sourceId unsignedLongLongValue]];

            NSDictionary *arcRow;
            while ((arcRow = [selectStatement step]) != nil ) {
                OWStaticArc *anArc = [self _r_arcFromRow:arcRow];
                [relatedArcs setObject:anArc forKey:[arcRow objectForKey:@"arc_id"]];
                [anArc release];
            }
            [selectStatement reset];
        });

        [preenEvent invokeLater];
    
        OFForEachInArray([relatedArcs allKeys], OWStaticArc *, existingArcID, {
            if ([newArc dominatesArc:[relatedArcs objectForKey:existingArcID]])
                [arcsToRemove addObject:existingArcID];
#if 0
            else
                NSLog(@"%@ arc not dominated = %@", [self shortDescription], existingArcID);
#endif
        });
            
#if 0
        NSLog(@"%@ arcsToRemove = %@", [self shortDescription], [arcsToRemove description]);
#endif    

        [pool release];
        [dbLock unlock];
    } NS_HANDLER {
#ifdef DEBUG
        NSLog(@"-[%@ %s] - %@", [self shortDescription], _cmd, localException);
#endif
        [localException retain];
        [pool release];
        [localException autorelease];
        [dbLock unlock];
        if ([[localException name] isEqualToString:CorruptDatabaseException])
            [self _flushCache:nil];
    } NS_ENDHANDLER;
}

- (void)invalidateArc:(id <OWCacheArc>)arcToWriteBack;
{
    // TODO
}

@end


@implementation OWDiskCache (Private)

+ (BOOL)_initializeDatabase:(OSLDatabaseController *)newDB;
{
/* Database schema

    Table Content:
      content_id - OXKeyValue - content OID, used to refer to this content
      time - OXIntValue - time() at which this content was last accessed
      type - OXIntValue - content's concrete type, according to enum
      valuehash - OXIntValue - hash of the concrete content value
      size - OXIntValue - length of the concrete content value
      metadata - OWXPlistValue - content's metadata dictionary
      value - OXBinaryValue - content's (non meta-)data, serialized
      longvalue - OXBlobValue - blob, for larger contents
    
    Table URI:
      content_id - OXIntValue - OID of this content
      uri - OXStringValue - URI for indexing address content

    Table Arc:
      arc_id - OXKeyValue - arc OID
      subject, source, object - OXIntValue - content_ids of relevant content
      metadata - OXBinaryValue - arc information, serialized
    
*/

    [newDB executeSQL:
	@"PRAGMA synchronous = OFF;\n"
	@"PRAGMA temp_store = MEMORY;\n" 
	withCallback:NULL context:NULL];

    [newDB executeSQL:
	@"CREATE TABLE Content (content_id integer primary key, time integer, type integer, valuehash integer, size integer, metadata, value);\n"
	@"CREATE TABLE Arc (arc_id integer primary key, source integer, subject integer, object integer, metadata);\n"
	@"CREATE TABLE URI (content_id integer, uri);\n"

	@"CREATE INDEX Arc_source on Arc (source);\n" 
        @"CREATE INDEX Arc_subject on Arc (subject);\n"
        @"CREATE INDEX Arc_object on Arc (object);\n"

	@"CREATE INDEX Content_time on content (time);\n" 
	@"CREATE INDEX Content_valuehash on content (valuehash);\n" 

	@"CREATE INDEX URI_content_id on URI (content_id);\n" 
	@"CREATE INDEX URI_uri on URI (uri);\n"

	withCallback:NULL context:NULL];

    return YES;
}

+ (NSString *)_indexFilenameForBundlePath:(NSString *)aBundlePath;
{
    NSString *contents = [aBundlePath stringByAppendingPathComponent:@"Contents"];
    NSString *dataDir = [contents stringByAppendingPathComponent:@"Data"];
    NSString *indexFile = [dataDir stringByAppendingPathComponent:@"Index.db"];
    return indexFile;
}

- (NSString *)_indexFilename;
{
    return [isa _indexFilenameForBundlePath:bundlePath];
}

- _initWithDatabaseController:(OSLDatabaseController *)aDatabaseController bundle:(NSString *)aBundlePath;
{
#ifdef DEBUG_kc
    NSLog(@"-[%@ %s]: aDatabaseController = %@", OBShortObjectDescription(self), _cmd, aDatabaseController);
#endif

    if ([super init] == nil)
        return nil;

    databaseController = [aDatabaseController retain];
    bundlePath = [aBundlePath copy];
    NSZone *thisZone = [self zone];
    retainedHandles = [[NSCountedSet allocWithZone:thisZone] init];
    recentlyUsedContent = [[NSMutableArray allocWithZone:thisZone] init];
    arcsToRemove = [[NSMutableSet alloc] init];
    contentToGC = [[NSMutableSet alloc] init];
    dbLock = [[NSLock alloc] init];
    preenEvent = [[OFDelayedEvent alloc] initWithInvocation:[[[OFInvocation alloc] initForObject:self selector:@selector(_preenCache)] autorelease] delayInterval:0.5 scheduler:[OWContentCacheGroup scheduler] fireOnTermination:NO];

    [[OFController sharedController] addObserver:(id)self];
    [OWContentCacheGroup addContentCacheObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_flushCache:) name:OWContentCacheFlushNotification object:nil];

    return self;
}

- (NSNumber *)_keyForContent:(OWContent *)someContent insert:(BOOL)shouldInsert;
{
    enum OWDiskCacheConcreteContentType enumType = concreteTypeOfContent(someContent);

    if (enumType == OWDiskCacheUnknownConcreteType)
        return nil;

    if (![someContent endOfData] || ![someContent endOfHeaders])
        return nil;

    unsigned recentlyUsedContentCount = [recentlyUsedContent count];
    unsigned recentlyUsedContentIndex;
    for (recentlyUsedContentIndex = recentlyUsedContentCount; recentlyUsedContentIndex > 0; recentlyUsedContentIndex --) {
        OWContent *possible = [recentlyUsedContent objectAtIndex:recentlyUsedContentIndex - 1];
        if ([possible isEqual:someContent]) {
            if (recentlyUsedContentIndex != recentlyUsedContentCount) {
                // Move-to-front.
                [recentlyUsedContent addObject:possible];
                [recentlyUsedContent removeObjectAtIndex:(recentlyUsedContentIndex - 1)];
            }
            return [possible handleForCache:self];
        }
    }

    if (recentlyUsedContentCount >= LRUContentHighWater)
        [recentlyUsedContent removeObjectsInRange:(NSRange){0, recentlyUsedContentCount - LRUContentLowWater}];

    unsigned int valueHash = [someContent contentHash];
    
    OSLPreparedStatement *selectStatement = [databaseController prepareStatement:@"select * from Content where valuehash = ?;\n"];
    [selectStatement bindInt:valueHash];

    NSDictionary *row;
    while ((row = [selectStatement step]) != nil ) {
        BOOL match = YES;
        NSNumber *cid = nil;

        if ([(NSNumber *)[row objectForKey:@"type"] unsignedIntValue] != enumType)
            match = NO;

        if (match) {
            OWContent *possibility = [self _contentFromRow:row];
            if (!possibility || ![possibility isEqual:someContent])
                match = NO;
            else {
                cid = (id)[row objectForKey:@"content_id"];
            }
        }

        if (match)
            return cid;
    }

    if (shouldInsert) {
        NSNumber *cid;
        NSDictionary *meta;
        NSData *contentValue;
        int contentLength;
        OWDataStream *stream;


        switch(enumType) {
            case OWDiskCacheAddressConcreteType:
                contentValue = [NSKeyedArchiver archivedDataWithRootObject:[someContent address]];
                break;
            case OWDiskCacheBytesConcreteType:
                // We do this rather than ask for the -dataCursor so that we get the compressed version if any
                stream = [someContent objectValue];
                contentValue = [[stream createCursor] readAllData];
                break;
            case OWDiskCacheExceptionConcreteType:
#ifdef DEBUG_kc0
                NSLog(@"Archiving exception content: %@", [someContent objectValue]);
#endif
                contentValue = [NSKeyedArchiver archivedDataWithRootObject:[someContent objectValue]];
                break;
            default:
                return nil; // can't store other kinds of content
        }
        contentLength = [contentValue length];
#ifdef DEBUG_toon0
            NSLog(@"Inserted %d byte content. %d total content size", contentLength, totalContentSize);
#endif                
        meta = [someContent headersAsPropertyList];
        if ([meta count] == 0)
            meta = nil;
        
	// CREATE TABLE Content (content_id integer primary key, time integer, type integer, valuehash integer, size integer, metadata, value);
        OSLPreparedStatement *insertStatement = [databaseController prepareStatement:@"insert into Content values (?, ?, ?, ?, ?, ?, ?);"];
        
        [insertStatement bindNull]; // content_id
        [insertStatement bindInt:time(NULL)]; // time
        [insertStatement bindInt:enumType]; // type
        [insertStatement bindInt:valueHash]; // valuehash
        [insertStatement bindInt:contentLength]; // size
        [insertStatement bindPropertyList:meta]; // metadata
        [insertStatement bindBlob:contentValue]; // value
        [insertStatement step];
        [insertStatement reset];

        cid = [[NSNumber alloc] initWithUnsignedLongLong:[databaseController lastInsertRowID]];

#ifdef DEBUG_wiml
        NSLog(@"Inserted obj handle=%@ ct=%d vh=%u", cid, enumType, valueHash);
#endif
        OBASSERT(![contentToGC containsObject:cid]);

        if (enumType == OWDiskCacheAddressConcreteType) {
            OWURL *resourceIdentifier = [[[someContent address] url] urlWithoutUsernamePasswordOrFragment];

            // CREATE TABLE URI (content_id integer, uri);
            OSLPreparedStatement *insertStatement = [databaseController prepareStatement:@"insert into URI values (?, ?);"];
            
            [insertStatement bindLongLongInt:[cid unsignedLongLongValue]]; // content_id
            [insertStatement bindString:[resourceIdentifier compositeString]]; // uri
            [insertStatement step];
            [insertStatement reset];
        }

        [someContent useHandle:cid forCache:self];
        [recentlyUsedContent addObject:someContent];

        return [cid autorelease];
    }

    return nil;
}

- (OWContent *)_contentForKey:(NSNumber *)contentID;
{
    OBPRECONDITION(contentID != nil);
    
    OFForEachInArray(recentlyUsedContent, OWContent *, someContent, {
        if ([contentID isEqual:[someContent handleForCache:self]])
            return someContent;
    });
    
    return [self _contentFromRow:[self _r_rowForId:contentID]];
}

- (id <OWConcreteCacheEntry>)_r_concreteContentFromRow:(NSDictionary *)row;
{
    enum OWDiskCacheConcreteContentType rowType = [(NSNumber *)[row objectForKey:@"type"] intValue];

    id storedConcreteValue = [row objectForKey:@"value"];
    NSData *rowData;
    if (storedConcreteValue == nil) {
        rowData = [NSData data];
    } else {
        OBASSERT([storedConcreteValue isKindOfClass:[NSData class]]);
        rowData = (NSData *)storedConcreteValue;
    }
    
    switch (rowType) {
        case OWDiskCacheAddressConcreteType:
        case OWDiskCacheExceptionConcreteType:
        {
#ifdef DEBUG_kc0
            NSLog(@"Unarchiving disk cache row: %@", row );
#endif
            NSObject *rowEntry = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
#ifdef DEBUG_kc0
            NSLog(@"Unarchived disk cache row: %@ -> %@", row, rowEntry);
#endif
            return [rowEntry retain];
        }

        case OWDiskCacheBytesConcreteType:
        {
            OWDataStream *dataStream = [[OWDataStream alloc] initWithLength:[rowData length]];
            [dataStream writeData:rowData];
            [dataStream dataEnd];
            return dataStream;
        }

        default:
            return nil;
    }
}

- (NSDictionary *)_r_rowForId:(id)aHandle;
{
    OBPRECONDITION([aHandle isKindOfClass:[NSNumber class]]);

    OSLPreparedStatement *selectStatement = [databaseController prepareStatement:@"select * from Content where content_id = ?;\n"];
    [selectStatement bindLongLongInt:[aHandle unsignedLongLongValue]];
    NSDictionary *row = [selectStatement step];
    [selectStatement reset];
    return row;
}

- (OWContent *)_contentFromRow:(NSDictionary *)row;
{
    if (row == nil)
        return nil;

    NSObject *contentHandle = [row objectForKey:@"content_id"];
    id <OWConcreteCacheEntry> innerContent = [self _r_concreteContentFromRow:row];
    OWContent *result = [[OWContent alloc] initWithContent:innerContent];
    [innerContent release];
    [result useHandle:contentHandle forCache:self];
    
    NSData *headerData = [row objectForKey:@"headerData"];
    if (headerData != nil) {
        CFStringRef errorString = NULL;
        CFPropertyListRef parsedHeaders = CFPropertyListCreateFromXMLData(kCFAllocatorDefault, (CFDataRef)headerData, kCFPropertyListImmutable, &errorString);
        if (parsedHeaders != nil) {
            [result addHeadersFromPropertyList:(id)parsedHeaders];
        } else {
#ifdef DEBUG
            NSLog(@"-[%@ %s]: Failed to parse header data: %@; headerData=%@", errorString, headerData);
#endif
        }
    }
    [result markEndOfHeaders];

    OBASSERT([result contentHash] == [(NSNumber *)[row objectForKey:@"valuehash"] unsignedIntValue]);

    [recentlyUsedContent addObject:result];

    [result autorelease];
    return result;
}

- (void)_pullArcsIntoMutableArray:(NSMutableArray *)targetArray contentId:(NSNumber *)contentId column:(NSString *)columnName;
{
    // TODO: Use an 'Or' qualifier of some sort here instead of making three scans and merging them. (Actually, we almost never do more than one column, so this isn't actually too inefficient.)

    OSLPreparedStatement *selectStatement = [databaseController prepareStatement:[NSString stringWithFormat:@"select * from Arc where %@ = ?;\n", columnName]];
    if (selectStatement == nil)
        return;

    [selectStatement bindLongLongInt:[contentId unsignedLongLongValue]];

    NSDictionary *row;
    while ((row = [selectStatement step]) != nil ) {
        if ([arcsToRemove containsObject:[row objectForKey:@"arc_id"]])
            continue;

        OWStaticArc *anArc = [self _r_arcFromRow:row];
        [targetArray addObject:anArc];
#ifdef DEBUG_kc
        NSLog(@"%@ pulled arc %@  ->  %@", [self shortDescription], [row objectForKey:@"arc_id"], anArc);
#endif
        [anArc release];
    }
    [selectStatement reset];
}

- (OWStaticArc *)_r_arcFromRow:(NSDictionary *)row;
{
    struct OWStaticArcInitialization i;
    OWStaticArc *newArc;
    NSObject *subjectKey, *sourceKey, *objectKey;

    bzero(&i, sizeof(i));

    if (![OWStaticArc deserializeProperties:&i fromBuffer:(NSData *)[row objectForKey:@"metadata"]])
        return nil;

    subjectKey = [row objectForKey:@"subject"];
    sourceKey = [row objectForKey:@"source"];
    objectKey = [row objectForKey:@"object"];
    i.subject = [self _contentForKey:(NSNumber *)subjectKey];
    i.source  = [self _contentForKey:(NSNumber *)sourceKey];
    i.object  = [self _contentForKey:(NSNumber *)objectKey];

    newArc = [[OWStaticArc alloc] initWithArcInitializationProperties:i];

    [contentToGC removeObject:subjectKey];
    [contentToGC removeObject:sourceKey];
    [contentToGC removeObject:objectKey];

    return newArc;  /* preretained */
}

static enum OWDiskCacheConcreteContentType concreteTypeOfContent(OWContent *content)
{
    if ([content isAddress])
        return OWDiskCacheAddressConcreteType;
    else if ([content isDataStream])
        return OWDiskCacheBytesConcreteType;
    else {
        id <OWConcreteCacheEntry> concreteContent = [content objectValue];
        if ([concreteContent isKindOfClass:[NSException class]])
            return OWDiskCacheExceptionConcreteType;
    }

    return OWDiskCacheUnknownConcreteType;
}

// Called when the app is about to exit
- (void)controllerWillTerminate:(OFController *)controller;
{
    [self close];
}

- (void)_flushCache:(NSNotification *)note;
{
    BOOL removeAll;
    NSAutoreleasePool *pool;

#ifdef DEBUG_wiml
    NSLog(@"Flushing cache: %@", note);
#endif

    removeAll = [OWContentCacheFlush_Remove isEqual:[[note userInfo] objectForKey:OWContentCacheInvalidateOrRemoveNotificationInfoKey]];

    OFLockRegion_Begin(dbLock);

    if (removeAll || note == nil) {
        NSString *indexFile;
        NSFileManager *fileManager;

        pool = [[NSAutoreleasePool alloc] init];
        [recentlyUsedContent removeAllObjects];
        [arcsToRemove removeAllObjects];
        [contentToGC removeAllObjects];
        [self _lockedCancelPreenEvent];
        
        [databaseController release];
        databaseController = nil;

        [pool release];

        OFSimpleLock(&retainedHandlesLock);
#ifdef DEBUG
        unsigned int count = [retainedHandles count];
#endif
        [retainedHandles removeAllObjects];
        OFSimpleUnlock(&retainedHandlesLock);
#ifdef DEBUG
        if (count > 0) {
            NSLog(@"Warning, %d dangling handles when flushing disk cache.", count);
        }
#endif

        pool = [[NSAutoreleasePool alloc] init];

        indexFile = [self _indexFilename];
        
        fileManager = [NSFileManager defaultManager];
        [fileManager removeFileAtPath:indexFile handler:nil];
        [fileManager removeFileAtPath:[indexFile stringByAppendingPathExtension:@"log"] handler:nil];

        databaseController = [[OSLDatabaseController alloc] initWithDatabasePath:indexFile];
        if (databaseController == nil || ![isa _initializeDatabase:databaseController]) {
            [databaseController deleteDatabase];
            [databaseController release];
            databaseController = nil;
            NSLog(@"OWDiskCache: Unable to initialize disk cache database %@", indexFile);
            /* ... ??? ... */
        }

        [pool release];
        
    } else {
#ifdef DEBUG
        NSLog(@"-[%@ %s]: don't understand notification %@", OBShortObjectDescription(self), _cmd, note);
#endif
    }

    OFLockRegion_End(dbLock);
}

- (int)_deleteContentRow:(NSDictionary *)contentRow andReferences:(BOOL)mayHaveReferences
{

    if (contentRow == nil)
        return NO;
    NSNumber *cid = [contentRow objectForKey:@"content_id"];
    if (cid == nil)
        return NO;

    if (mayHaveReferences) {
        // select arc_id from Arc where subject = ? or object = ? or source = ?
        OSLPreparedStatement *selectStatement = [databaseController prepareStatement:@"select arc_id from Arc where source = ?;\n"];
        [selectStatement bindLongLongInt:[cid unsignedLongLongValue]];

        NSDictionary *arcRow;
        while ((arcRow = [selectStatement step]) != nil ) {
            [arcsToRemove addObject:[arcRow objectForKey:@"arc_id"]];
        }
        [selectStatement reset];

        // We have to go ahead and delete these now, or else we'll end up re-inserting our content_id into contentToGC when we do delete these arcs. It turns out that (in OX) if we do a select on a 'key' column, we can get a tuple even if it's already been deleted, and deleting it twice causes badness to happen.  (This is presumably no longer true now that we're using sqlite.)
        [self _deletePendingArcs];
    }

    [contentToGC removeObject:cid];

    [databaseController executeSQL:
        [NSString stringWithFormat:@"delete from URI where content_id = %llu;\n", [cid unsignedLongLongValue]]
                      withCallback:NULL context:NULL];

    [databaseController executeSQL:
        [NSString stringWithFormat:@"delete from Content where content_id = %llu;\n", [cid unsignedLongLongValue]]
                      withCallback:NULL context:NULL];

    return YES;
}

- (void)_deletePendingArcs;
{
    while ([arcsToRemove count]) {
        NSNumber *anArcId = [arcsToRemove anyObject];
        [self _deleteArcID:anArcId];
        [arcsToRemove removeObject:anArcId];
    }
}

- (void)_deleteArcID:(NSNumber *)anArcId;
{
#ifdef DEBUG_kc
    NSLog(@"%@ deleting arc id=%@", [self shortDescription], anArcId);
#endif

    OSLPreparedStatement *selectStatement = [databaseController prepareStatement:@"select * from Arc where arc_id = ?;\n"];
    [selectStatement bindLongLongInt:[anArcId unsignedLongLongValue]];
    NSDictionary *row = [selectStatement step];
    [selectStatement reset];
    if (row == nil)
        return;

    [contentToGC addObject:[row objectForKey:@"source"]];
    [contentToGC addObject:[row objectForKey:@"subject"]];
    [contentToGC addObject:[row objectForKey:@"object"]];

    [databaseController executeSQL:
        [NSString stringWithFormat:@"delete from Arc where arc_id = %llu;\n", [anArcId unsignedLongLongValue]]
                      withCallback:NULL context:NULL];
}

- (void)_deleteUnreferencedContent
{
    if ([contentToGC count] == 0)
        return;

#ifdef DEBUG_kc0
    NSLog(@"%@ before: contentToGC=%@", [self shortDescription], [contentToGC description]);
#endif

    /* Remove any content IDs from contentToGC if there is an arc referring to them */
    OSLPreparedStatement *selectStatement = [databaseController prepareStatement:@"select * from Arc;\n"];
    unsigned int rowCount = 0;
    NSDictionary *arcRow;
    while ((arcRow = [selectStatement step]) != nil ) {
        rowCount++;
        [contentToGC removeObject:[arcRow objectForKey:@"source"]];
        [contentToGC removeObject:[arcRow objectForKey:@"subject"]];
        [contentToGC removeObject:[arcRow objectForKey:@"object"]];
        if ([contentToGC count] == 0)
            break;
    }
    [selectStatement reset];

#if defined(DEBUG_wiml) || defined(DEBUG_kc0)
    NSLog(@"%@ after: %u arcs, contentToGC=%@", [self shortDescription], rowCount, [contentToGC description]);
#endif

#if 0
    // Check that the content we're about to delete actually exists
    {
        NSMutableSet *cts = [contentToGC mutableCopy];
        OXSQLCommand *cQuery = [db parseSQLCommand:@"select content_id from Content"];
        unsigned int rowCount;
        OSLPreparedStatement *selectStatement = [cQuery nextResultSetInDatabase:db rowCount:&rowCount];
        NSDictionary *cRow;
        while ( (cRow = [selectStatement nextRow]) != nil ) {
            [cts removeObject:[cRow objectForKey:@"content_id"]];
        }

        OBASSERT([cts count] == 0);
        [cts release];
    }
#endif

    while ([contentToGC count]) {
        NSNumber *contentId = [contentToGC anyObject];
        NSDictionary *contentRow = [self _r_rowForId:contentId];
        [contentToGC removeObject:contentId];

        if (contentRow != nil)
            [self _deleteContentRow:contentRow andReferences:NO];
    }
}

- (int)_deleteOldestContent;
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    OSLPreparedStatement *selectStatement = [databaseController prepareStatement:@"select * from Content order by time limit 1;\n"];
    NSDictionary *oldestRow = [selectStatement step];
    [selectStatement reset];

    if (oldestRow == nil)
        return 0;
    
    int sizeRemoved = [[oldestRow objectForKey:@"size"] intValue];
    BOOL didRemove = [self _deleteContentRow:oldestRow andReferences:YES];
    [pool release];

    return didRemove ? sizeRemoved : 0;
}

- (unsigned long long int)_totalContentSize;
{
    return 0ULL; // TODO: Write a select statement which calculates this size
}

- (void)_reduceCacheSize;
{
    // guess at about 70% efficiency so only 700,000 content bytes per megabyte of disk cache limit
    unsigned long long int desiredTotalContentSize = [[NSUserDefaults standardUserDefaults] integerForKey:@"OWDiskCacheLimit"] * 700000ULL;
    unsigned long long int totalContentSize = [self _totalContentSize];
    if (totalContentSize < desiredTotalContentSize)
        return;
    
    [self _deleteUnreferencedContent];
    
    while (totalContentSize > desiredTotalContentSize) {
        int removed = [self _deleteOldestContent];
        if (!removed)
            break;
#ifdef DEBUG_toon0
        NSLog(@"Removed %d byte content. %d total size remaining", removed, totalContentSize);
#endif
        [self _deletePendingArcs];
        [self _deleteUnreferencedContent];
    }
}

- (void)_lockedCancelPreenEvent;
{
    [preenEvent cancelIfPending];
    [preenEvent release];
    preenEvent = nil;
}

- (void)_preenCache;
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    [dbLock lock];

    NS_DURING {
        [databaseController beginTransaction];
        [self _deletePendingArcs];
        [databaseController commitTransaction];
        
        [self _deleteUnreferencedContent];
    } NS_HANDLER {
#ifdef DEBUG
        NSLog(@"-[%@ %s]: %@", [self shortDescription], _cmd, localException);
#endif
        [pool release];
        [dbLock unlock];
        return;
    } NS_ENDHANDLER;
    [pool release];
    [dbLock unlock];
}

OFWeakRetainConcreteImplementation_NULL_IMPLEMENTATION

@end
