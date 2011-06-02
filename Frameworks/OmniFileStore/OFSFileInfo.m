// Copyright 2008-2011 Omni Development, Inc.  All rights reserved.
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
#import <OmniFoundation/OFNull.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif

RCS_ID("$Id$");

@implementation OFSFileInfo

static NSMutableDictionary *_NativeUTIForFileExtension;

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

static NSString *UTIForFileExtension(NSString *fileExtension)
{
    if (fileExtension == nil)
        return nil;

    NSString *nativeUTI = [_NativeUTIForFileExtension objectForKey:fileExtension];
    if (nativeUTI != nil)
        return nativeUTI;

    // Not a registered native UTI; try asking LaunchServices
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)fileExtension, NULL);
    return [NSMakeCollectable(fileUTI) autorelease];
}

+ (NSString *)UTIForFilename:(NSString *)filename;
{
    NSString *fileExtension = [filename pathExtension];
    NSString *fileUTI = UTIForFileExtension(fileExtension);
    if (fileUTI != nil && UTTypeConformsTo((CFStringRef)fileUTI, kUTTypeArchive)) {    // only supporting zip files including an extension that we recognize (so, if user uses Finder to compress, will end up with 'filename.graffle.zip') 
        NSString *unarchivedFilename = [filename stringByDeletingPathExtension];
        fileUTI = UTIForFileExtension([unarchivedFilename pathExtension]);
    }
    return fileUTI;
}

+ (NSString *)UTIForURL:(NSURL *)url;
{
    return [self UTIForFilename:[self nameForURL:url]];
}

+ (void)registerNativeUTI:(NSString *)UTI forFileExtension:(NSString *)fileExtension;
{
    if (_NativeUTIForFileExtension == nil)
        _NativeUTIForFileExtension = [[NSMutableDictionary alloc] init];

    [_NativeUTIForFileExtension setObject:UTI forKey:fileExtension];
}

- initWithOriginalURL:(NSURL *)url name:(NSString *)name exists:(BOOL)exists directory:(BOOL)directory size:(off_t)size lastModifiedDate:(NSDate *)date;
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
    
    return self;
}

- (void)dealloc;
{
    [_originalURL release];
    [_name release];
    [_lastModifiedDate release];
    [super dealloc];
}

- (NSURL *)originalURL;
{
    return _originalURL;
}

- (NSString *)name;
{
    return _name;
}

- (BOOL)exists;
{
    return _exists;
}

- (BOOL)isDirectory;
{
    return _directory;
}

- (off_t)size;
{
    return _size;
}

- (NSDate *)lastModifiedDate;
{
    return _lastModifiedDate;
}

- (BOOL)hasExtension:(NSString *)extension;
{
    return ([[_name pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame);
}

- (NSString *)UTI;
{
    return [OFSFileInfo UTIForFilename:_name];
}

- (NSComparisonResult)compareByURLPath:(OFSFileInfo *)otherInfo;
{
    return [[_originalURL path] compare:[[otherInfo originalURL] path]];
}

- (NSComparisonResult)compareByName:(OFSFileInfo *)otherInfo;
{
    return [_name caseInsensitiveCompare:[otherInfo name]];
}

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

@end

NSURL *OFSURLRelativeToDirectoryURL(NSURL *baseURL, NSString *quotedFileName)
{
    NSMutableString *urlString = [[baseURL absoluteString] mutableCopy];
    NSRange pathRange = OFSURLRangeOfPath(urlString);
    
    if ([urlString rangeOfString:@"/" options:NSAnchoredSearch|NSBackwardsSearch range:pathRange].length == 0) {
        [urlString insertString:@"/" atIndex:NSMaxRange(pathRange)];
        pathRange.length ++;
    }
    
    [urlString insertString:quotedFileName atIndex:NSMaxRange(pathRange)];

    NSURL *newURL = [NSURL URLWithString:urlString];
    [urlString release];
    return newURL;
}

NSURL *OFSDirectoryURLForURL(NSURL *url)
{
    NSString *urlString = [url absoluteString];
    NSRange lastComponentRange;
    unsigned trailingSlashLength;
    if (!OFSURLRangeOfLastPathComponent(urlString, &lastComponentRange, &trailingSlashLength))
        return url;

    NSString *parentURLString = [urlString substringToIndex:lastComponentRange.location];
    NSURL *parentURL = [NSURL URLWithString:parentURLString];
    return parentURL;
}

NSURL *OFSURLWithTrailingSlash(NSURL *baseURL)
{
    if (baseURL == nil)
        return nil;

    if ([[baseURL path] hasSuffix:@"/"])
        return baseURL;
    
    NSString *baseURLString = [baseURL absoluteString];
    NSRange pathRange = OFSURLRangeOfPath(baseURLString);
    
    if (pathRange.length && [baseURLString rangeOfString:@"/" options:NSAnchoredSearch|NSBackwardsSearch range:pathRange].length > 0)
        return baseURL;
    
    NSMutableString *newString = [baseURLString mutableCopy];
    [newString insertString:@"/" atIndex:NSMaxRange(pathRange)];
    NSURL *newURL = [NSURL URLWithString:newString];
    [newString release];
    
    return newURL;
}

NSURL *OFSURLWithNameAffix(NSURL *baseURL, NSString *quotedSuffix, BOOL addSlash, BOOL removeSlash)
{
    OBASSERT(![quotedSuffix containsString:@"/"]);
    OBASSERT(!(addSlash && removeSlash));
    
    NSMutableString *urlString = [[baseURL absoluteString] mutableCopy];
    NSRange pathRange = OFSURLRangeOfPath(urlString);
    
    // Can't apply an affix to an empty name. Well, we could, but that would just push the problem off to some other part of XMLData.
    if (!pathRange.length) {
        [urlString release];
        return nil;
    }
    
    NSRange trailingSlash = [urlString rangeOfString:@"/" options:NSAnchoredSearch|NSBackwardsSearch range:pathRange];
    if (trailingSlash.length) {
        if (removeSlash)
            [urlString replaceCharactersInRange:trailingSlash withString:quotedSuffix];
        else
            [urlString insertString:quotedSuffix atIndex:trailingSlash.location];
    } else {
        if (addSlash)
            [urlString insertString:@"/" atIndex:NSMaxRange(pathRange)];
        [urlString insertString:quotedSuffix atIndex:NSMaxRange(pathRange)];
    }
    // pathRange is inaccurate now, but we don't use it again

    NSURL *newURL = [NSURL URLWithString:urlString];
    [urlString release];
    return newURL;
}

BOOL OFSURLRangeOfLastPathComponent(NSString *urlString, NSRange *lastComponentRange, unsigned *andTrailingSlash)
{
    if (!urlString)
        return NO;
    
    NSRange pathRange = OFSURLRangeOfPath(urlString);
    if (!pathRange.length)
        return NO;
    
    NSRange trailingSlash = [urlString rangeOfString:@"/" options:NSAnchoredSearch|NSBackwardsSearch range:pathRange];
    NSRange previousSlash;
    if (trailingSlash.length) {
        OBINVARIANT(NSMaxRange(trailingSlash) == NSMaxRange(pathRange));
        previousSlash = [urlString rangeOfString:@"/"
                                         options:NSBackwardsSearch
                                           range:(NSRange){ pathRange.location, trailingSlash.location - pathRange.location }];
        
        if (previousSlash.length && !(NSMaxRange(previousSlash) <= trailingSlash.location)) {
            // Double trailing slash is a syntactic weirdness we don't have a good way to handle.
            return NO;
        }
    } else {
        previousSlash = [urlString rangeOfString:@"/" options:NSBackwardsSearch range:pathRange];
    }
    
    if (!previousSlash.length)
        return NO;
    
    lastComponentRange->location = NSMaxRange(previousSlash);
    lastComponentRange->length = NSMaxRange(pathRange) - NSMaxRange(previousSlash) - trailingSlash.length;
    if (andTrailingSlash)
        *andTrailingSlash = (unsigned)trailingSlash.length;
    
    return YES;
}

NSRange OFSURLRangeOfPath(NSString *rfc1808URL)
{
    if (!rfc1808URL) {
        return (NSRange){NSNotFound, 0};
    }
    
    NSRange colon = [rfc1808URL rangeOfString:@":"];
    if (!colon.length) {
        return (NSRange){NSNotFound, 0};
    }
    
    NSUInteger len = [rfc1808URL length];
#define Suffix(pos) (NSRange){(pos), len - (pos)}

    // The fragment identifier is significant anywhere after the colon (and forbidden before the colon, but whatever)
    NSRange terminator = [rfc1808URL rangeOfString:@"#" options:0 range:Suffix(NSMaxRange(colon))];
    if (terminator.length)
        len = terminator.location;
    
    // According to RFC1808, the ? and ; characters do not have special meaning within the host specifier.
    // But the host specifier is an optional part (again, according to the RFC), so we need to only optionally skip it.
    NSRange pathRange;
    NSRange slashes = [rfc1808URL rangeOfString:@"//" options:NSAnchoredSearch range:Suffix(NSMaxRange(colon))];
    if (slashes.length) {
        NSRange firstPathSlash = [rfc1808URL rangeOfString:@"/" options:0 range:Suffix(NSMaxRange(slashes))];
        if (!firstPathSlash.length) {
            // A URL of the form foo://bar.com
            return (NSRange){ len, 0 };
        } else {
            pathRange.location = firstPathSlash.location;
        }
    } else {
        // The first character after the colon may or may not be a slash; RFC1808 allows relative paths there.
        pathRange.location = NSMaxRange(colon);
    }
    
    pathRange.length = len - pathRange.location;
    
    // Strip any query
    terminator = [rfc1808URL rangeOfString:@"?" options:0 range:pathRange];
    if (terminator.length)
        pathRange.length = terminator.location - pathRange.location;
    
    // Strip any parameter-string
    [rfc1808URL rangeOfString:@";" options:0 range:pathRange];
    if (terminator.length)
        pathRange.length = terminator.location - pathRange.location;
    
    return pathRange;
}


// This is a sort of simple 3-way-merge of URLs which we use to rewrite the Destination: header of a MOVE request if the server responds with a redirect of the source URL.
// Generally we're just MOVEing something to rename it within its containing collection. So this function checks to see if that is true, and if so, returns a new Destination: URL which represents the same rewrite within the new collection pointed to by the redirect.
// For more complicated situations, this function just gives up and returns nil; the caller will need to have some way to handle that.
NSString *OFSURLAnalogousRewrite(NSURL *oldSourceURL, NSString *oldDestination, NSURL *newSourceURL)
{
    if ([oldDestination hasPrefix:@"/"])
        oldDestination = [[NSURL URLWithString:oldDestination relativeToURL:oldSourceURL] absoluteString];
    NSString *oldSource = [oldSourceURL absoluteString];
    
    NSRange oldSourceLastComponent, oldDestinationLastComponent, newSourceLastComponent;
    unsigned oldSourceSlashy, oldDestinationSlashy, newSourceSlashy;
    if (!OFSURLRangeOfLastPathComponent(oldDestination, &oldDestinationLastComponent, &oldDestinationSlashy) ||
        !OFSURLRangeOfLastPathComponent(oldSource, &oldSourceLastComponent, &oldSourceSlashy)) {
        // Can't parse something.
        return nil;
    }
    
    if (![[oldSource substringToIndex:oldSourceLastComponent.location] isEqualToString:[oldDestination substringToIndex:oldDestinationLastComponent.location]]) {
        // The old source and destination URLs differ in more than just their final path component. Not obvious how to rewrite.
        // (We should maybe be checking the span after the last path component as well, but that's going to be an empty string in any reasonable situation)
        return nil;
    }
    
    NSString *newSource = [newSourceURL absoluteString];
    if (!OFSURLRangeOfLastPathComponent(newSource, &newSourceLastComponent, &newSourceSlashy)) {
        // Can't parse something.
        return nil;
    }
    
    if (![[oldSource substringWithRange:oldSourceLastComponent] isEqualToString:[newSource substringWithRange:newSourceLastComponent]]) {
        // The server's redirect changes the final path component, which is the same thing our MOVE is changing. Flee!
        return nil;
    }
    
    NSMutableString *newDestination = [[newSource mutableCopy] autorelease];
    NSString *newLastComponent = [oldDestination substringWithRange:oldDestinationLastComponent];
    if (!oldSourceSlashy && oldDestinationSlashy && !newSourceSlashy) {
        // We were adding a trailing slash; keep doing so.
        newLastComponent = [newLastComponent stringByAppendingString:@"/"];
    } else if (oldSourceSlashy && !oldDestinationSlashy && newSourceSlashy) {
        // We were removing a trailing slash. Extend the range so that we delete the new URL's trailing slash as well.
        newSourceLastComponent.length += newSourceSlashy;
    }
    [newDestination replaceCharactersInRange:newSourceLastComponent withString:newLastComponent];
    
    return newDestination;
}

