// Copyright 1997-2005, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWContentType.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContent.h>  // For OWContent{Type,Encoding}HeaderString
#import <OWF/OWContentTypeLink.h>
#import <OWF/OWConversionPathElement.h>
#import <OWF/OWUnknownDataStreamProcessor.h>

RCS_ID("$Id$")

@interface NSFileManager (UsedToBeInOmniFoundation)
- (int)getType:(unsigned long *)typeCode andCreator:(unsigned long *)creatorCode forPath:(NSString *)path;
@end

@implementation NSFileManager (UsedToBeInOmniFoundation)

typedef struct {
    long type;
    long creator;
    short flags;
    short locationV;
    short locationH;
    short fldr;
    short iconID;
    short unused[3];
    char script;
    char xFlags;
    short comment;
    long putAway;
} OFFinderInfo;

- (int)getType:(unsigned long *)typeCode andCreator:(unsigned long *)creatorCode forPath:(NSString *)path;
{
    struct attrlist attributeList;
    struct {
        long ssize;
        OFFinderInfo finderInfo;
    } attributeBuffer;
    int errorCode;
    
    attributeList.bitmapcount = ATTR_BIT_MAP_COUNT;
    attributeList.reserved = 0;
    attributeList.commonattr = ATTR_CMN_FNDRINFO;
    attributeList.volattr = attributeList.dirattr = attributeList.fileattr = attributeList.forkattr = 0;
    memset(&attributeBuffer, 0, sizeof(attributeBuffer));
    
    errorCode = getattrlist([self fileSystemRepresentationWithPath:path], &attributeList, &attributeBuffer, sizeof(attributeBuffer), 0);
    if (errorCode == -1) {
        switch (errno) {
            case EOPNOTSUPP: {
                BOOL isDirectory;
                NSString *ufsResourceForkPath;
                unsigned long aTypeCode, aCreatorCode;
                
                ufsResourceForkPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:[@"._" stringByAppendingString:[path lastPathComponent]]];
                if ([self fileExistsAtPath:ufsResourceForkPath isDirectory:&isDirectory] == YES && isDirectory == NO) {
                    NSData *resourceFork;
                    const unsigned int offsetOfTypeInResourceFork = 50;
                    
                    resourceFork = [NSData dataWithContentsOfMappedFile:ufsResourceForkPath];
                    if ([resourceFork length] < offsetOfTypeInResourceFork + sizeof(unsigned long) + sizeof(unsigned long))
                        return errorCode;
                    
                    [resourceFork getBytes:&aTypeCode range:NSMakeRange(offsetOfTypeInResourceFork, sizeof(aTypeCode))];
                    [resourceFork getBytes:&aCreatorCode range:NSMakeRange(offsetOfTypeInResourceFork + sizeof(aTypeCode), sizeof(aCreatorCode))];
                    *typeCode = NSSwapBigLongToHost(aTypeCode);
                    *creatorCode = NSSwapBigLongToHost(aCreatorCode);
                    return 0;
                } else {
                    *typeCode = 0; // We could use the Mac APIs, or just read the "._" file.
                    *creatorCode = 0;
                }
            }
            default:
                return errorCode;
        }
    } else {
        *typeCode = attributeBuffer.finderInfo.type;
        *creatorCode = attributeBuffer.finderInfo.creator;
    }
    
    return errorCode;
}

@end

@interface OWContentType (Private)
+ (void)controllerDidInitialize:(OFController *)controller;
+ (void)reloadExpirationTimeIntervals:(NSNotification *)notification;
+ (void)registerAliasesDictionary:(NSDictionary *)extensionsDictionary;
+ (void)registerExtensionsDictionary:(NSDictionary *)extensionsDictionary;
+ (OSType)osTypeForString:(NSString *)string;
+ (void)registerHFSTypesDictionary:(NSDictionary *)hfsTypesDictionary;
+ (void)registerHFSCreatorsDictionary:(NSDictionary *)hfsCreatorsDictionary;
+ (void)registerIconsDictionary:(NSDictionary *)iconsDictionary;
+ (void)registerFlagsDictionary:(NSDictionary *)iconsDictionary;
- _initWithContentTypeString:(NSString *)aString;
- (void)_addReverseContentType:(OWContentType *)sourceContentType;
- (void)_locked_flushConversionPaths;
- (OWConversionPathElement *)_locked_computeBestPathForType:(OWContentType *)targetType visitedTypes:(NSMutableSet *)visitedTypes recursionLevel:(unsigned int)recursionLevel;
@end

@implementation OWContentType

NSTimeInterval OWContentTypeNeverExpireTimeInterval = -1.0;
NSTimeInterval OWContentTypeExpireWhenFlushedTimeInterval = 1e+10;
NSString *OWContentTypeNeverExpireString = @"NeverExpire";
NSString *OWContentTypeExpireWhenFlushedString = @"ExpireWhenFlushed";
NSString *OWContentTypeReloadExpirationTimeIntervalsNotificationName = @"OWContentTypeReloadExpirationTimeIntervals";

static NSLock *contentTypeLock;
static NSMutableDictionary *contentTypeDictionary;
static NSMutableArray *contentEncodings;
static NSMutableDictionary *extensionToContentTypeDictionary;
static NSMutableDictionary *macOSTypeToContentTypeDictionary;
static NSMutableArray *replacedContentTypes;
static OWContentType *wildcardContentType;
static OWContentType *sourceContentType;
static OWContentType *retypedSourceContentType;
static OWContentType *unknownContentType;
static OWContentType *errorContentType;
static OWContentType *nothingContentType;
static NSTimeInterval defaultExpirationTimeInterval = 0.0;
static NSZone *zone;

// This is a hack.
static NSString *privateSupertypes[] = {
    @"documenttitle", @"omniaddress", @"objectstream", @"omni", @"owftpdirectory", @"owdatastream", @"timestamp", @"url", @"gopher", nil
};

+ (void)didLoad;
{
    [[OFController sharedController] addObserver:(id)self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadExpirationTimeIntervals:) name:OWContentTypeReloadExpirationTimeIntervalsNotificationName object:nil];
}

+ (void)initialize;
{
    OBINITIALIZE;

    zone = NSCreateZone(NSPageSize(), NSPageSize(), YES);
    contentTypeLock = [[NSRecursiveLock allocWithZone:zone] init];
    
    // Use our case-insensitive string key dictionary for these to avoid calling -lowercaseString
    contentTypeDictionary = OFCreateCaseInsensitiveKeyMutableDictionary();
    extensionToContentTypeDictionary = OFCreateCaseInsensitiveKeyMutableDictionary();
    macOSTypeToContentTypeDictionary = [[NSMutableDictionary allocWithZone:zone] init];
    replacedContentTypes = [[NSMutableArray alloc] init];
    
    contentEncodings = [[NSMutableArray allocWithZone:zone] initWithCapacity:5];

    wildcardContentType = [self contentTypeForString:@"*/*"];
    sourceContentType = [self contentTypeForString:@"omni/source"]; // a pseudo-type; no actual content will have this type, but targets an request it in order to receive content (of any type) whose producers have marked it as being "source" content.
    retypedSourceContentType = [self contentTypeForString:@"omni/retypedsource"];
    unknownContentType = [self contentTypeForString:@"www/unknown"];
    errorContentType = [OWContentType contentTypeForString:@"Omni/ErrorContent"];
    nothingContentType = [OWContentType contentTypeForString:@"Omni/NoContent"];
}

// Bundle registration

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
    if ([itemName isEqualToString:@"aliases"])
        [self registerAliasesDictionary:description];
    else if ([itemName isEqualToString:@"extensions"])
        [self registerExtensionsDictionary:description];
    else if ([itemName isEqualToString:@"hfsTypes"])
        [self registerHFSTypesDictionary:description];
    else if ([itemName isEqualToString:@"hfsCreators"])
        [self registerHFSCreatorsDictionary:description];
    else if ([itemName isEqualToString:@"icons"])
        [self registerIconsDictionary:description];
    else if ([itemName isEqualToString:@"guesses"])
        [OWUnknownDataStreamProcessor registerGuessesDictionary:description];
    else if ([itemName isEqualToString:@"flags"])
        [self registerFlagsDictionary:description];
}


// Defaults

#define ExpirationDefaultsKey @"OWContentTypeExpirationTimeIntervals"
#define ExpirationDefaultVersionKey @"_version_"
#define ExpirationDefaultVersionValue 2

+ (void)updateExpirationTimeIntervalsFromDefaults;
{
    NSDictionary *defaultsDictionary;
    NSEnumerator *contentTypeEnumerator;
    NSString *aContentTypeString;
    NSUserDefaults *defaults;
    NSNumber *version;

    defaults = [NSUserDefaults standardUserDefaults];
    defaultsDictionary = [defaults dictionaryForKey:ExpirationDefaultsKey];
    version = [defaultsDictionary objectForKey:ExpirationDefaultVersionKey];
    if (version == nil || [version intValue] != ExpirationDefaultVersionValue) {
        // We don't want old versions of this dictionary to override new ones.  If we were feeling especially clever, I guess we could apply the changes from the old to the new, but if we were really truly clever we'd just make a separate override dictionary where we stored the user's settings so we wouldn't have to store every setting when they just changed one.
        [defaults removeObjectForKey:ExpirationDefaultsKey];
        defaultsDictionary = [defaults dictionaryForKey:ExpirationDefaultsKey];
#ifdef OMNI_ASSERTIONS_ON
        version = [defaultsDictionary objectForKey:ExpirationDefaultVersionKey];
#endif
    }
    OBASSERT(version != nil && [version intValue] == ExpirationDefaultVersionValue); // If this ever fails, it's because our registered defaults are out of synch with this code (or this code is broken).

    contentTypeEnumerator = [defaultsDictionary keyEnumerator];
    while ((aContentTypeString = [contentTypeEnumerator nextObject])) {
        OWContentType *contentType;
        id expirationStringOrNumber;

        if ([aContentTypeString isEqualToString:ExpirationDefaultVersionKey])
            continue;
        contentType = [self contentTypeForString:aContentTypeString];
        expirationStringOrNumber = [defaultsDictionary objectForKey:aContentTypeString];
        if ([expirationStringOrNumber isEqual:OWContentTypeNeverExpireString])
            [contentType setExpirationTimeInterval:OWContentTypeNeverExpireTimeInterval];
        else if ([expirationStringOrNumber isEqual:OWContentTypeExpireWhenFlushedString])
            [contentType setExpirationTimeInterval:OWContentTypeExpireWhenFlushedTimeInterval];
        else
            [contentType setExpirationTimeInterval:[expirationStringOrNumber floatValue]];
    }
}

+ (OWContentType *)contentTypeForString:(NSString *)aString;
{
    OWContentType *contentType;
    
    if (!aString)
	return nil;

    [contentTypeLock lock];
    contentType = [contentTypeDictionary objectForKey:aString];
    if (!contentType) {
        // Go ahead and put lowercase strings in the content type and dictionary even though we want to avoid lowercasing during lookups.
        aString = [aString lowercaseString];
        OBASSERT([contentTypeDictionary objectForKey:aString] == nil); 
        contentType = [[self allocWithZone:zone] _initWithContentTypeString:aString];
	[contentTypeDictionary setObject:contentType forKey:aString];
        if ([contentType isEncoding])
            [contentEncodings addObject:contentType];
        [contentType autorelease];
    }
    [contentTypeLock unlock];

    return contentType;
}

+ (OWContentType *)contentEncodingForString:(NSString *)aString;
{
    if ([NSString isEmptyString:aString])
        return nil;
    else if ([aString hasPrefix:@"encoding/"])
        return [self contentTypeForString:aString];
    else
        return [self contentTypeForString:[@"encoding/" stringByAppendingString:aString]];
}

+ (OWContentType *)existingContentTypeForString:(NSString *)aString;
{
    OWContentType *contentType;

    if (!aString)
        return nil;

    [contentTypeLock lock];
    contentType = [contentTypeDictionary objectForKey:aString];
    [contentTypeLock unlock];

    return contentType;
}

+ (OWContentType *)wildcardContentType;
{
    return wildcardContentType;
}

+ (OWContentType *)sourceContentType;
{
    return sourceContentType;
}

+ (OWContentType *)retypedSourceContentType;
{
    return retypedSourceContentType;
}

+ (OWContentType *)unknownContentType;
{
    return unknownContentType;
}

+ (OWContentType *)errorContentType;
{
    return errorContentType;
}

+ (OWContentType *)nothingContentType;
{
    return nothingContentType;
}

/* TODO: This does not contain aliases! */
/* NB: Eventually, when we support type wildcarding in some reasonable way, this method will be unneeded because encodings will be returned by -indirectSourceContentTypes. Other code will have to change to check for encodings among those types, however. */
+ (NSArray *)contentEncodings
{
    return contentEncodings;
}

+ (NSArray *)contentTypes
{
    return [contentTypeDictionary allValues];
}

+ (void)setDefaultExpirationTimeInterval:(NSTimeInterval)newTimeInterval;
{
    defaultExpirationTimeInterval = newTimeInterval;
}

+ (OWContentTypeLink *)linkForTargetContentType:(OWContentType *)targetContentType fromContentType:(OWContentType *)sourceContentType orContentTypes:(NSSet *)sourceTypes;
{
    OWConversionPathElement *path;
    NSEnumerator *typeEnum;
    OWContentType *type;
    OWContentTypeLink *lastFound;
    
    // Check for the requested type first
    if ((path = [sourceContentType bestPathForTargetContentType: targetContentType]))
        goto got_path;
    
    typeEnum = [sourceTypes objectEnumerator];
    while ((type = [typeEnum nextObject])) {
        if ((path = [type bestPathForTargetContentType: targetContentType]))
            goto got_path;
    }
    
    // If we don't find anything under the requested type, check the wildcard type (the type that is returned when fetching source content that isn't typed yet)
    if ((path = [sourceContentType bestPathForTargetContentType: wildcardContentType]))
        goto got_path;
    
    typeEnum = [sourceTypes objectEnumerator];
    while ((type = [typeEnum nextObject])) {
        if ((path = [type bestPathForTargetContentType: wildcardContentType]))
            goto got_path;
    }
    
    // Didn't get anything
    return nil;
    
got_path:
    // Return the last link in the path for which we have content
    lastFound = [path link];
    while((path = [path nextElement])) {
        if ([sourceTypes member:[[path link] sourceContentType]])
            lastFound = [path link];
    }
    return lastFound;
}

+ (void)registerFileExtension:(NSString *)extension forContentType:(OWContentType *)contentType;
{
    NSString *key;
    OWContentType *oldContentType;
    NSArray *oldExtensions;
    NSMutableArray *newExtensions;

    if ([NSString isEmptyString:extension])
        return;

    [contentTypeLock lock];
    
    key = [[extension lowercaseString] copyWithZone:zone];
    if ((oldContentType = [extensionToContentTypeDictionary objectForKey:key])) {
        if (contentType != oldContentType) {
            NSLog(@"Overriding extension to content type mapping for extension '%@'.  Old mapping was %@, new mapping is %@.", extension, oldContentType, contentType);
        }
    }
    
    [extensionToContentTypeDictionary setObject:contentType forKey:key];

    oldExtensions = [contentType extensions];
    if (!oldExtensions || [oldExtensions indexOfObject:extension] == NSNotFound) {
        newExtensions = oldExtensions ? [oldExtensions mutableCopy] : [[NSMutableArray alloc] init];
        [newExtensions addObject:extension];
        [contentType setExtensions:newExtensions];
        [newExtensions release];
    }
    
    [key release];

    [contentTypeLock unlock];
}

+ (OWContentType *)contentTypeForExtension:(NSString *)extension;
{
    OWContentType *contentType;

    if (extension == nil)
	return nil;

    [contentTypeLock lock];
    contentType = [extensionToContentTypeDictionary objectForKey:extension];
    [contentTypeLock unlock];
    return contentType;
}

+ (OWContentType *)contentTypeForFilename:(NSString *)filename isLocalFile:(BOOL)isLocalFile;
{
    OWContentType *contentType;
    
    if (isLocalFile) {
        // Check HFS Mac OS Type code, since sometimes that does NOT match the filename extension (or the extension is missing).
        NSFileManager *fileManager;
        BOOL isDirectory;
        unsigned long typeCode, creatorCode;
    
        fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:filename isDirectory:&isDirectory] == YES && isDirectory == NO) {
            if ([fileManager getType:&typeCode andCreator:&creatorCode forPath:filename] != -1) {
                [contentTypeLock lock]; {
                    contentType = [macOSTypeToContentTypeDictionary objectForKey:[NSNumber numberWithUnsignedLong:typeCode]];
                } [contentTypeLock unlock];
                
                if (contentType != nil)
                    return contentType;
            }
        }
    }

    contentType = [self contentTypeForExtension:[filename pathExtension]];
    return contentType ? contentType : [OWUnknownDataStreamProcessor unknownContentType];
}

+ (OFMultiValueDictionary *)contentTypeAndEncodingForFilename:(NSString *)aFilename isLocalFile:(BOOL)isLocalFile;
{
    OWContentType *type;
    NSMutableArray *encodings;
    NSString *trimmedFilename;
    OFMultiValueDictionary *headers;

    type = [OWContentType contentTypeForFilename:aFilename isLocalFile:isLocalFile];

    encodings = [[NSMutableArray alloc] init];

    trimmedFilename = [aFilename lastPathComponent];
    while ([type isEncoding]) {
        [encodings insertObject:[type contentTypeString] atIndex:0];
        trimmedFilename = [trimmedFilename stringByDeletingPathExtension];
        type = [OWContentType contentTypeForFilename:trimmedFilename isLocalFile:NO];
    }

    headers = [[OFMultiValueDictionary alloc] initWithCaseInsensitiveKeys:YES];
    [headers autorelease];
    if (type != nil && type != [OWUnknownDataStreamProcessor unknownContentType])
        [headers addObject:[type contentTypeString] forKey:OWContentTypeHeaderString];
    if ([encodings count])
        [headers addObjects:encodings forKey:OWContentEncodingHeaderString];
    [encodings release];
    
    return headers;
}


// Instance methods

// Make sure no shenanigans go on

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (id)retain;
{
    return self;
}

- (id)autorelease;
{
    return self;
}

- (void)release;
{
}

- (void)dealloc;
{
    OBASSERT_NOT_REACHED("Who be deallocing me?");
    if(0)
        [super dealloc];
}


// Coding support

- initWithCoder:(NSCoder *)archiver
{
    [super init];
    contentTypeString = [[archiver decodeObject] retain];
    // This object will be deallocated in -awakeAfterUsingCoder: and replaced with a real OWContent.
    return self;
}

- (id)awakeAfterUsingCoder:(NSCoder *)archiver
{
    OWContentType *actualInstance = [[isa contentTypeForString:contentTypeString] retain];
    [super release];
    return actualInstance;
}

- (void)encodeWithCoder:(NSCoder *)archiver
{
    [archiver encodeObject:contentTypeString];
}

//

- (void)setExtensions:(NSArray *)someExtensions;
{
    if (extensions == someExtensions)
	return;
    [extensions release];
    extensions = [someExtensions copyWithZone:zone];
}

- (NSArray *)extensions;
{
    return extensions;
}

- (NSString *)primaryExtension;
{
    if ([extensions count])
	return [extensions objectAtIndex:0];
    return nil;
}

- (void)setHFSType:(OSType)newHFSType;
{
    hfsType = newHFSType;
}

- (OSType)hfsType;
{
    return hfsType;
}


- (void)setHFSCreator:(OSType)newHFSCreator;
{
    hfsCreator = newHFSCreator;
}

- (OSType)hfsCreator;
{
    return hfsCreator;
}


- (void)setImageName:(NSString *)newImageName;
{
    // This normally only is called once per instance, and only from +registerIconsDictionary:
    if (imageName != newImageName) {
        NSString *oldImageName;

        oldImageName = imageName;
        imageName = [newImageName copyWithZone:zone];
        [oldImageName release];
    }
}

- (NSString *)imageName;
{
    return imageName;
}

- (NSString *)contentTypeString;
{
    return contentTypeString;
}

- (NSString *)readableString;
{
    return readableString;
}

- (BOOL)isEncoding;
{
    return flags.isEncoding;
}

- (BOOL)isPublic;
{
    return flags.isPublic;
}

- (BOOL)isInteresting;
{
    return flags.isInteresting && [links count] > 0;
}

// Aliases

- (void)registerAlias:(NSString *)newAlias;
{
    NSString *key = [[newAlias lowercaseString] copyWithZone:zone];

    [contentTypeLock lock];
    OWContentType *replacedContentType = [contentTypeDictionary objectForKey:key];
    if (replacedContentType != nil && replacedContentType != self) {
#ifdef DEBUG_kc
        NSLog(@"-[%@ %s%@]: replacing %@ with %@", OBShortObjectDescription(self), _cmd, newAlias, [replacedContentType contentTypeString], [self contentTypeString]);
#endif
        [replacedContentTypes addObject:replacedContentType];
    }
    [contentTypeDictionary setObject:self forKey:key];
    [contentTypeLock unlock];
    [key release];
}

// Links

- (void)linkToContentType:(OWContentType *)targetContentType usingProcessorDescription:(OWProcessorDescription *)aProcessorDescription cost:(float)aCost;
{
    OWContentTypeLink *link;
    NSUInteger linkIndex, linkCount;

    [contentTypeLock lock];
    
    linkCount = [links count];
    for (linkIndex = 0; linkIndex < linkCount; linkIndex++) {
        link = [links objectAtIndex: linkIndex];

	if ([link targetContentType] == targetContentType) {
            if ([link cost] < aCost) {
                // Keep existing, cheaper link instead.
                [contentTypeLock unlock];
                return;
            }
            
            // We are replacing an old expensive link with a new cheaper version.
            [links removeObjectAtIndex:linkIndex];
            break;
        }
    }

    // We could probably figure out an algorithm to flush the minimum number of paths, but this is safer and this shouldn't happen very often (if at all) since content links are registered at startup.
    {
        NSEnumerator *typeEnum;
        OWContentType *type;
        
        typeEnum = [contentTypeDictionary objectEnumerator];
        while ((type = [typeEnum nextObject]))
            [type _locked_flushConversionPaths];
    }

    link = [[OWContentTypeLink allocWithZone:zone] initWithProcessorDescription:aProcessorDescription sourceContentType:self targetContentType:targetContentType cost:aCost];
    [links addObject:link];
    [link release];
    [targetContentType _addReverseContentType:self];
    
    [contentTypeLock unlock];
}

- (OWConversionPathElement *)bestPathForTargetContentType: (OWContentType *) targetType;
{
    OWConversionPathElement *path;
    
    [contentTypeLock lock];
    path = [[self _locked_computeBestPathForType:targetType visitedTypes:nil recursionLevel:0] retain];
    if (path == nil)
        [bestPathByType setObject:[NSNull null] forKey:targetType];
    [contentTypeLock unlock];

    return [path autorelease];
}

- (NSArray *)directTargetContentTypes;
{
    return links;
}

- (NSSet *)directSourceContentTypes;
{
    return reverseLinks;
}

- (NSSet *)indirectSourceContentTypes;
{
    NSMutableSet *indirectSources;
    NSMutableArray *targets;
    OWContentType *target, *source;
    NSEnumerator *sourceEnumerator;
    
    indirectSources = [[NSMutableSet alloc] init];
    targets = [[NSMutableArray alloc] initWithCapacity:5];
    
    [targets addObject:self];
    
    while ([targets count]) {
        target = [targets objectAtIndex:0];
	sourceEnumerator = [[target directSourceContentTypes] objectEnumerator];
	[targets removeObjectAtIndex:0];
	
	while ((source = [sourceEnumerator nextObject])) {
	    if (![indirectSources containsObject:source]) {
		[indirectSources addObject:source];
		[targets addObject:source];
	    }
	}
    }
    
    [targets release];
    
    return [indirectSources autorelease];
}

// Content expiration

- (NSTimeInterval)expirationTimeInterval;
{
    return expirationTimeInterval;
}

- (void)setExpirationTimeInterval:(NSTimeInterval)newTimeInterval;
{
    expirationTimeInterval = newTimeInterval;
}


//

- (NSString *)pathForEncodings:(NSArray *)contentEncodings givenOriginalPath:(NSString *)aPath;
{
#if 1
    return aPath;
#else
    NSString *fileTypeExtension, *fileEncodingExtension;
    NSString *desiredTypeExtension;
    NSString *desiredEncodingExtension;
    OWContentType *fileContentType, *fileContentEncoding;

    desiredTypeExtension = [self primaryExtension];
    desiredEncodingExtension = [contentEncoding primaryExtension];
    
    fileTypeExtension = [aPath pathExtension];
    fileEncodingExtension = nil;

    fileContentType = [OWContentType contentTypeForExtension:fileTypeExtension];
    fileContentEncoding = nil;
    if (fileContentType) {
	aPath = [aPath stringByDeletingPathExtension];
	
	if ([fileContentType isEncoding]) {
	    fileContentEncoding = fileContentType;
	    fileEncodingExtension = fileTypeExtension;
    
	    fileTypeExtension = [aPath pathExtension];
	    fileContentType = [OWContentType contentTypeForExtension:fileTypeExtension];
	    if (fileContentType)
		aPath = [aPath stringByDeletingPathExtension];
	    else
		fileTypeExtension = nil;
	}
    } else
	fileTypeExtension = nil;

#warning WJS: Put in a preference for using preferred extensions over original extensions
    // if file's type is same as datastream's type, use preferred extension
    if (fileContentType == self && desiredTypeExtension) {
        aPath = [aPath stringByAppendingPathExtension:desiredTypeExtension];

    // if datastream's type is different from file's extension type, and datastream's type specifies an extension, append datastream type extension but leave file type extension in front of it
    } else if (desiredTypeExtension && ![desiredTypeExtension isEqualToString:fileTypeExtension] && self != [OWUnknownDataStreamProcessor unknownContentType]) {
        if (fileTypeExtension)
	    aPath = [aPath stringByAppendingPathExtension:fileTypeExtension];
        aPath = [aPath stringByAppendingPathExtension:desiredTypeExtension];

    // else, put old type extension back
    } else if (fileTypeExtension)
	aPath = [aPath stringByAppendingPathExtension:fileTypeExtension];


    // Same for encoding
    if (fileContentEncoding == contentEncoding && desiredEncodingExtension) {
        aPath = [aPath stringByAppendingPathExtension:desiredEncodingExtension];
    } else if (desiredEncodingExtension && ![desiredEncodingExtension isEqualToString:fileEncodingExtension]) {
        if (fileEncodingExtension)
            aPath = [aPath stringByAppendingPathExtension:fileEncodingExtension];
        aPath = [aPath stringByAppendingPathExtension:desiredEncodingExtension];
    } else if (fileEncodingExtension)
        aPath = [aPath stringByAppendingPathExtension:fileEncodingExtension];

    return aPath;
#endif
}

// NSObject subclass and protocol

- (NSUInteger)hash;
{
    return hash;
}

// Debugging (OBObject subclass)

- (NSString *)shortDescription;
{
    return contentTypeString;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    [debugDictionary setObject:contentTypeString forKey:@"contentType"];
    [debugDictionary setObject:links forKey:@"links"];
    [debugDictionary setObject:[NSString stringWithFormat:@"%g", expirationTimeInterval] forKey:@"expirationTimeInterval"];
    if (!flags.isPublic)
        [debugDictionary setBoolValue:flags.isPublic forKey:@"isPublic"];
    if (!flags.isInteresting)
        [debugDictionary setBoolValue:flags.isInteresting forKey:@"isInteresting"];
    if (flags.isEncoding)
        [debugDictionary setBoolValue:flags.isEncoding forKey:@"isEncoding"];

    return debugDictionary;
}

@end

@implementation OWContentType (Private)

+ (void)controllerDidInitialize:(OFController *)controller;
{
    [self reloadExpirationTimeIntervals:nil];
}

+ (void)reloadExpirationTimeIntervals:(NSNotification *)notification;
{
    [self updateExpirationTimeIntervalsFromDefaults];
}

+ (void)registerAliasesDictionary:(NSDictionary *)aliasesDictionary;
{
    NSEnumerator *contentTypeEnumerator;
    NSString *aContentTypeString;
    NSEnumerator *aliasesEnumerator;

    contentTypeEnumerator = [aliasesDictionary keyEnumerator];
    aliasesEnumerator = [aliasesDictionary objectEnumerator];

    while ((aContentTypeString = [contentTypeEnumerator nextObject])) {
	id aliasesObject;
	NSArray *aliasesArray;
	OWContentType *contentType;
	NSEnumerator *aliasEnumerator;
	NSString *alias;
	
	aliasesObject = [aliasesEnumerator nextObject];
	if ([aliasesObject isKindOfClass:[NSArray class]])
	    aliasesArray = aliasesObject;
	else if ([aliasesObject isKindOfClass:[NSString class]])
	    aliasesArray = [NSArray arrayWithObject:aliasesObject];
	else
	    break;
	
	contentType = [self contentTypeForString:aContentTypeString];
	aliasEnumerator = [aliasesArray objectEnumerator];
        while ((alias = [aliasEnumerator nextObject])) {
            [contentType registerAlias:alias];
        }
    }
}

+ (void)registerExtensionsDictionary:(NSDictionary *)extensionsDictionary;
{
    NSEnumerator *contentTypeEnumerator;
    NSString *aContentTypeString;
    NSEnumerator *extensionsEnumerator;

    contentTypeEnumerator = [extensionsDictionary keyEnumerator];
    extensionsEnumerator = [extensionsDictionary objectEnumerator];

    [contentTypeLock lock];
    while ((aContentTypeString = [contentTypeEnumerator nextObject])) {
        id extensionsObject;
        NSArray *extensionsArray;
        OWContentType *contentType;
        NSEnumerator *extensionEnumerator;
        NSString *extension;

        extensionsObject = [extensionsEnumerator nextObject];
        if ([extensionsObject isKindOfClass:[NSArray class]])
            extensionsArray = extensionsObject;
        else if ([extensionsObject isKindOfClass:[NSString class]])
            extensionsArray = [NSArray arrayWithObject:extensionsObject];
        else
            break;

        contentType = [self contentTypeForString:aContentTypeString];

        extensionEnumerator = [extensionsArray objectEnumerator];
        while ((extension = [extensionEnumerator nextObject])) {
            [self registerFileExtension: extension forContentType: contentType];
        }
    }
    [contentTypeLock unlock];
}

+ (OSType)osTypeForString:(NSString *)string;
{
    OSType osType = 0x20202020; // all spaces

    [[string dataUsingEncoding:NSMacOSRomanStringEncoding] getBytes:(void *)&osType length:4];
    return osType;
}

+ (void)registerHFSTypesDictionary:(NSDictionary *)hfsTypesDictionary;
{
    NSEnumerator *contentTypeEnumerator;
    NSString *aContentTypeString;
    NSEnumerator *hfsTypesEnumerator;

    contentTypeEnumerator = [hfsTypesDictionary keyEnumerator];
    hfsTypesEnumerator = [hfsTypesDictionary objectEnumerator];

    [contentTypeLock lock];
    while ((aContentTypeString = [contentTypeEnumerator nextObject])) {
        OWContentType *contentType;
        OSType anHFSType;
        
        contentType = [self contentTypeForString:aContentTypeString];
        anHFSType = [self osTypeForString:[hfsTypesEnumerator nextObject]];
        [contentType setHFSType:anHFSType];
        [macOSTypeToContentTypeDictionary setObject:contentType forKey:[NSNumber numberWithUnsignedLong:anHFSType]];
    }
    [contentTypeLock unlock];
}

+ (void)registerHFSCreatorsDictionary:(NSDictionary *)hfsCreatorsDictionary;
{
    NSEnumerator *contentTypeEnumerator;
    NSString *aContentTypeString;
    NSEnumerator *hfsCreatorsEnumerator;

    contentTypeEnumerator = [hfsCreatorsDictionary keyEnumerator];
    hfsCreatorsEnumerator = [hfsCreatorsDictionary objectEnumerator];

    [contentTypeLock lock];
    while ((aContentTypeString = [contentTypeEnumerator nextObject])) {
        [[self contentTypeForString:aContentTypeString] setHFSCreator:[self osTypeForString:[hfsCreatorsEnumerator nextObject]]];
    }
    [contentTypeLock unlock];
}

+ (void)registerIconsDictionary:(NSDictionary *)iconsDictionary;
{
    NSEnumerator *contentTypeEnumerator;
    NSString *aContentTypeString;
    NSEnumerator *imageNamesEnumerator;

    contentTypeEnumerator = [iconsDictionary keyEnumerator];
    imageNamesEnumerator = [iconsDictionary objectEnumerator];

    while ((aContentTypeString = [contentTypeEnumerator nextObject])) {
        NSString *imageNameString;
        OWContentType *contentType;

        imageNameString = [imageNamesEnumerator nextObject];
        if ([imageNameString zone] != zone)
            imageNameString = [[imageNameString copyWithZone:zone] autorelease];
        contentType = [self contentTypeForString:aContentTypeString];
        [contentType setImageName:imageNameString];
    }
}

+ (void)registerFlagsDictionary:(NSDictionary *)iconsDictionary;
{
    NSEnumerator *contentTypeEnumerator;
    NSString *aContentTypeString;

    contentTypeEnumerator = [iconsDictionary keyEnumerator];

    while ((aContentTypeString = [contentTypeEnumerator nextObject])) {
        id contentFlags;
        NSString *flag;
        OWContentType *contentType;
        NSEnumerator *flagEnumerator;

        contentFlags = [iconsDictionary objectForKey:aContentTypeString];
        contentType = [self contentTypeForString:aContentTypeString];

        if ([contentFlags isKindOfClass:[NSArray class]]) {
            flagEnumerator = [contentFlags objectEnumerator];
            flag = [flagEnumerator nextObject];
        } else {
            flagEnumerator = nil;
            flag = contentFlags;
        }

        for( ; flag; flag = [flagEnumerator nextObject]) {
            if ([flag isEqualToString:@"boring"])
                contentType->flags.isInteresting = NO;
            else if([flag isEqualToString:@"private"])
                contentType->flags.isPublic = NO;
        }
    }
}
        

- _initWithContentTypeString:(NSString *)aString;
{
    unsigned int privateTypeIndex;

    if (![super init])
	return nil;

    contentTypeString = [aString copyWithZone:zone];
    hash = [contentTypeString hash];
    links = [[NSMutableArray allocWithZone:zone] init];
    reverseLinks = nil;
    extensions = nil;
    expirationTimeInterval = defaultExpirationTimeInterval;

    flags.isEncoding = [contentTypeString hasPrefix:@"encoding/"];
    flags.isPublic = YES;
    flags.isInteresting = YES;

    for (privateTypeIndex = 0; privateSupertypes[privateTypeIndex]; privateTypeIndex++) {
	if ([contentTypeString hasPrefix:privateSupertypes[privateTypeIndex]]) {
	    flags.isPublic = NO;
	    break;
	}
    }

    if ([contentTypeString hasPrefix:@"image/"])
        readableString = NSLocalizedStringFromTableInBundle(@"Image", @"OWF", [OWContentType bundle], @"contenttype readable name of 'image/' encodings");
    else if ([contentTypeString isEqualToString:@"text/html"])
        readableString = NSLocalizedStringFromTableInBundle(@"HTML", @"OWF", [OWContentType bundle], @"contenttype readable name of 'text/html' encodings");
    else {
        NSRange range;

        range = [contentTypeString rangeOfString:@"/"];
        if (range.location != NSNotFound)
            readableString = [[[contentTypeString substringFromIndex:NSMaxRange(range)] capitalizedString] copyWithZone:zone];
        else
            readableString = nil;
    }
    
    return self;
}

- (void)_addReverseContentType:(OWContentType *)sourceContentType;
{
    if (!reverseLinks)
        reverseLinks = [[NSMutableSet allocWithZone:zone] initWithCapacity:5];

    [reverseLinks addObject:sourceContentType];
}

- (void) _locked_flushConversionPaths;
{
    [bestPathByType release];
    bestPathByType = nil;
}

- (OWConversionPathElement *)_locked_computeBestPathForType:(OWContentType *)targetType visitedTypes:(NSMutableSet *)visitedTypes recursionLevel:(unsigned int)recursionLevel;
{
    float cost, bestCost = FLT_MAX;
    OWContentTypeLink *bestLink;
    OWConversionPathElement *bestPath;

    // Check for a cached result (positive or negative)
    bestPath = [bestPathByType objectForKey:targetType];
    if (bestPath) {
        if ((id)bestPath == [NSNull null])
            return nil;
        else
            return bestPath;
    }
    
    // No cached result, if we are at the top of the recursion, allocate a visited set
#ifdef DEBUG_PATHS
    NSLog(@"%@Compute best path: checking %@ -> %@", [NSString spacesOfLength:4 * recursionLevel], [self contentTypeString], [targetType contentTypeString]);
#endif

    if (!visitedTypes)
        visitedTypes = [NSMutableSet set];
    else if ([visitedTypes member:self]) {
        // Detect and eliminate loops
#ifdef DEBUG_PATHS
        NSLog(@"%@Short-circuit: visited types contains %@", [NSString spacesOfLength:4 * recursionLevel], [self contentTypeString], [targetType contentTypeString]);
#endif
        return nil;
    }
    [visitedTypes addObject:self];

    // Lazily allocate this dictionary to store cached results
    if (!bestPathByType)
        bestPathByType = [[NSMutableDictionary alloc] init];


    bestLink = nil;
    bestPath = nil;
    bestCost = FLT_MAX;
    
    for (OWContentTypeLink *link in links) {
        OWContentType *type = [link targetContentType];
        
        OWConversionPathElement *path;
        if (type == targetType) {
            // direct link
            path = nil;
            cost = [link cost];
        } else {
            path = [type _locked_computeBestPathForType:targetType visitedTypes:visitedTypes recursionLevel:recursionLevel + 1];
            if (path) {
                // indirect link through this type
                cost = [link cost] + [path totalCost];
            } else {
                // no link at all
                continue;
            }
        }
        if (cost < bestCost) {
            bestCost = cost;
            bestLink = link;
            bestPath = path; // might be nil in a direct link
        }
    }
    
    if (bestLink) {
        bestPath = [OWConversionPathElement elementLink:bestLink nextElement:bestPath];
        [bestPathByType setObject:bestPath forKey:targetType];
    }

#ifdef DEBUG_PATHS
    if (bestLink)
        NSLog(@"%@Calculated best path from %@ -> %@: %@ (%1.1f) creates %@", [NSString spacesOfLength:4 * recursionLevel], [self contentTypeString], [targetType contentTypeString], [bestLink processorClassName], bestCost, [[bestLink targetContentType] contentTypeString]);
    else
        NSLog(@"%@No path from %@ -> %@", [NSString spacesOfLength:4 * recursionLevel], [self contentTypeString], [targetType contentTypeString]);
#endif

    return bestPath;
}

@end
