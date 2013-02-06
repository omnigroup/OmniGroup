// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSURL.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif
#import <OmniFoundation/OFUTI.h>

RCS_ID("$Id$")

#if 0
NSString * const OFSDocumentStoreFolderPathExtension = @"folder";

BOOL OFSIsFolder(NSURL *URL)
{
    return [[URL pathExtension] caseInsensitiveCompare:OFSDocumentStoreFolderPathExtension] == NSOrderedSame;
}

NSString *OFSFolderNameForFileURL(NSURL *fileURL)
{
    NSURL *containerURL = [fileURL URLByDeletingLastPathComponent];
    if (OFSIsFolder(containerURL))
        return [containerURL lastPathComponent];
    return nil;
}
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
NSString * const OFSDocumentInteractionInboxFolderName = @"Inbox";

BOOL OFSInInInbox(NSURL *url)
{
    // Check to see if the URL directly points to the Inbox.
    if (([[url lastPathComponent] caseInsensitiveCompare:OFSDocumentInteractionInboxFolderName] == NSOrderedSame)) {
        return YES;
    }
    
    // URL does not directly point to Inbox, check if it points to a file directly in the Inbox.
    NSURL *pathURL = [url URLByDeletingLastPathComponent]; // Remove the filename.
    NSString *lastPathComponentString = [pathURL lastPathComponent];
    
    return ([lastPathComponentString caseInsensitiveCompare:OFSDocumentInteractionInboxFolderName] == NSOrderedSame);
}

BOOL OFSIsZipFileType(NSString *uti)
{
    // Check both of the semi-documented system UTIs for zip (in case one goes away or something else weird happens).
    // Also check for a temporary hack UTI we had, in case the local LaunchServices database hasn't recovered.
    return UTTypeConformsTo((__bridge CFStringRef)uti, CFSTR("com.pkware.zip-archive")) ||
    UTTypeConformsTo((__bridge CFStringRef)uti, CFSTR("public.zip-archive")) ||
    UTTypeConformsTo((__bridge CFStringRef)uti, CFSTR("com.omnigroup.zip"));
}
#endif

OFSScanDirectoryFilter OFSScanDirectoryExcludeInboxItemsFilter(void)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return [^BOOL(NSURL *fileURL){
        // We never want to acknowledge files in the inbox directly. Instead they'll be dealt with when they're handed to us via document interaction and moved.
        return OFSInInInbox(fileURL) == NO;
    } copy];
#else
    return nil; // No Inbox support on the Mac
#endif
};

BOOL OFSShouldIgnoreURLDuringScan(NSURL *fileURL)
{
    if ([[fileURL lastPathComponent] caseInsensitiveCompare:@".DS_Store"] == NSOrderedSame)
        return YES;
    return NO;
}

// We no longer use an NSFileCoordinator when scanning the documents directory. NSFileCoordinator doesn't make writers of documents wait if there is a coordinator of their containing directory, so this doesn't help. We *could*, as we find documents, do a coordinated read on each document to make sure we get its most recent timestamp, but this seems wasteful in most cases.
void OFSScanDirectory(NSURL *directoryURL, BOOL shouldRecurse,
                      OFSScanDirectoryFilter filterBlock,
                      OFSScanPathExtensionIsPackage pathExtensionIsPackage,
                      OFSScanDirectoryItemHandler itemHandler)
{
    OBASSERT(![NSThread isMainThread]);
    
    NSMutableArray *scanDirectoryURLs = [NSMutableArray arrayWithObjects:directoryURL, nil];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    while ([scanDirectoryURLs count] != 0) {
        NSURL *scanDirectoryURL = [scanDirectoryURLs lastObject]; // We're building a set, and it's faster to remove the last object than the first
        [scanDirectoryURLs removeLastObject];
        
        NSError *contentsError = nil;
        NSArray *fileURLs = [fileManager contentsOfDirectoryAtURL:scanDirectoryURL includingPropertiesForKeys:[NSArray arrayWithObject:NSURLIsDirectoryKey] options:0 error:&contentsError];
        if (!fileURLs)
            NSLog(@"Unable to scan documents in %@: %@", scanDirectoryURL, [contentsError toPropertyList]);
        
        for (__strong NSURL *fileURL in fileURLs) {
            // Built-in filter
            if (OFSShouldIgnoreURLDuringScan(fileURL))
                continue;
            
            // We do NOT use UTIs for determining if a folder is a file package (meaning we should treat it as a document). We might not have UTIs registered in this app for all the document types that might be present (a newer app version might have placed something in the container that an older version doesn't understand, and Launch Service might go insane and not even correctly report the UTIs in our Info.plist). Instead, any folder that has an extension that isn't OFSDocumentStoreFolderPathExtension is considered a package.
            // This does mean that folders *must* have the special extension, or no extension, or we'll treat them like file packages. This may be why iWork uses this approach, otherwise a user might create a folder called "2012.01 Presentations" and suddenly the app might think it was a file package from some future version.
            NSNumber *isDirectoryValue = nil;
            NSError *resourceError = nil;
            if (![fileURL getResourceValue:&isDirectoryValue forKey:NSURLIsDirectoryKey error:&resourceError])
                NSLog(@"Unable to determine if %@ is a directory: %@", fileURL, [resourceError toPropertyList]);
            
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
                    isPackage = pathExtensionIsPackage(pathExtension);
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
            }
            
            itemHandler(fileManager, fileURL);
        }
    }
}

OFSScanPathExtensionIsPackage OFSIsPackageWithKnownPackageExtensions(NSSet *packageExtensions)
{
    // Don't cache the list of package extensions forever. Installing a new application between sync operations might make a file that previously existed turn into a package.
    NSMutableDictionary *extensionToIsPackage = [NSMutableDictionary new];
    
    OFSScanPathExtensionIsPackage isPackage = ^BOOL(NSString *pathExtension){
        pathExtension = [pathExtension lowercaseString];
        
        // Our UTTypeConformsTo() of local types below would hopefully catch this, but it might not since it uses depends on LaunchServices registration. Thus, it will only catch types that LaunchServices really knows about (whereas we fill in _localPackagePathExtensions by inspecting our UTI definitions directly).
        if ([packageExtensions member:pathExtension])
            return YES;
                
        NSNumber *cachedValue = extensionToIsPackage[pathExtension];
        if (cachedValue)
            return [cachedValue boolValue];
        
        __block BOOL foundPackage = NO;
        OFUTIEnumerateKnownTypesForTagPreferringNative((NSString *)kUTTagClassFilenameExtension, pathExtension, nil/*conformingToUTIOrNil*/, ^(NSString *typeIdentifier, BOOL *stop){
            // We check conformance here rather than passing in kUTTypePackage to OFUTIEnumerateKnownTypesForTagPreferringNative. The underlying UTTypeCreateAllIdentifiersForTag will *generate* a dynamic type that conforms to what we pass in instead of just returning an empty array.
            if (UTTypeConformsTo((__bridge CFStringRef)typeIdentifier, kUTTypePackage)) {
                foundPackage = YES;
                *stop = YES;
            }
        });
        
        extensionToIsPackage[pathExtension] = @(foundPackage);
        return foundPackage;
    };
    
    return [isPackage copy];
}

BOOL OFSGetBoolResourceValue(NSURL *url, NSString *key, BOOL *outValue, NSError **outError)
{
    NSError *error = nil;
    NSNumber *numberValue = nil;
    if (![url getResourceValue:&numberValue forKey:key error:&error]) {
        NSLog(@"Error getting resource key %@ for %@: %@", key, url, [error toPropertyList]);
        if (outError)
            *outError = error;
        return NO;
    }
    
    *outValue = [numberValue boolValue];
    return YES;
}


static void _assertPlainURL(NSURL *url)
{
    OBPRECONDITION([NSString isEmptyString:[url fragment]]);
    OBPRECONDITION([NSString isEmptyString:[url parameterString]]);
    OBPRECONDITION([NSString isEmptyString:[url query]]);
}

static NSString *_standardizedPathForURL(NSURL *url)
{
    OBASSERT([url isFileURL]);
    NSString *urlPath = [[url absoluteURL] path];
    
    NSString *path = [[urlPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
    
    // In some cases this doesn't normalize /private/var/mobile and /var/mobile to the same thing.
    path = [path stringByRemovingPrefix:@"/var/mobile/"];
    path = [path stringByRemovingPrefix:@"/private/var/mobile/"];
    
    return path;
}

BOOL OFSURLContainsURL(NSURL *containerURL, NSURL *url)
{
    _assertPlainURL(url);
    _assertPlainURL(containerURL);

    if (!containerURL)
        return NO;
    
    // -[NSFileManager contentsOfDirectoryAtURL:...], when given something in file://localhost/var/mobile/... will return file URLs with non-standarized paths like file://localhost/private/var/mobile/...  Terrible.
    OBASSERT([containerURL isFileURL]);
    
    NSString *urlPath = _standardizedPathForURL(url);
    NSString *containerPath = _standardizedPathForURL(containerURL);
    
    if (![containerPath hasSuffix:@"/"])
        containerPath = [containerPath stringByAppendingString:@"/"];
    
    return [urlPath hasPrefix:containerPath];
}

NSString *OFSFileURLRelativePath(NSURL *baseURL, NSURL *fileURL)
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

BOOL OFSURLIsStandardized(NSURL *url)
{
    OBPRECONDITION([url checkResourceIsReachableAndReturnError:NULL]); // Don't ask to standardize URLs that don't exist -- -URLByStandardizingPath returns incorrect results in that case
    return [url isEqual:[url URLByStandardizingPath]];
}
