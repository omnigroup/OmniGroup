// Copyright 2015-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

OB_REQUIRE_ARC

#import <OmniDAV/ODAVStaleFiles.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniDAV/ODAVFileInfo.h>

RCS_ID("$Id$")

/// Preference where we remember what we've seen.
///
/// Value is a dictionary mapping identifiers to a file info blob.
/// A file info blob is an array consisting of a first-checked date, last-checked date, and a fileInfos dictionary.
/// The fileInfos dictionary maps resourceNames to meta-date about the file (size, mod time, count of times seen, etc.)
NSString * const ODAVStaleFilesPreferenceKey = @"StaleFiles";

// Keys in an individual file entry dictionary
static NSString *ODAVStaleFileETag = @"etag";  // The file's ETag, optional
static NSString *ODAVStaleFileSize = @"size";  // The file's size
static NSString *ODAVStaleFileMTime = @"mtime"; // The file's modification time as given by the server
static NSString *ODAVStaleFileLastCountedLocal = @"cl";    // The last time we incremented "n", according to our clock
static NSString *ODAVStaleFileLastCountedRemote = @"cs";    // The last time we incremented "n", according to the server's clock
static NSString *ODAVStaleFileCount = @"n";     // The number of times we've seen this file

// Tuneable parameters
static NSTimeInterval ODAVStaleFileGroupMaxAge = (45 * 24 * 60 * 60);  // about 45 days: if we don't look at a directory for this long, forget any deletions-in-progress

/// Necessary duration between sightings to count as a new sighting
static NSTimeInterval AgainInterval = 4 * 60 * 60;   // about four hours

/// If user defaults map this key to a positive double value, that value is used for the AgainInterval
static NSString *ODAVStaleFilesCountAgainIntervalKey = @"ODAVStaleFilesCountAgainInterval";

/// Number of sightings before we delete something
static const NSUInteger DeletionTriggerCount = 7;

#pragma mark -
/// A helper object for tracking the info for a single file.
@interface ODAVStaleFileInfo : NSObject
+ (instancetype)infoFromPreferencesDictionary:(NSDictionary *)dictionary;
+ (BOOL)validatePreferencesDictionary:(NSDictionary *)dictionary;

@property (nonatomic) NSMutableDictionary *backingDictionary;
@property (nonatomic, readonly) id preferencesRepresentation;
@property (nonatomic) off_t fileSize;
@property (nonatomic) NSString *eTag;
@property (nonatomic) NSDate *lastModifiedDate;
@property (nonatomic) NSUInteger countOfTimesSeen;
@property (nonatomic) NSDate *localDateOfLastCounting;
@property (nonatomic) NSDate *serverDateOfLastCounting;

- (BOOL)isDistinctFromInfo:(ODAVStaleFileInfo *)otherInfo;
- (void)updateFromPreviousInfo:(ODAVStaleFileInfo *)otherInfo localDate:(NSDate *)localDate serverDate:(NSDate *)serverDate;
@end

#pragma mark -
/// A helper object for tracking the info for a single identifier.
@interface ODAVStaleFileInfosForIdentifier : NSObject
+ (instancetype)infosFromPreferencesArray:(NSArray *)array;
+ (BOOL)validatePreferencesArray:(NSArray *)array;

@property (nonatomic, nonnull) NSMutableDictionary *fileInfosDictionary;
@property (nonatomic, nonnull, readonly) id preferencesRepresentation;
@property (nonatomic, readonly) NSUInteger countOfInfos;
@property (nonatomic, nonnull) NSDate *firstCheckedDate;
@property (nonatomic, nonnull) NSDate *lastCheckedDate;

- (ODAVStaleFileInfo *)infoForResourceNamed:(NSString *)resourceName;
- (void)setInfo:(ODAVStaleFileInfo *)info forResourceNamed:(NSString *)resourceName;
@end

#pragma mark -
@interface ODAVStaleFiles ()
// Redeclare as readwrite
@property (nonatomic,readwrite,copy) NSString *identifier;

/// Whether we even consider deleting directories
@property (nonatomic) BOOL shouldDeleteDirectories;

@property (nonatomic) BOOL hasValidatedDefaultsFormat;
@end

#pragma mark -
@implementation ODAVStaleFiles

+ (void)initialize
{
    OBINITIALIZE;
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval customCountAgainInterval = [defaults doubleForKey:ODAVStaleFilesCountAgainIntervalKey];
    if (customCountAgainInterval > 0) {
        AgainInterval = customCountAgainInterval;
    }
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
    
    _identifier = ident;
     // We haven't done the engineering to test for stale directories yet. For example, what do modification dates and file sizes mean for directories on all the various DAV servers?  [They are not useful to us, according to the DAV spec: they can refer to a file that is unrelated to the directory contents.  -wim]
    _shouldDeleteDirectories = NO;
    
    return self;
}

- (NSArray <ODAVFileInfo *> *)examineDirectoryContents:(NSArray <ODAVFileInfo *> *)currentItems serverDate:(NSDate *)serverDate;
{
    NSDate *nowDate = [NSDate date];
    NSArray *result = [self examineDirectoryContents:currentItems localDate:nowDate serverDate:serverDate];
    return result;
}

#pragma mark Private API

- (id)_defaults
{
    id result = self.userDefaultsMock ?: [NSUserDefaults standardUserDefaults];
    return result;
}

- (void)_clearStoredPreferenceData
{
    [[self _defaults] removeObjectForKey:ODAVStaleFilesPreferenceKey];
}

/// Validates that the information stored in the preference is well-formed.
///
/// The format changed. Stale data can be thrown away without risk. So let's make sure the data is OK so we don't choke on it.
- (void)_validateStoredPreferenceData
{
    if (self.hasValidatedDefaultsFormat) {
        return;
    }
    
    self.hasValidatedDefaultsFormat = YES;
    
    BOOL isInvalid = NO;

    do { // using single turn do-loop so we can use `break` to skip subsequent checks on validation failure
        NSDictionary *allInfoByIdentifier = [[self _defaults] objectForKey:ODAVStaleFilesPreferenceKey];
        
        if (allInfoByIdentifier == nil) { // missing is OK
            break;
        }
        
        if (![allInfoByIdentifier isKindOfClass:[NSDictionary class]]) {
            isInvalid = YES;
            break;
        }
        
        for (NSArray *infosArrayForIdentifier in allInfoByIdentifier.allValues) {
            if (![ODAVStaleFileInfosForIdentifier validatePreferencesArray:infosArrayForIdentifier]) {
                isInvalid = YES;
                break;
            }
        }
    } while (0);
    
    if (isInvalid) {
        NSLog(@"Legacy format found for stored ODAVStaleFiles records. Clearing old data.");
        [self _clearStoredPreferenceData];
    }
}

- (ODAVStaleFileInfosForIdentifier *)_storedInfosForCurrentIdentifier
{
    [self _validateStoredPreferenceData];
    NSDictionary *allInfoByIdentifier = [[self _defaults] objectForKey:ODAVStaleFilesPreferenceKey];
    NSArray *arrayForCurrentIdentifier = allInfoByIdentifier[self.identifier];
    ODAVStaleFileInfosForIdentifier *result = [ODAVStaleFileInfosForIdentifier infosFromPreferencesArray:arrayForCurrentIdentifier];
    return result;
}

/// Reads the full set from preferences and ages out info for old identifiers.
- (NSDictionary *)_filteredStoredInfosForAllIdentifiersLocalDate:(NSDate *)localDate
{
    [self _validateStoredPreferenceData];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSDictionary *oldFileInfosForAllIdentifiers = [[self _defaults] objectForKey:ODAVStaleFilesPreferenceKey];

    for(NSString *identifier in oldFileInfosForAllIdentifiers) {
        NSArray *array = oldFileInfosForAllIdentifiers[identifier];
        ODAVStaleFileInfosForIdentifier *infos = [ODAVStaleFileInfosForIdentifier infosFromPreferencesArray:array];
        NSDate *lastChecked = infos.lastCheckedDate;
        OBASSERT(lastChecked != nil); // annotation says so, but clang isn't paying attention
        if ([lastChecked timeIntervalSinceDate:localDate] >= ( -1 * ODAVStaleFileGroupMaxAge )) {
            result[identifier] = infos.preferencesRepresentation;
        }
    }

    return result;
}

- (void)_updatePreferences:(ODAVStaleFileInfosForIdentifier *)fileInfos localDate:(NSDate *)localDate
{
    NSDictionary *oldFileInfosForAllIdentifiers = [self _filteredStoredInfosForAllIdentifiersLocalDate:localDate];
    
    NSMutableDictionary *newFileInfosForAllIdentifiers = [oldFileInfosForAllIdentifiers mutableCopy];
    newFileInfosForAllIdentifiers[self.identifier] = fileInfos.preferencesRepresentation;
    
    if (newFileInfosForAllIdentifiers.count > 0) {
        [[self _defaults] setObject:newFileInfosForAllIdentifiers forKey:ODAVStaleFilesPreferenceKey];
    } else {
        [[self _defaults] removeObjectForKey:ODAVStaleFilesPreferenceKey];
    }
}

#pragma mark Testing

- (NSArray <ODAVFileInfo *> *)examineDirectoryContents:(NSArray <ODAVFileInfo *> *)currentItems localDate:(NSDate *)localDate serverDate:(NSDate *)serverDate;
{
    /* Retrieve previous data - will often be nil */
    ODAVStaleFileInfosForIdentifier *previousInfos = [self _storedInfosForCurrentIdentifier];
    
    /* Our updated version of the above, generated from the snapshot we're looking at */
    ODAVStaleFileInfosForIdentifier *newInfos = [ODAVStaleFileInfosForIdentifier new];
    
    /* And a list of things to tell our caller to delete */
    NSMutableArray *toDelete = [NSMutableArray array];
    
    for (ODAVFileInfo *fileInfo in currentItems) {
        if (!fileInfo.exists)
            continue;
        
        if (!self.shouldDeleteDirectories && fileInfo.isDirectory)
            continue;
        
        NSString *resourceName = fileInfo.name;
        NSUInteger nameLength = [resourceName length];
        
        if (self.pattern) {
            NSRange matchRange = [self.pattern rangeOfFirstMatchInString:resourceName options:NSMatchingAnchored range:(NSRange){0, nameLength}];
            if (matchRange.location != 0 || matchRange.length != nameLength) {
                continue;
            }
        }
        
        ODAVStaleFileInfo *updatedEntry = [ODAVStaleFileInfo new];
        updatedEntry.fileSize = fileInfo.size;
        updatedEntry.eTag = fileInfo.ETag;
        updatedEntry.lastModifiedDate = fileInfo.lastModifiedDate;
        
        ODAVStaleFileInfo *previousEntry = [previousInfos infoForResourceNamed:resourceName];
        
        if ([updatedEntry isDistinctFromInfo:previousEntry]) {
            updatedEntry.countOfTimesSeen = 0;
            updatedEntry.localDateOfLastCounting = localDate;
            updatedEntry.serverDateOfLastCounting = serverDate;
        } else {
            // Not a distinct entry (i.e., seems to be untouched since we last recorded info about it), so update our existing info
            [updatedEntry updateFromPreviousInfo:previousEntry localDate:localDate serverDate:serverDate];
        }
        
        
        [newInfos setInfo:updatedEntry forResourceNamed:resourceName];
        
        if (updatedEntry.countOfTimesSeen >= DeletionTriggerCount) {
            [toDelete addObject:fileInfo];
        }
    }
    
    if (newInfos.countOfInfos == 0) {
        [self _updatePreferences:nil localDate:localDate];
    } else {
        newInfos.firstCheckedDate = previousInfos.firstCheckedDate ?: localDate;
        newInfos.lastCheckedDate = localDate;
        [self _updatePreferences:newInfos localDate:localDate];
    }
    
    return toDelete;
}

- (void)setUserDefaultsMock:(NSMutableDictionary *)userDefaultsMock
{
    if (userDefaultsMock == _userDefaultsMock) {
        return;
    }
    
    _userDefaultsMock = userDefaultsMock;
    self.hasValidatedDefaultsFormat = NO;
}

@end

#pragma mark -
@implementation ODAVStaleFileInfo

+ (instancetype)infoFromPreferencesDictionary:(NSDictionary *)dictionary;
{
    ODAVStaleFileInfo *result = [ODAVStaleFileInfo new];
    [result.backingDictionary addEntriesFromDictionary:dictionary];
    return result;
}

+ (BOOL)validatePreferencesDictionary:(NSDictionary *)dictionary;
{
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    BOOL(^nilOrType)(NSString *key, Class cls) = ^BOOL(NSString *key, Class cls) {
        id value = dictionary[key];
        return value == nil || [value isKindOfClass:cls];
    };
    
    BOOL isOK = (
                 nilOrType(ODAVStaleFileSize, [NSNumber class])
                 && nilOrType(ODAVStaleFileETag, [NSString class])
                 && nilOrType(ODAVStaleFileMTime, [NSDate class])
                 && nilOrType(ODAVStaleFileCount, [NSNumber class])
                 && nilOrType(ODAVStaleFileLastCountedLocal, [NSDate class])
                 && nilOrType(ODAVStaleFileLastCountedRemote, [NSDate class])
                 );
    
    return isOK;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _backingDictionary = [NSMutableDictionary new];
    }
    return self;
}

#pragma mark Property Covers

- (id)preferencesRepresentation
{
    return self.backingDictionary;
}

- (void)setFileSize:(off_t)fileSize
{
    NSNumber *sizeRef;
    if (fileSize <= 0) {
        sizeRef = nil;
    } else {
        sizeRef = @(fileSize);
    }
    
    self.backingDictionary[ODAVStaleFileSize] = sizeRef;
}

- (off_t)fileSize
{
    NSNumber *sizeRef = self.backingDictionary[ODAVStaleFileSize];
    return sizeRef.longLongValue;
}

- (void)setETag:(NSString *)eTag
{
    if (eTag != nil && [eTag hasPrefix:@"W/"]) {
        eTag = nil;
    }
    self.backingDictionary[ODAVStaleFileETag] = eTag;
}

- (NSString *)eTag
{
    return self.backingDictionary[ODAVStaleFileETag];
}

- (void)setLastModifiedDate:(NSDate *)lastModifiedDate
{
    self.backingDictionary[ODAVStaleFileMTime] = lastModifiedDate;
}

- (NSDate *)lastModifiedDate
{
    return self.backingDictionary[ODAVStaleFileMTime];
}

- (void)setCountOfTimesSeen:(NSUInteger)countOfTimesSeen
{
    self.backingDictionary[ODAVStaleFileCount] = @(countOfTimesSeen);
}

- (NSUInteger)countOfTimesSeen
{
    NSNumber *countRef = self.backingDictionary[ODAVStaleFileCount];
    return countRef.unsignedIntegerValue;
}

- (void)setLocalDateOfLastCounting:(NSDate *)localDateOfLastCounting
{
    self.backingDictionary[ODAVStaleFileLastCountedLocal] = localDateOfLastCounting;
}

- (NSDate *)localDateOfLastCounting
{
    return self.backingDictionary[ODAVStaleFileLastCountedLocal];
}

- (void)setServerDateOfLastCounting:(NSDate *)serverDateOfLastCounting
{
    self.backingDictionary[ODAVStaleFileLastCountedRemote] = serverDateOfLastCounting;
}

- (NSDate *)serverDateOfLastCounting
{
    return self.backingDictionary[ODAVStaleFileLastCountedRemote];
}

#pragma mark Operations

- (BOOL)isDistinctFromInfo:(ODAVStaleFileInfo *)otherInfo
{
    if (otherInfo == nil) {
        return YES;
    }
    
    if (!OFISEQUAL(self.eTag, otherInfo.eTag)) {
        return YES;
    }
    
    if (self.fileSize != otherInfo.fileSize) {
        return YES;
    }

    if (!OFISEQUAL(self.lastModifiedDate, otherInfo.lastModifiedDate)) {
        return YES;
    }
    
    return NO;
}

- (void)updateFromPreviousInfo:(ODAVStaleFileInfo *)otherInfo localDate:(NSDate *)localDate serverDate:(NSDate *)serverDate
{
    NSDate *lcLocal = otherInfo.localDateOfLastCounting;
    NSDate *lcRemote = otherInfo.serverDateOfLastCounting;
    NSUInteger count = otherInfo.countOfTimesSeen;
    
    BOOL timeToCountAgainBasedOnLocalClock = !lcLocal || [lcLocal timeIntervalSinceDate:localDate] <= -1 * AgainInterval;
    BOOL timeToCountAgainBasedOnServerClock = !lcRemote || !serverDate || [lcRemote timeIntervalSinceDate:serverDate] <= -1 * AgainInterval;
    if (timeToCountAgainBasedOnLocalClock && timeToCountAgainBasedOnServerClock) {
        count += 1;
        self.localDateOfLastCounting = localDate;
        self.serverDateOfLastCounting = serverDate ?: lcRemote;
    } else {
        self.localDateOfLastCounting = lcLocal ?: localDate;
        self.serverDateOfLastCounting = lcRemote;
    }

    self.countOfTimesSeen = count;
}

@end

#pragma mark -
@implementation ODAVStaleFileInfosForIdentifier
+ (instancetype)infosFromPreferencesArray:(NSArray *)array
{
    ODAVStaleFileInfosForIdentifier *result = [ODAVStaleFileInfosForIdentifier new];
    result.firstCheckedDate = array[0];
    result.lastCheckedDate = array[1];
    [result.fileInfosDictionary addEntriesFromDictionary:array[2]];
    return result;
}

+ (BOOL)validatePreferencesArray:(NSArray *)array;
{
    if (![array isKindOfClass:[NSArray class]] || array.count != 3) {
        return NO;
    }
    
    if (![array[0] isKindOfClass:[NSDate class]] || ![array[1] isKindOfClass:[NSDate class]]) {
        return NO;
    }
    
    NSDictionary *dict = array[2];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    
    for (NSDictionary *infoDict in dict.allValues) {
        if (![ODAVStaleFileInfo validatePreferencesDictionary:infoDict]) {
            return NO;
        }
    }
    
    return YES;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _fileInfosDictionary = [NSMutableDictionary new];
    }
    return self;
}

#pragma mark Property Covers

- (id)preferencesRepresentation
{
    NSArray *result = @[
                        self.firstCheckedDate,
                        self.lastCheckedDate,
                        self.fileInfosDictionary,
                        ];
    return result;
}

- (NSUInteger)countOfInfos
{
    return self.fileInfosDictionary.count;
}

#pragma mark Operations

- (ODAVStaleFileInfo *)infoForResourceNamed:(NSString *)resourceName
{
    NSDictionary *dict = self.fileInfosDictionary[resourceName];
    ODAVStaleFileInfo *result = [ODAVStaleFileInfo infoFromPreferencesDictionary:dict];
    return result;
}

- (void)setInfo:(ODAVStaleFileInfo *)info forResourceNamed:(NSString *)resourceName;
{
    self.fileInfosDictionary[resourceName] = info.preferencesRepresentation;
}

@end
