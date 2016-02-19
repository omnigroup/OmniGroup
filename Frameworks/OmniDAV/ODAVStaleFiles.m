// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

OB_REQUIRE_ARC

#import <OmniDAV/ODAVStaleFiles.h>
	
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniDAV/ODAVFileInfo.h>

RCS_ID("$Id$")

// Preference where we remember what we've seen
#define ODAVStaleFilesPreferenceKey @"StaleFiles"

// Keys in an individual file entry dictionary
#define ODAVStaleFileETag                @"etag"  // The file's ETag, optional
#define ODAVStaleFileSize                @"size"  // The file's size
#define ODAVStaleFileMTime               @"mtime" // The file's modification time as given by the server
#define ODAVStaleFileLastCountedLocal    @"cl"    // The last time we incremented "n", according to our clock
#define ODAVStaleFileLastCountedRemote   @"cs"    // The last time we incremented "n", according to the server's clock
#define ODAVStaleFileCount               @"n"     // The number of times we've seen this file

// Per-identifier metadata key: must not collide with a filename
#define ODAVStaleFileGroupMetadataKey @""  /* yes, empty string, because no file has this name */

// Pile metadata
#define ODAVStaleFileGroupLastChecked @"checked"
#define ODAVStaleFileGroupFirstChecked @"created"

// Tuneable parameters
#define ODAVStaleFileGroupAgeFuzz (3 * 60 * 60)       // 3 hours: allowable imprecision in ODAVStaleFileGroupLastChecked; avoids gratuitous prefs rewrites
#define ODAVStaleFileGroupMaxAge (45 * 24 * 60 * 60)  // 45 days: if we don't look at a directory for this long, forget any deletions-in-progress

@implementation ODAVStaleFiles
{
    NSString *identifier;                 // Unique identifier, e.g. the URL of the directory
    NSRegularExpression *pattern;         // Optional pattern to restrict files of interest
    NSTimeInterval againInterval;         // Necessary duration between sightings to count as a new sighting
    unsigned int deletionTriggerCount;    // Number of sightings before we delete something
    BOOL deleteDirectories;               // Whether we even consider deleting directories
}

- (instancetype)init
{
    OBRejectUnusedImplementation(self, _cmd);
    return [self initWithIdentifier:@""];
}

- (instancetype __nullable)initWithIdentifier:(NSString *)ident
{
    if (!(self = [super init]))
        return nil;
    
    identifier = ident;
    againInterval = 20 * 60 * 60;   // about a day
    deletionTriggerCount = 7;
    deleteDirectories = NO;
    
    return self;
}

@synthesize identifier;
@synthesize pattern;

- (void)_store:(NSDictionary * __nullable)newPile
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *stored = [d objectForKey:ODAVStaleFilesPreferenceKey];
    NSDictionary *old = [stored objectForKey:identifier];
    NSDictionary *updated;
    if (!old) {
        if (!newPile)
            return;
        updated = [NSDictionary dictionaryWithObject:newPile forKey:identifier];
    } else {
        /* While we're updating it, let's expire any meta-entries (groups we haven't looked at in a long time) */
        NSMutableDictionary *tmp = [NSMutableDictionary dictionary];
        for(NSString *k in stored) {
            if([k isEqualToString:identifier])
                continue;
            NSDictionary *oldPile = [stored objectForKey:k];
            NSDate *oldTouched = [[oldPile objectForKey:ODAVStaleFileGroupMetadataKey] objectForKey:ODAVStaleFileGroupLastChecked];
            if (oldTouched && [oldTouched timeIntervalSinceNow] < ( -1 * ODAVStaleFileGroupMaxAge ))
                continue;
            [tmp setObject:oldPile forKey:k];
        }
        if (newPile)
            [tmp setObject:newPile forKey:identifier];
        updated = tmp;
    }
    
    if (updated && [updated count]) {
        [d setObject:updated forKey:ODAVStaleFilesPreferenceKey];
    } else {
        [d removeObjectForKey:ODAVStaleFilesPreferenceKey];
    }
}

static BOOL matches(NSDictionary *d, NSString *k, NSObject *v)
{
    NSObject *c = [d objectForKey:k];
    if (c == nil) {
        if (v == nil)
            return YES;
        return NO;
    } else {
        if (v == nil)
            return NO;
        return [c isEqual:v];
    }
}

- (NSArray <ODAVFileInfo *> *)examineDirectoryContents:(NSArray <ODAVFileInfo *> *)currentItems serverDate:(NSDate *)serverDate;
{
    /* Retrieve previous data - will often be nil */
    NSDictionary *previousEntries = [[[NSUserDefaults standardUserDefaults] objectForKey:ODAVStaleFilesPreferenceKey] objectForKey:identifier];
    
    /* Our updated version of the above, generated from the snapshot we're looking at */
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    
    /* And a list of things to tell our caller to delete */
    NSMutableArray *toDelete = [NSMutableArray array];
    
    NSDate *nowDate = [NSDate date];

    OFForEachObject([currentItems objectEnumerator], ODAVFileInfo *, finfo) {
        if (!finfo.exists)
            continue;
        
        if (!deleteDirectories && finfo.isDirectory)
            continue;
        
        NSString *resourceName = finfo.name;
        NSUInteger nameLength = [resourceName length];
        
        if (pattern) {
            NSRange matchRange = [pattern rangeOfFirstMatchInString:resourceName options:NSMatchingAnchored range:(NSRange){0, nameLength}];
            if (matchRange.location != 0 || matchRange.length != nameLength) {
                continue;
            }
        }
        
        if ([resourceName isEqualToString:ODAVStaleFileGroupMetadataKey]) {
            /* Shouldn't happen if we've chosen the metadata key well, but let's be sure */
            continue;
        }
        
        NSMutableDictionary *updatedEntry = [NSMutableDictionary dictionary];

        NSNumber *curSize;
        off_t fileSize = finfo.size;
        if (fileSize <= 0)
            curSize = nil;
        else
            curSize = [NSNumber numberWithUnsignedLongLong:(unsigned long long)fileSize];
        [updatedEntry setObject:curSize forKey:ODAVStaleFileSize defaultObject:nil];
        
        NSString *curETag = finfo.ETag;
        if (curETag && [curETag hasPrefix:@"W/"])
            curETag = nil;
        [updatedEntry setObject:curETag forKey:ODAVStaleFileETag defaultObject:nil];
        
        [updatedEntry setObject:finfo.lastModifiedDate forKey:ODAVStaleFileMTime defaultObject:nil];
        
        NSDictionary *previous = [previousEntries objectForKey:resourceName];
        
        if (previous) {
            NSString *oldETag = [previous objectForKey:ODAVStaleFileETag];
            if (oldETag && (!curETag || ![oldETag isEqualToString:curETag]))
                previous = nil;
        }
        if (previous && !matches(previous, ODAVStaleFileSize, curSize))
            previous = nil;
        if (previous && !matches(previous, ODAVStaleFileMTime, finfo.lastModifiedDate))
            previous = nil;
        
        unsigned seenCount;
        if (previous) {
            NSDate *lcLocal = [previous objectForKey:ODAVStaleFileLastCountedLocal];
            NSDate *lcRemote = [previous objectForKey:ODAVStaleFileLastCountedRemote];
            unsigned count = [previous unsignedIntForKey:ODAVStaleFileCount defaultValue:0];
            
            if ((!lcLocal || [lcLocal timeIntervalSinceNow] <= -1 * againInterval) &&
                (!lcRemote || !serverDate || [lcRemote timeIntervalSinceDate:serverDate] <= -1 * againInterval) ) {
                seenCount = count + 1;
                [updatedEntry setObject:nowDate forKey:ODAVStaleFileLastCountedLocal];
                [updatedEntry setObject:serverDate forKey:ODAVStaleFileLastCountedRemote defaultObject: (lcRemote? lcRemote : nil)];
            } else {
                seenCount = count;
                [updatedEntry setObject:lcLocal forKey:ODAVStaleFileLastCountedLocal defaultObject:nowDate];
                [updatedEntry setObject:lcRemote forKey:ODAVStaleFileLastCountedRemote defaultObject:nil];
            }
        } else {
            seenCount = 0;
        }
        
        [updatedEntry setUnsignedIntValue:seenCount forKey:ODAVStaleFileCount];
        
        [entries setObject:updatedEntry forKey:resourceName];
        
        if (seenCount >= deletionTriggerCount)
            [toDelete addObject:finfo];
    }
    
    /* Compute what to store back in prefs */
    BOOL mustStore;
    if (![entries count]) {
        /* Nothing to store. */
        entries = nil;
        mustStore = ( previousEntries == nil ? NO : YES );
    } else {
        /* Check whether the new value is the same as the old one (it often will be): don't rewrite prefs if the only thing that's changed is the timestamp and it hasn't changed much. */

        NSDictionary *previousMetadata = [previousEntries objectForKey:ODAVStaleFileGroupMetadataKey];
        NSDate *lastChecked = [previousMetadata objectForKey:ODAVStaleFileGroupLastChecked];
        if (!lastChecked || [nowDate timeIntervalSinceDate:lastChecked] > ODAVStaleFileGroupAgeFuzz) {
            /* Have to update the timestamp anyway, can't avoid a rewrite */
            mustStore = YES;
        } else {
            /* The same, aside from the metadata? */
            [entries setObject:previousMetadata forKey:ODAVStaleFileGroupMetadataKey];
            mustStore = ![entries isEqual:previousEntries];
        }
        
        if (mustStore) {
            NSMutableDictionary *newMetadata = [NSMutableDictionary dictionary];
            if (!previousEntries)
                [newMetadata setObject:nowDate forKey:ODAVStaleFileGroupFirstChecked];
            if (previousMetadata)
                [newMetadata addEntriesFromDictionary:previousMetadata];
            [newMetadata setObject:nowDate forKey:ODAVStaleFileGroupLastChecked];
            [entries setObject:newMetadata forKey:ODAVStaleFileGroupMetadataKey];
        }
    }
    
    if (mustStore)
        [self _store:entries];
    
    return toDelete;
}



@end
