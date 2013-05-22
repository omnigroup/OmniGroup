// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSFileInfo.h>

#import <OmniFoundation/NSString-OFURLEncoding.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/OFNull.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif

RCS_ID("$Id$");

@implementation OFSFileInfo

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

- (NSComparisonResult)compareByURLPath:(OFSFileInfo *)otherInfo;
{
    return [[_originalURL path] compare:[[otherInfo originalURL] path]];
}

- (NSComparisonResult)compareByName:(OFSFileInfo *)otherInfo;
{
    return [_name localizedStandardCompare:[otherInfo name]];
}

- (BOOL)isSameAsFileInfo:(OFSFileInfo *)otherInfo asOfServerDate:(NSDate *)serverDate;
{
    if (OFNOTEQUAL(_ETag, otherInfo.ETag))
        return NO;
    if (OFNOTEQUAL(_lastModifiedDate, otherInfo.lastModifiedDate))
        return NO;
    if (![_lastModifiedDate isBeforeDate:serverDate])
        return NO; // It might be the same, but we can't be sure since server timestamps have limited resolution.
    
    return YES;
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return _name;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(NSUInteger)level;
{
    return [self shortDescription];
}

#ifdef DEBUG
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:_originalURL forKey:@"url" defaultObject:nil];
    [dict setObject:_name forKey:@"name" defaultObject:nil];
    [dict setObject:[NSNumber numberWithBool:_exists] forKey:@"exists"];
    [dict setObject:[NSNumber numberWithBool:_directory] forKey:@"directory"];
    [dict setObject:[NSNumber numberWithUnsignedLongLong:_size] forKey:@"size"];
    return dict;
}
#endif

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    // We are immutable
    return self;
}

@end
