// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSURL-OFExtensions.h>

@import OmniBase;
@import Foundation;

#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFUTI.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif

RCS_ID("$Id$")

OB_REQUIRE_ARC

NS_ASSUME_NONNULL_BEGIN

#if 0 && defined(DEBUG_bungi)
// Patch -[NSURL isEqual:] and -hash to asssert. Don't use these as dictionary keys due to their issues with comparison (standardized paths for /var/private, trailing slash, case comparison bugs with hex-encoded octets).
static BOOL (*original_NSURL_isEqual)(NSURL *self, SEL _cmd, id otherObject);
static NSUInteger (*original_NSURL_hash)(NSURL *self, SEL _cmd);

static BOOL replacement_NSURL_isEqual(NSURL *self, SEL _cmd, id otherObject)
{
    if ([self isFileURL]) {
        // NSFileManager calls -isEqual: on the two URLs given to -writeToURL:options:originalContentsURL:error:, so we ignore file URLs.
    } else if ([[self absoluteString] length] == 0) {
        // OSURLStyleAttribute's default value
        
    } else {
        OBASSERT_NOT_REACHED("Don't call -[NSURL isEqual:]");
    }
    
    return original_NSURL_isEqual(self, _cmd, otherObject);
}

static NSUInteger replacement_NSURL_hash(NSURL *self, SEL _cmd)
{
    OBASSERT_NOT_REACHED("Don't call -[NSURL hash]");
    return original_NSURL_hash(self, _cmd);
}

static void patchURL(void) __attribute__((constructor));
static void patchURL(void)
{
    Class cls = [NSURL class];
    original_NSURL_isEqual = (typeof(original_NSURL_isEqual))OBReplaceMethodImplementation(cls, @selector(isEqual:), (IMP)replacement_NSURL_isEqual);
    original_NSURL_hash = (typeof(original_NSURL_hash))OBReplaceMethodImplementation(cls, @selector(hash), (IMP)replacement_NSURL_hash);
}


#endif


NSRange OFURLRangeOfPath(NSString *rfc1808URL)
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

NSRange OFURLRangeOfHost(NSString *rfc1808URL)
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
    NSRange slashes = [rfc1808URL rangeOfString:@"//" options:NSAnchoredSearch range:Suffix(NSMaxRange(colon))];
    if (!slashes.length)
        return (NSRange){NSNotFound, 0};

    
    NSRange afterSlashes = Suffix(NSMaxRange(slashes));
    NSRange firstPathSlash = [rfc1808URL rangeOfString:@"/" options:0 range:afterSlashes];
    if (!firstPathSlash.length)
        // A URL of the form foo://bar.com
        return afterSlashes;
    
    return NSMakeRange(afterSlashes.location, firstPathSlash.location - afterSlashes.location);
}

NSURL *OFURLWithTrailingSlash(NSURL *baseURL)
{
    if (baseURL == nil) {
        return nil;
    }
    
    if ([[baseURL path] hasSuffix:@"/"]) {
        return baseURL;
    }
    
    NSString *baseURLString = [baseURL absoluteString];
    NSRange pathRange = OFURLRangeOfPath(baseURLString);
    
    if (pathRange.location == NSNotFound) {
        // No path, so we can't append a / to the path
        return baseURL;
    }
    
    if (pathRange.location != NSNotFound && [baseURLString rangeOfString:@"/" options:NSAnchoredSearch|NSBackwardsSearch range:pathRange].location != NSNotFound) {
        return baseURL;
    }
    
    NSMutableString *newString = [baseURLString mutableCopy];
    [newString insertString:@"/" atIndex:NSMaxRange(pathRange)];
    NSURL *newURL = [NSURL URLWithString:newString];
    
    return newURL;
}

BOOL OFURLEqualsURL(NSURL *URL1, NSURL *URL2)
{
    if (URL1 == URL2)
        return YES;
    if (!URL1 || !URL2)
        return NO;
    
    URL1 = [URL1 absoluteURL];
    URL2 = [URL2 absoluteURL];
    
    // This assumes that -path keeps the trailing slash and that we want slash differences to be significant (might want to change that).
    if (OFNOTEQUAL([URL1 path], [URL2 path]))
        return NO;
    
    // Some other bits should maybe be URL-decoded before comparison too. Also, we should maybe just assert that all the goofy stuff is nil for OFX-used URLs.
    return
    OFISEQUAL(URL1.scheme, URL2.scheme) &&
    OFISEQUAL(URL1.host, URL2.host) &&
    OFISEQUAL(URL1.port, URL2.port) &&
    OFISEQUAL(URL1.user, URL2.user) &&
    OFISEQUAL(URL1.password, URL2.password) &&
    OFISEQUAL(URL1.fragment, URL2.fragment) &&
    OFISEQUAL(URL1.parameterString, URL2.parameterString) &&
    OFISEQUAL(URL1.query, URL2.query);
}

BOOL OFURLEqualToURLIgnoringTrailingSlash(NSURL *URL1, NSURL *URL2)
{
    if (OFURLEqualsURL(URL1, URL2))
        return YES;
    return OFURLEqualsURL(OFURLWithTrailingSlash(URL1), OFURLWithTrailingSlash(URL2));
}

static void _assertPlainURL(NSURL *url)
{
    OBPRECONDITION([NSString isEmptyString:[url fragment]]);
    OBPRECONDITION([NSString isEmptyString:[url parameterString]]);
    OBPRECONDITION([NSString isEmptyString:[url query]]);
}

NSString *OFStandardizedPathForFileURL(NSURL *url, BOOL followFinalSymlink)
{
    OBASSERT([url isFileURL]);
    NSString *urlPath = [[url absoluteURL] path];
    
    NSString *path;
    if (!followFinalSymlink) {
        // We don't always want to resolve symlinks in the last path component, or we can't tell symlinks apart from the things they point at
        NSString *standardizedParentPath = [[urlPath stringByDeletingLastPathComponent] stringByStandardizingPath];
        path = [standardizedParentPath stringByAppendingPathComponent:[urlPath lastPathComponent]];
    } else {
        // When the container is a symlink, however, we do want to resolve it
        path = [[urlPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
    }
    
    // In some cases this doesn't normalize /private/var/mobile and /var/mobile to the same thing.
    path = [path stringByRemovingPrefix:@"/var/mobile/"];
    path = [path stringByRemovingPrefix:@"/private/var/mobile/"];
    
    return path;
}

BOOL OFURLContainsURL(NSURL *containerURL, NSURL *url)
{
    _assertPlainURL(url);
    _assertPlainURL(containerURL);
    
    if (!containerURL)
        return NO;
    
    if ([[containerURL scheme] caseInsensitiveCompare:[url scheme]] != NSOrderedSame)
        return NO;
    
    if (OFISEQUAL(containerURL, url))
        return YES;
    
    NSString *containerPath, *urlPath;

    if ([containerURL isFileURL]) {
        // -[NSFileManager contentsOfDirectoryAtURL:...], when given something in file://localhost/var/mobile/... will return file URLs with non-standarized paths like file://localhost/private/var/mobile/...  Terrible.
        OBASSERT([containerURL isFileURL]);
        containerPath = OFStandardizedPathForFileURL(containerURL, NO);
        urlPath = OFStandardizedPathForFileURL(url, YES);
    } else {
        containerPath = [[containerURL absoluteURL] path];
        urlPath = [[url absoluteURL] path];
    }
    
    if (![containerPath hasSuffix:@"/"])
        containerPath = [containerPath stringByAppendingString:@"/"];
    
    return [urlPath hasPrefix:containerPath];
}

NSString *OFFileURLRelativePath(NSURL *baseURL, NSURL *fileURL)
{
    _assertPlainURL(fileURL);
    _assertPlainURL(baseURL);
    OBPRECONDITION([[[fileURL absoluteURL] path] hasPrefix:[[baseURL absoluteURL] path]]); // Can't compare the prefix in URL encoding since the % encoding can have upper/lowercase differences.
    
    NSString *localBasePath = [[baseURL absoluteURL] path];
    if (![localBasePath hasSuffix:@"/"])
        localBasePath = [localBasePath stringByAppendingString:@"/"];
    
    NSString *localAbsolutePath = [[fileURL absoluteURL] path];
    OBASSERT([localAbsolutePath hasPrefix:localBasePath]);
    
    NSString *localRelativePath = [[localAbsolutePath stringByRemovingPrefix:localBasePath] stringByRemovingSuffix:@"/"];
    OBASSERT(![localRelativePath hasPrefix:@"/"]);
    
    return localRelativePath;
}

BOOL OFGetBoolResourceValue(NSURL *url, NSString *key, BOOL *outValue, NSError **outError)
{
    __autoreleasing NSError *error = nil;
    __autoreleasing NSNumber *numberValue = nil;
    if (![url getResourceValue:&numberValue forKey:key error:&error]) {
        NSLog(@"Error getting resource key %@ for %@: %@", key, url, [error toPropertyList]);
        if (outError)
            *outError = error;
        return NO;
    }
    
    *outValue = [numberValue boolValue];
    return YES;
}


BOOL OFURLIsStandardizedOrMissing(NSURL *url)
{
    OBPRECONDITION([url isFileURL]);
    
    OB_AUTORELEASING NSError *error;
    if (![url checkResourceIsReachableAndReturnError:&error]) {
        if ([error causedByMissingFile])
            return YES; // -URLByStandardizingPath won't do anything useful in this case.
    }
    
    return OFURLEqualsURL([url URLByStandardizingPath], url);
}

BOOL OFURLIsStandardized(NSURL *url)
{
    OBPRECONDITION([url isFileURL]);
    OBPRECONDITION([url checkResourceIsReachableAndReturnError:NULL]); // Don't ask to standardize URLs that don't exist -- -URLByStandardizingPath returns incorrect results in that case
    return OFURLEqualsURL([url URLByStandardizingPath], url);
}


NSURL *OFURLRelativeToDirectoryURL(NSURL *baseURL, NSString *quotedFileName)
{
    if (!baseURL || !quotedFileName)
        return nil;
    
    NSMutableString *urlString = [[baseURL absoluteString] mutableCopy];
    NSRange pathRange = OFURLRangeOfPath(urlString);
    
    if ([urlString rangeOfString:@"/" options:NSAnchoredSearch|NSBackwardsSearch range:pathRange].length == 0) {
        [urlString insertString:@"/" atIndex:NSMaxRange(pathRange)];
        pathRange.length ++;
    }
    
    [urlString insertString:quotedFileName atIndex:NSMaxRange(pathRange)];
    
    NSURL *newURL = [NSURL URLWithString:urlString];
    return newURL;
}

NSURL *OFDirectoryURLForURL(NSURL *url)
{
    NSString *urlString = [url absoluteString];
    NSRange lastComponentRange;
    unsigned trailingSlashLength;
    if (!OFURLRangeOfLastPathComponent(urlString, &lastComponentRange, &trailingSlashLength))
        return url;
    
    NSString *parentURLString = [urlString substringToIndex:lastComponentRange.location];
    NSURL *parentURL = [NSURL URLWithString:parentURLString];
    return parentURL;
}

NSURL * _Nullable OFURLWithNameAffix(NSURL *baseURL, NSString *quotedSuffix, BOOL addSlash, BOOL removeSlash)
{
    OBASSERT(![quotedSuffix containsString:@"/"]);
    OBASSERT(!(addSlash && removeSlash));
    
    NSMutableString *urlString = [[baseURL absoluteString] mutableCopy];
    NSRange pathRange = OFURLRangeOfPath(urlString);
    
    // Can't apply an affix to an empty name. Well, we could, but that would just push the problem off to some other part of XMLData.
    if (!pathRange.length) {
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
    return newURL;
}

BOOL OFURLRangeOfLastPathComponent(NSString *urlString, NSRange *lastComponentRange, unsigned *andTrailingSlash)
{
    if (!urlString)
        return NO;
    
    NSRange pathRange = OFURLRangeOfPath(urlString);
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

// This is a sort of simple 3-way-merge of URLs which we use to rewrite the Destination: header of a MOVE request if the server responds with a redirect of the source URL.
// Generally we're just MOVEing something to rename it within its containing collection. So this function checks to see if that is true, and if so, returns a new Destination: URL which represents the same rewrite within the new collection pointed to by the redirect.
// For more complicated situations, this function just gives up and returns nil; the caller will need to have some way to handle that.

static NSString *OFURLAnalogousRewriteByLastPathComponent(NSURL *oldSourceURL, NSString *oldDestination, NSURL *newSourceURL)
{
    NSString *oldSource = [oldSourceURL absoluteString];
    NSRange oldSourceLastComponent, oldDestinationLastComponent, newSourceLastComponent;
    unsigned oldSourceSlashy, oldDestinationSlashy, newSourceSlashy;
    if (!OFURLRangeOfLastPathComponent(oldDestination, &oldDestinationLastComponent, &oldDestinationSlashy) ||
        !OFURLRangeOfLastPathComponent(oldSource, &oldSourceLastComponent, &oldSourceSlashy)) {
        // Can't parse something.
        return nil;
    }
    
    if (![[oldSource substringToIndex:oldSourceLastComponent.location] isEqualToString:[oldDestination substringToIndex:oldDestinationLastComponent.location]]) {
        // The old source and destination URLs differ in more than just their final path component. Not obvious how to rewrite.
        // (We should maybe be checking the span after the last path component as well, but that's going to be an empty string in any reasonable situation)
        return nil;
    }
    
    NSString *newSource = [newSourceURL absoluteString];
    if (!OFURLRangeOfLastPathComponent(newSource, &newSourceLastComponent, &newSourceSlashy)) {
        // Can't parse something.
        return nil;
    }
    
    if (![[oldSource substringWithRange:oldSourceLastComponent] isEqualToString:[newSource substringWithRange:newSourceLastComponent]]) {
        // The server's redirect changes the final path component, which is the same thing our MOVE is changing. Flee!
        return nil;
    }
    
    NSMutableString *newDestination = [newSource mutableCopy];
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

static NSString *OFURLAnalogousRewriteByHost(NSURL *oldSourceURL, NSString *oldDestination, NSURL *newSourceURL)
{
    NSString *oldSource = [oldSourceURL absoluteString];
    NSRange oldSourceHostRange = OFURLRangeOfHost(oldSource);
    if (oldSourceHostRange.length == 0)
        return nil;
    
    NSString *newSource = [newSourceURL absoluteString];
    NSRange newSourceHostRange = OFURLRangeOfHost(newSource);
    if (newSourceHostRange.length == 0)
        return nil;
    
    if (![[oldSource substringToIndex:oldSourceHostRange.location] isEqual:[newSource substringToIndex:newSourceHostRange.location]]) {
        // Scheme changed
        return nil;
    }
    
    NSString *oldAfterHost = [oldSource substringFromIndex:NSMaxRange(oldSourceHostRange)];
    NSString *newAfterHost = [newSource substringFromIndex:NSMaxRange(newSourceHostRange)];
    if (![oldAfterHost isEqualToString:newAfterHost]) {
        // Something in the path changed
        return nil;
    }
    
    NSRange oldDestinationHostRange = OFURLRangeOfHost(oldDestination);
    if (oldDestinationHostRange.length == 0) {
        // Can't parse the old Destination header
        return nil;
    }
    
    // Swap the new host into the old destination
    NSMutableString *newDestionation = [oldDestination mutableCopy];
    [newDestionation replaceCharactersInRange:oldDestinationHostRange withString:[newSource substringWithRange:newSourceHostRange]];
    
    return newDestionation;
}

NSString *OFURLAnalogousRewrite(NSURL *oldSourceURL, NSString *oldDestination, NSURL *newSourceURL)
{
    if ([oldDestination hasPrefix:@"/"])
        oldDestination = [[NSURL URLWithString:oldDestination relativeToURL:oldSourceURL] absoluteString];
    
    // Check if we are just MOVE/COPYing in the same container
    NSString *newDestination = OFURLAnalogousRewriteByLastPathComponent(oldSourceURL, oldDestination, newSourceURL);
    if (newDestination)
        return newDestination;
    
    // Check if the old URL and new URL are the same except for the host. In this case, we are just hitting some sort of load balancing redirector (like OmniSyncServer).
    newDestination = OFURLAnalogousRewriteByHost(oldSourceURL, oldDestination, newSourceURL);
    if (newDestination)
        return newDestination;
    
    OBASSERT_NOT_REACHED("We don't know how to rewrite this Destination -- are there other situations we can handle?");
    return nil;
}

#pragma mark - Scanning

static OFDeclareDebugLogLevel(OFPackageDebug);
#define DEBUG_PACKAGE(level, format, ...) do { \
    if (OFPackageDebug >= (level)) \
        NSLog(@"PACKAGE: " format, ## __VA_ARGS__); \
    } while (0)

BOOL OFShouldIgnoreURLDuringScan(NSURL *fileURL)
{
    NSString *fileName = [fileURL lastPathComponent];
    if ([fileName caseInsensitiveCompare:@".DS_Store"] == NSOrderedSame)
        return YES;
    if ([fileName caseInsensitiveCompare:@"Icon\r"] == NSOrderedSame)
        return YES;
    return NO;
}

static BOOL OFURLIsStillBeingCreatedOrHasGoneMissing(NSURL *fileURL)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return NO; // Don't bother with all these attribute lookups when they don't matter
#else
    // Skip files that are still being copied in and aren't ready to look at (pretend they aren't there at all). Large copies in Finder will flag the file with kMagicBusyCreationDate. In this case, we'll get called again (and again likely) until the file is uploaded. NSFileBusy is documented, but I can't find any way to get it set.
    // kMagicBusyCreationDate is 0x4F3AFDB0
    // 1904-01-01 00:00:00 +0000
    static NSTimeInterval FileMagicBusyCreationTimeInterval = -3061152000;
    
    // For whole folders of files, Finder uses "1984-01-24 08:00:00 +0000". It doesn't seem to set the kFirstMagicBusyFiletype/kLastMagicBusyFiletype in the document or folder case, as far as I've seen.
    static NSTimeInterval FolderMagicBusyCreationTimeInterval = -534528000;
    
    
    __autoreleasing NSError *resourceError = nil;
    __autoreleasing NSDate *creationDate;
    
    // For individual file/document copies, Finder marks the creation date.
    if (![fileURL getResourceValue:&creationDate forKey:NSURLCreationDateKey error:&resourceError]) {
        if ([resourceError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]) {
            // Gone missing.
            return YES;
        } else
            NSLog(@"Unable to determine if %@ is being created: %@", fileURL, [resourceError toPropertyList]);
        return NO;
    }
    
    NSTimeInterval creationTimeInterval = [creationDate timeIntervalSinceReferenceDate];
    
    return (creationTimeInterval == FileMagicBusyCreationTimeInterval || creationTimeInterval == FolderMagicBusyCreationTimeInterval);
#endif
}

// We no longer use an NSFileCoordinator when scanning the documents directory. NSFileCoordinator doesn't make writers of documents wait if there is a coordinator of their containing directory, so this doesn't help. We *could*, as we find documents, do a coordinated read on each document to make sure we get its most recent timestamp, but this seems wasteful in most cases.
static void _OFScanDirectory(NSURL *directoryURL, BOOL shouldRecurse,
                             _Nullable OFScanDirectoryFilter filterBlock,
                             OFScanPathExtensionIsPackage pathExtensionIsPackage,
                             OFScanDirectoryItemHandler itemHandler,
                             OFScanErrorHandler errorHandler)
{
    NSMutableArray *scanDirectoryURLs = [NSMutableArray arrayWithObjects:directoryURL, nil];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    while ([scanDirectoryURLs count] != 0) {
        NSURL *scanDirectoryURL = [scanDirectoryURLs lastObject]; // We're building a set, and it's faster to remove the last object than the first
        [scanDirectoryURLs removeLastObject];
        
        // It is important to skip busy-creation folders too since the documents inside them don't get any magic timestamp (so we could end up looking at a partial document).
        if (OFURLIsStillBeingCreatedOrHasGoneMissing(scanDirectoryURL))
            continue;
        
        __autoreleasing NSError *contentsError = nil;
        NSArray *fileURLs = [fileManager contentsOfDirectoryAtURL:scanDirectoryURL includingPropertiesForKeys:[NSArray arrayWithObject:NSURLIsDirectoryKey] options:0 error:&contentsError];
        if (!fileURLs) {
            NSLog(@"Unable to scan documents in %@: %@", scanDirectoryURL, [contentsError toPropertyList]);
            if (errorHandler && !errorHandler(scanDirectoryURL, contentsError))
                return;
        }
        
        for (__strong NSURL *fileURL in fileURLs) {
            // Built-in filter
            if (OFShouldIgnoreURLDuringScan(fileURL))
                continue;
            
            // We do NOT use UTIs for determining if a folder is a file package (meaning we should treat it as a document). We might not have UTIs registered in this app for all the document types that might be present (a newer app version might have placed something in the container that an older version doesn't understand, and Launch Service might go insane and not even correctly report the UTIs in our Info.plist). Instead, we get passed a block that determines whether a directory is a package. OmniPresence clients register containers by path extension, which other clients see and then start treating as packages. For the case where we explicitly want a folder, we have OFDirectoryPathExtension. If a user makes a folder "2013.foo", we'll silently name it "2013.foo.folder" and will hide that path extension. This helps avoid worries that "foo" might someday become a package extension by some as-yet invented app. Obviously, this isn't totally impervious to screw-ups, but our frameworks will do their best to ignore the UTI database for this path extension and always treat it as a folder.
            __autoreleasing NSNumber *isDirectoryValue = nil;
            __autoreleasing NSError *resourceError = nil;
            if (![fileURL getResourceValue:&isDirectoryValue forKey:NSURLIsDirectoryKey error:&resourceError]) {
                NSLog(@"Unable to determine if %@ is a directory: %@", fileURL, [resourceError toPropertyList]);
                if (errorHandler && !errorHandler(fileURL, resourceError))
                    return;
            }
            
            // NSFileManager hands back non-standardized URLs even if the input is standardized.
            OBASSERT(isDirectoryValue);
            BOOL isDirectory = [isDirectoryValue boolValue];
            fileURL = [scanDirectoryURL URLByAppendingPathComponent:[fileURL lastPathComponent] isDirectory:isDirectory];
            
            if (filterBlock && !filterBlock(fileURL))
                continue;
            
            NSString *pathExtension = [fileURL pathExtension];
            if (isDirectory) {
                BOOL isPackage;
                if ([NSString isEmptyString:pathExtension])
                    isPackage = NO;
                else if (pathExtensionIsPackage) {
                    // Even if someone mistakenly gets a container in their OmniPresence with this path extension, we will never accept that it is.
                    isPackage = pathExtensionIsPackage(pathExtension) && ![pathExtension isEqualToString:OFDirectoryPathExtension];
                    DEBUG_PACKAGE(1, @"\"%@\" package:%d", pathExtension, isPackage);
                } else {
                    OBASSERT_NOT_REACHED("Cannot tell if a path extension is a package... should we allow this at all?");
                    isPackage = NO;
                }
                
                if (isPackage) {
                    // Fall through and treat it as an item
                } else {
                    // Should be treated as a folder
                    if (shouldRecurse)
                        [scanDirectoryURLs addObject:fileURL];
                    continue; // We don't want to create an item if the fileURL points to a directory.
                }
            } else {
                // <bug:///94055> (Deal with flat files that get the 'folder' path extension)
            }
            
            if (OFURLIsStillBeingCreatedOrHasGoneMissing(fileURL))
                continue;
            itemHandler(fileManager, fileURL);
        }
    }
}

// It's generally a bad idea to block the main queue with filesystem operations, so we have two versions here -- one that can be searched for independently for blocking.

void OFScanDirectory(NSURL *directoryURL, BOOL shouldRecurse,
                     _Nullable OFScanDirectoryFilter filterBlock,
                     OFScanPathExtensionIsPackage pathExtensionIsPackage,
                     OFScanDirectoryItemHandler itemHandler,
                     OFScanErrorHandler errorHandler)
{
    OBPRECONDITION([NSOperationQueue currentQueue] != [NSOperationQueue mainQueue], "bug:///137297");
    _OFScanDirectory(directoryURL, shouldRecurse, filterBlock, pathExtensionIsPackage, itemHandler, errorHandler);
}

void OFScanDirectoryAllowMainQueue(NSURL *directoryURL, BOOL shouldRecurse,
                                   _Nullable OFScanDirectoryFilter filterBlock,
                                   OFScanPathExtensionIsPackage pathExtensionIsPackage,
                                   OFScanDirectoryItemHandler itemHandler,
                                   OFScanErrorHandler errorHandler)
{
    _OFScanDirectory(directoryURL, shouldRecurse, filterBlock, pathExtensionIsPackage, itemHandler, errorHandler);
}

OFScanPathExtensionIsPackage OFIsPackageWithKnownPackageExtensions(NSSet * _Nullable packageExtensions)
{
    DEBUG_PACKAGE(1, @"Creating block with extensions %@", [[packageExtensions allObjects] sortedArrayUsingSelector:@selector(compare:)]);
    
    // Don't cache the list of package extensions forever. Installing a new application between sync operations might make a file that previously existed turn into a package.
    NSMutableDictionary *extensionToIsPackage = [NSMutableDictionary new];
    
    OFScanPathExtensionIsPackage isPackage = ^BOOL(NSString *pathExtension){
        pathExtension = [pathExtension lowercaseString];
        
        // Our OFTypeConformsTo() of local types below would hopefully catch this, but it might not since it uses depends on LaunchServices registration. Thus, it will only catch types that LaunchServices really knows about (whereas we fill in _localPackagePathExtensions by inspecting our UTI definitions directly).
        if ([packageExtensions member:pathExtension])
            return YES;
        
        NSNumber *cachedValue = extensionToIsPackage[pathExtension];
        if (cachedValue)
            return [cachedValue boolValue];

        __block BOOL foundPackage = NO;
        OFUTIEnumerateKnownTypesForTagPreferringNative((NSString *)kUTTagClassFilenameExtension, pathExtension, nil/*conformingToUTIOrNil*/, ^(NSString *typeIdentifier, BOOL *stop){
            // We check conformance here rather than passing in kUTTypePackage to OFUTIEnumerateKnownTypesForTagPreferringNative. The underlying UTTypeCreateAllIdentifiersForTag will *generate* a dynamic type that conforms to what we pass in instead of just returning an empty array.
            if (OFTypeConformsTo(typeIdentifier, kUTTypePackage)) {
                foundPackage = YES;
                *stop = YES;
            }
        });
        
        if (foundPackage && [pathExtension isEqual:OFDirectoryPathExtension]) {
            OBASSERT_NOT_REACHED("OFDirectoryPathExtension is our explicitly-not-a package extension -- did some app declare it as a package?");
            foundPackage = NO;
        }
        
        extensionToIsPackage[pathExtension] = @(foundPackage);
        return foundPackage;
    };
    
    return [isPackage copy];
}

NS_ASSUME_NONNULL_END
