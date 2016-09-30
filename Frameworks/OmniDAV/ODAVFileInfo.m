// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDAV/ODAVFileInfo.h>

#import <OmniFoundation/NSString-OFURLEncoding.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/NSURL-OFExtensions.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif

RCS_ID("$Id$");

@implementation ODAVFileInfo

+ (NSString *)nameForURL:(NSURL *)url;
{
    NSString *urlPath = [url path];
    if ([urlPath hasSuffix:@"/"])
        urlPath = [urlPath stringByRemovingSuffix:@"/"];
    // Hack for double-encoding servers.  We know none of our file names have '%' in them.
    NSString *name = [urlPath lastPathComponent];
    NSString *decodedName = [NSString decodeURLString:name];
    while (![name isEqualToString:decodedName]) {
        name = decodedName;
        decodedName = [NSString decodeURLString:name];
    }
    return name;
}

+ (NSURL *)availableURL:(NSURL *)startingURL avoidingFileInfos:(NSArray *)fileInfos;
{
    NSString *baseName = [self nameForURL:startingURL];
    NSURL *directoryURL = OFDirectoryURLForURL(startingURL);
    
    NSString *extension = [baseName pathExtension];
    
    BOOL isDirectory = [[startingURL absoluteString] hasSuffix:@"/"]; // Terrible
    BOOL shouldContainExtension = ![NSString isEmptyString:extension];
    
    __autoreleasing NSString *name;
    NSUInteger counter;
    [[baseName stringByDeletingPathExtension] splitName:&name andCounter:&counter];
    
    NSMutableSet *usedFilenames = [NSMutableSet new];
    for (ODAVFileInfo *fileInfo in fileInfos)
        [usedFilenames addObject:[fileInfo.originalURL lastPathComponent]];

    while (YES) {
        NSString *filename = nil;
        
        if (counter == 0) {
            if (shouldContainExtension)
                filename = [[NSString alloc] initWithFormat:@"%@.%@", name, extension];
            else
                filename = [name copy];
        } else {
            if (shouldContainExtension)
                filename = [[NSString alloc] initWithFormat:@"%@ %lu.%@", name, counter, extension];
            else
                filename = [[NSString alloc] initWithFormat:@"%@ %lu", name, counter];
        }
        
        // TODO: We are assuming the server is case sensitive.
        if ([usedFilenames member:filename] == nil)
            return [directoryURL URLByAppendingPathComponent:filename isDirectory:isDirectory];
        
        if (counter == 0)
            counter = 2; // First duplicate should be 'Foo 2'.
        else
            counter++;
    }
}

- initWithOriginalURL:(NSURL *)url name:(NSString *)name exists:(BOOL)exists directory:(BOOL)directory size:(off_t)size lastModifiedDate:(NSDate *)date ETag:(NSString *)ETag;
{
    OBPRECONDITION(url);
    OBPRECONDITION(!directory || size == 0);
    
    if (!(self = [super init]))
        return nil;

    _originalURL = [[url absoluteURL] copy];
    if (name)
        _name = [name copy];
    else
        _name = [[[self class] nameForURL:_originalURL] copy];
    _exists = exists;
    _directory = directory;
    _size = size;
    _lastModifiedDate = [date copy];
    _ETag = [ETag copy];
    
    return self;
}

- initWithOriginalURL:(NSURL *)url name:(NSString *)name exists:(BOOL)exists directory:(BOOL)directory size:(off_t)size lastModifiedDate:(NSDate *)date;
{
    return [self initWithOriginalURL:url name:name exists:exists directory:directory size:size lastModifiedDate:date ETag:nil];
}

@synthesize originalURL = _originalURL;
@synthesize name = _name;
@synthesize exists = _exists;
@synthesize isDirectory = _directory;
@synthesize size = _size;
@synthesize lastModifiedDate = _lastModifiedDate;
@synthesize ETag = _ETag;

- (BOOL)hasExtension:(NSString *)extension;
{
    return ([[_name pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame);
}

- (NSString *)UTI;
{
    return OFUTIForFileExtensionPreferringNative([_name pathExtension], [NSNumber numberWithBool:_directory]);
}

- (NSComparisonResult)compareByURLPath:(ODAVFileInfo *)otherInfo;
{
    return [[_originalURL path] compare:[[otherInfo originalURL] path]];
}

- (NSComparisonResult)compareByName:(ODAVFileInfo *)otherInfo;
{
    return [_name localizedStandardCompare:[otherInfo name]];
}

- (BOOL)isSameAsFileInfo:(ODAVFileInfo *)otherInfo asOfServerDate:(NSDate *)serverDate;
{
    if (OFNOTEQUAL(_ETag, otherInfo.ETag))
        return NO;
    if (OFNOTEQUAL(_lastModifiedDate, otherInfo.lastModifiedDate))
        return NO;
    if (![_lastModifiedDate isBeforeDate:serverDate])
        return NO; // It might be the same, but we can't be sure since server timestamps have limited resolution.
    
    return YES;
}

- (BOOL)mayBeSameAsFileInfo:(ODAVFileInfo *)otherInfo;
{
    if ((_exists && !otherInfo.exists) ||
        (!_exists && otherInfo.exists)) {
        return NO;
    }
    
    if ((_directory && !otherInfo.isDirectory) ||
        (!_directory && otherInfo.isDirectory)) {
        return NO;
    }
    
    if (_lastModifiedDate && otherInfo.lastModifiedDate && ![_lastModifiedDate isEqual:otherInfo.lastModifiedDate])
        return NO;
    
    if (_directory || !_exists) {
        // ETag and size validators don't apply to directories
        // or to non-existent files
        return YES;
    }
    
    if (self.size && otherInfo.size && self.size != otherInfo.size)
        return NO;
    if (_ETag && otherInfo.ETag && ![_ETag isEqualToString:otherInfo.ETag])
        return NO;

    return YES;
}

#pragma mark - Debugging

- (NSString *)description;
{
    return [NSString stringWithFormat:@"<%@:%p '%@'>", NSStringFromClass([self class]), self, _name];
}

- (NSString *)shortDescription;
{
    return _name;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(NSUInteger)level;
{
    return [self shortDescription];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:_originalURL forKey:@"url" defaultObject:nil];
    [dict setObject:_name forKey:@"name" defaultObject:nil];
    [dict setBoolValue:_exists forKey:@"exists"];
    [dict setBoolValue:_directory forKey:@"directory"];
    [dict setUnsignedLongLongValue:_size forKey:@"size"];
    [dict setObject:_lastModifiedDate forKey:@"lastModifiedDate" defaultObject:nil];
    [dict setObject:_ETag forKey:@"ETag" defaultObject:nil];
    return dict;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    // We are immutable
    return self;
}

@end
