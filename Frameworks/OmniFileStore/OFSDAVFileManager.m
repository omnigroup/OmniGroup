// Copyright 2008-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDAVFileManager.h>

#import "OFSDAVFileManager-Reachability.h"
#import "OFSDAVFileManager-Network.h"
#import "OFSDAVOperation.h"

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSFileInfo.h>

#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/NSString-OFURLEncoding.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFUtilities.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIDevice.h>
#endif

#import <sys/sysctl.h>

RCS_ID("$Id$");

@interface OFSDAVFileManager (Private)
- (NSArray *)_propfind:(NSURL *)url depth:(NSString *)depth redirects:(NSMutableArray *)redirs error:(NSError **)outError;
- (NSMutableArray *)_recursivelyCollectDirectoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections options:(OFSDirectoryEnumerationOptions)options error:(NSError **)outError;
@end

static const NSURLRequestCachePolicy DefaultCachePolicy = NSURLRequestUseProtocolCachePolicy;
static const NSTimeInterval DefaultTimeoutInterval = 300.0;
static NSString *StandardUserAgentString;

// TODO: once iOS supports private api like SecTrustSettingsSetTrustSettings, can get rid of TrustedHosts
static NSMutableSet *TrustedHosts;

NSString * const OFSMobileMeHost = @"idisk.me.com";
NSString * const OFSTrustedSyncHostPreference = @"OFSTrustedSyncHostPreference";

@implementation OFSDAVFileManager

#if TARGET_IPHONE_SIMULATOR
#define DEFAULT_HARDWARE_MODEL @"iPhone Simulator"
#elif TARGET_OS_IPHONE
#define DEFAULT_HARDWARE_MODEL @"iPhone"
#else
#define DEFAULT_HARDWARE_MODEL @"Mac"
#endif

static NSString *OFSDAVHardwareModel(void)
{
    int name[] = {CTL_HW, HW_MODEL};
    const int nameCount = sizeof(name) / sizeof(*name);
    size_t bufSize = 0;
    
    // Passing a null pointer just says we want to get the size out
    if (sysctl(name, nameCount, NULL, &bufSize, NULL, 0) < 0) {
	perror("sysctl");
	return DEFAULT_HARDWARE_MODEL;
    }
    
    char *value = calloc(1, bufSize + 1);
    
    if (sysctl(name, nameCount, value, &bufSize, NULL, 0) < 0) {
	// Not expecting any errors now!
	free(value);
	perror("sysctl");
	return DEFAULT_HARDWARE_MODEL;
    }
    
    NSString *hardwareModel = NSMakeCollectable(CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, value, kCFStringEncodingUTF8, kCFAllocatorMalloc));
    
    return [hardwareModel autorelease];
}

static NSString *ClientComputerName(void)
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    return OFHostName();
#else
    return [[UIDevice currentDevice] name];
#endif
}

static NSString *OFSDAVDepth(int depth)
{
    NSString *depthString = nil;
    switch (depth) {
        case 0:     /* local; returns file */
            depthString = @"0";
            break;
        case 1:     /* children; returns direct descendants */
            depthString = @"1";
            break;
        default:    /* all; deep, recursive descendants */
            depthString = @"infinity";
            break;
    }
    return depthString;
}

+ (void)initialize;
{
    OBINITIALIZE;

    NSString *osVersionString = [[OFVersionNumber userVisibleOperatingSystemVersionNumber] originalVersionString];
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [bundleInfo objectForKey:(NSString *)kCFBundleNameKey];
    NSString *appVersionString = [bundleInfo objectForKey:(NSString *)kCFBundleVersionKey];
    NSString *hardwareModel = [NSString encodeURLString:OFSDAVHardwareModel() asQuery:NO leaveSlashes:YES leaveColons:YES];
    NSString *clientName = [NSString encodeURLString:ClientComputerName() asQuery:NO leaveSlashes:YES leaveColons:YES];
    
    StandardUserAgentString = [[NSString alloc] initWithFormat:@"%@/%@ Darwin/%@ (%@) (%@)", appName, appVersionString, osVersionString, hardwareModel, clientName];
    TrustedHosts = [[NSMutableSet alloc] init];
}

- initWithBaseURL:(NSURL *)baseURL error:(NSError **)outError;
{    
    if (!(self = [super initWithBaseURL:baseURL error:outError]))
        return nil;
    
    if (![[[self baseURL] path] isAbsolutePath]) {
        NSString *title =  NSLocalizedStringFromTableInBundle(@"An error has occurred.", @"OmniFileStore", OMNI_BUNDLE, @"error title");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Ensure that the server address, user name, and password are correct and please try again.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        OFSError(outError, OFSBaseURLIsNotAbsolute, title, description);
        
        NSLog(@"Error: The path of the url \"%@\" is not absolute. Cannot create DAV-based file manager.", [self baseURL]);
        [self release];
        return nil;
    }
        
    return self;
}

#pragma mark API

+ (NSString *)standardUserAgentString;
{
    return StandardUserAgentString;
}

static id <OFSDAVFileManagerUserAgentDelegate> UserAgentDelegate = nil;

+ (void)setUserAgentDelegate:(id <OFSDAVFileManagerUserAgentDelegate>)delegate;
{
    UserAgentDelegate = delegate;
}

+ (id <OFSDAVFileManagerUserAgentDelegate>)userAgentDelegate;
{
    return UserAgentDelegate;
}

static void OFSDAVAddUserAgentStringToRequest(OFSDAVFileManager *manager, NSMutableURLRequest *request)
{
    NSString *userAgent = StandardUserAgentString;
    if (UserAgentDelegate)
        userAgent = [UserAgentDelegate DAVFileManager:manager userAgentForRequest:request];
    if (userAgent)
        [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
}

static id <OFSDAVFileManagerAuthenticationDelegate> AuthenticationDelegate = nil;

+ (void)setAuthenticationDelegate:(id <OFSDAVFileManagerAuthenticationDelegate>)delegate;
{
    AuthenticationDelegate = delegate;
}

+ (id <OFSDAVFileManagerAuthenticationDelegate>)authenticationDelegate;
{
    return AuthenticationDelegate;
}

+ (BOOL)isTrustedHost:(NSString *)host;
{
    return [TrustedHosts containsObject:host];
}

+ (void)setTrustedHost:(NSString *)host;
{
    [TrustedHosts addObject:host];
}

+ (void)removeTrustedHost:(NSString *)host;
{
    [TrustedHosts removeObject:host];
}

#pragma mark OFSFileManager subclass

- (id <OFSAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url withTarget:(id <OFSFileManagerAsynchronousOperationTarget>)target;
{
    OBPRECONDITION(target); // Call the synchronous version otherwise.
    
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: GET %@", url);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"GET"]; // really the default, but just for conformity with the others...
    
    OFSDAVOperation *operation = [[[OFSDAVOperation alloc] initWithFileManager:self request:request target:target] autorelease];
    OBASSERT(operation != nil); // Otherwise we should call [target fileManager:self didFailWithError:nil];

    // DO NOT launch the operation here. The caller should do this so it can assign it to an ivar or otherwise store it before it has to expect any callbacks.
    
    return operation;
}

- (id <OFSAsynchronousOperation>)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically withTarget:(id <OFSFileManagerAsynchronousOperationTarget>)target;
{
    OBPRECONDITION(target); // Call the synchronous version otherwise.

    // We need to PUT to a temporary location and the MOVE for this to work.  Right now we don't need atomic support.
    OBPRECONDITION(atomically == NO);
    
    // TODO: What guarantees does WebDAV make about PUT command atomicity?  Do servers have bugs with this?  We could generate a crazy tmp file name and move it afterward, but we'd have to make assumptions about where we can put that file or what we can name it to make it 'invisible' while we are writing it.
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: PUT %@ (data of %ld bytes)", url, [data length]);

#ifdef OFSDAVForceReadOnly
    [target fileManager:self
       didFailWithError:[NSError errorWithDomain:OFSErrorDomain
                                            code:OFSCannotWriteFile 
                                        userInfo:[NSDictionary dictionaryWithObject:@"Read-only!" forKey:NSLocalizedDescriptionKey]]];
#endif
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:data];
    
    OFSDAVOperation *operation = [[[OFSDAVOperation alloc] initWithFileManager:self request:request target:target] autorelease];
    OBASSERT(operation != nil); // Otherwise we should call [target fileManager:self didFailWithError:nil];

    // DO NOT launch the operation here. The caller should do this so it can assign it to an ivar or otherwise store it before it has to expect any callbacks.

    return operation;
}

#pragma mark OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;
{
    return YES;
}

// TODO: Ensure that the input urls are within the specified URL.  Either need to check this directly, or require that they are relative.

- (OFSFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    NSError *localError = nil;
    NSArray *fileInfos = [self _propfind:url depth:OFSDAVDepth(0) redirects:nil error:&localError];
    if (!fileInfos) {
        if ([[localError domain] isEqualToString:OFSDAVHTTPErrorDomain]) {
            NSInteger code = [localError code];
            
            // A 406 Not Acceptable means that there is something possibly similar to what we asked for with a different content type than we specified in our Accepts header.
            // This is goofy since we didn't ASK for the resource contents, but its properties and our "text/xml" Accepts entry was for the format of the returned properties.
            // MobileMe doesn't return this, but Apache does on sync.omnigroup.com (at least with the current configuration as of this writing) if we do a PROPFIND for "Foo" and there is a "Foo.txt".
            if (code == 404 || code == 406) {
                // The resource was legitimately not found.
                return [[[OFSFileInfo alloc] initWithOriginalURL:url name:nil exists:NO directory:NO size:0 lastModifiedDate:nil] autorelease];
            }
        }
        
        // Some other error; pass it up
        if (outError)
            *outError = localError;
        return nil;
    }
    
    if ([fileInfos count] == 0) {
        // This really doesn't make sense. But translate it to an error rather than raising an exception below.
        if (outError)
            *outError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:[NSDictionary dictionaryWithObject:url forKey:OFSURLErrorFailingURLErrorKey]];
        return nil;
    }

    OFSFileInfo *fileInfo = [fileInfos objectAtIndex:0];
#ifdef OMNI_ASSERTIONS_ON
    {
        NSURL *foundURL = [fileInfo originalURL];
        if (!OFISEQUAL(url, foundURL)) {
            NSLog(@"url: %@", url);
            NSLog(@"foundURL: %@", foundURL);
            OBASSERT(OFISEQUAL([OFSFileInfo nameForURL:url], [OFSFileInfo nameForURL:foundURL])); // Any issues with encoding normalization or whatnot?
        }
    }
#endif
    
    return fileInfo;
}

- (NSMutableArray *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections options:(OFSDirectoryEnumerationOptions)options error:(NSError **)outError;
{
    NSArray *fileInfos = [self _propfind:url depth:((options & OFSDirectoryEnumerationSkipsSubdirectoryDescendants) ? OFSDAVDepth(1) : OFSDAVDepth(-1)) redirects:redirections error:outError];
    if (!fileInfos) {
        if (outError != NULL && [[*outError domain] isEqualToString:OFSDAVHTTPErrorDomain]) {
            if ([*outError code] == 404) {
                // The resource was legitimately not found.
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No document exists at \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason - listing contents of a nonexistent directory"), url];
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to read document.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
                OFSError(outError, OFSNoSuchDirectory, description, reason);
            } else if (!(options & OFSDirectoryEnumerationSkipsSubdirectoryDescendants) && (options & OFSDirectoryEnumerationForceRecursiveDirectoryRead) && [*outError code] == 403 /* 'forbidden' */) {
                /* possible that 'depth:infinity' not supported on this server but still want results */
                *outError = nil;
                return [self _recursivelyCollectDirectoryContentsAtURL:url collectingRedirects:redirections options:options error:outError];
            }
            
        }
        return nil;
    }

    NSURL *expectedDirectoryURL = ( redirections && [redirections count] )? [[redirections lastObject] objectForKey:kOFSRedirectedTo] : nil;
    if (!expectedDirectoryURL)
        expectedDirectoryURL = url;
        
    if ([fileInfos count] == 1) {
        // If we only got info about one resource, and it's not a collection, then we must have done a PROPFIND on a non-collection
        OFSFileInfo *info = [fileInfos objectAtIndex:0];
        if (![info isDirectory]) {
            // Is there a better error code for this? Do any of our callers distinguish this case from general failure?
            if (outError)
                *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOTDIR userInfo:[NSDictionary dictionaryWithObject:url forKey:OFSURLErrorFailingURLStringErrorKey]];
            return nil;
        }
        // Otherwise, it's just that the collection is empty.
    }
    
    NSMutableArray *contents = [NSMutableArray array];
    
    OFSFileInfo *containerInfo = nil;
    
    for (OFSFileInfo *info in fileInfos) {
        if (![info exists]) {
            OBASSERT_NOT_REACHED("Why would we list something that doesn't exist?"); // Maybe if a <prop> element comes back 404 or with some other error?  We aren't even looking at the per entry status yet.
            continue;
        }
        
        // The directory itself will be in the property results.
        // We don't necessarily know what its name will be, though.
        if (!containerInfo && [[info originalURL] isEqual:expectedDirectoryURL]) {
            containerInfo = info;
            // Don't return the container itself in the results list.
            continue;
        }
        
        if ((options & OFSDirectoryEnumerationSkipsHiddenFiles) && [[info name] hasPrefix:@"."]) {
            continue;
        }
        
        if ([[info name] hasPrefix:@"._"]) {
            // Ignore split resource fork files; these presumably happen when moving between filesystems.
            continue;
        }
        
        [contents addObject:info];
    }
    
    if (!containerInfo && [contents count]) {
        // Somewhat unexpected: we never found the fileinfo corresponding to the container itself.
        // My reading of RFC4918 [5.2] is that all of the contained items MUST have URLs consisting of the container's URL plus one path component.
        // (The resources may be available at other URLs as well, but I *think* those URLs will not be returned in our multistatus.)
        // If so, and ignoring the possibility of resources with zero-length names, the container will be the item with the shortest path.
        
        NSUInteger shortestIndex = 0;
        NSUInteger shortestLength = [[[[contents objectAtIndex:shortestIndex] originalURL] path] length];
        for (NSUInteger infoIndex = 1; infoIndex < [contents count]; infoIndex ++) {
            OFSFileInfo *contender = [contents objectAtIndex:infoIndex];
            NSUInteger contenderLength = [[[contender originalURL] path] length];
            if (contenderLength < shortestLength) {
                shortestIndex = infoIndex;
                shortestLength = contenderLength;
            }
        }
        
        containerInfo = [contents objectAtIndex:shortestIndex];

        if (redirections) {
            if (OFSFileManagerDebug > 0) {
                NSLog(@"PROPFIND rewrite <%@> -> <%@>", expectedDirectoryURL, [containerInfo originalURL]);
            }
            
            OFSAddRedirectEntry(redirections, kOFSRedirectPROPFIND, expectedDirectoryURL, [containerInfo originalURL], nil /* PROPFIND is not cacheable */ );
        }

        [contents removeObjectAtIndex:shortestIndex];
    }
    
    // containerInfo is still in fileInfos, so it won't have been deallocated yet
    OBASSERT([containerInfo isDirectory]);
    
    return contents;
}

- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension options:(OFSDirectoryEnumerationOptions)options error:(NSError **)outError;
{
    NSMutableArray *fileInfos = [self directoryContentsAtURL:url collectingRedirects:nil options:options error:outError];
    if (!fileInfos)
        return nil;
    
    NSUInteger infoIndex = [fileInfos count];
    while (infoIndex--) {
        OFSFileInfo *info = [fileInfos objectAtIndex:infoIndex];
        
        NSString *filename = [info name];
        
        // Verify the extension after decoding, in case the extension has something quote-worth.
        if (extension && [[filename pathExtension] caseInsensitiveCompare:extension] != NSOrderedSame) {
            [fileInfos removeObjectAtIndex:infoIndex];
            continue;
        }
    }

    return fileInfos;
}

- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    return [self directoryContentsAtURL:url havingExtension:extension options:OFSDirectoryEnumerationSkipsSubdirectoryDescendants error:outError];
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: GET %@", url);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"GET"]; // really the default, but just for conformity with the others...
    return [self _rawDataByRunningRequest:request operation:NULL error:outError];
}

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: PUT %@ (data of %ld bytes) atomically:%d", url, [data length], atomically);

#ifdef OFSDAVForceReadOnly
    OFSError(outError, OFSCannotWriteFile, @"Read-only!", nil);
    return nil;
#endif
    
    // PUT is not atomic.  By itself it will just stream the file right into place; if the transfer is interrupted, it'll just leave a partial turd there.
    if (atomically) {
        // Do a non-atomic PUT to a temporary location.  The name needs to be something that won't get picked up by XMLTransactionGraph or XMLSynchronizer (which use file extensions).  We don't have a temporary directory on the DAV server.
        // TODO: Use the "POST to unique filename" feature if this DAV server supports it --- we'll need to do discovery, but we can do that for free in our initial PROPFIND. See ftp://ftp.ietf.org/internet-drafts/draft-reschke-webdav-post-08.txt. 
        NSString *temporaryNameSuffix = [@"-write-in-progress-" stringByAppendingString:[OFXMLCreateID() autorelease]];
        NSURL *temporaryURL = OFSURLWithNameAffix(url, temporaryNameSuffix, NO, YES);
        
        NSURL *actualTemporaryURL = [self writeData:data toURL:temporaryURL atomically:NO error:outError];
        if (!actualTemporaryURL)
            return nil;
        
        NSURL *finalURL = url;
        if (![actualTemporaryURL isEqual:temporaryURL]) {
            NSString *rewrittenFinalURL = OFSURLAnalogousRewrite(temporaryURL, [url absoluteString], actualTemporaryURL);
            if (rewrittenFinalURL)
                finalURL = [NSURL URLWithString:rewrittenFinalURL];
        }
        
        // MOVE the fully written data into place.
        BOOL success = [self moveURL:actualTemporaryURL toURL:finalURL error:outError];
        // TODO: Try to delete the temporary file if MOVE fails?
        return ( success ? finalURL : nil );
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:data];
    return [self _runRequestExpectingEmptyResultData:request error:outError];
}

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: MKCOL %@", url);
#ifdef OFSDAVForceReadOnly
    OFSError(outError, OFSCannotCreateDirectory, @"Read-only!", nil);
    return nil;
#endif
        
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"MKCOL"];
    return [self _runRequestExpectingEmptyResultData:request error:outError];
}

- (BOOL)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: MOVE %@ to %@", sourceURL, destURL);
#ifdef OFSDAVForceReadOnly
    OFSError(outError, OFSCannotMove, @"Read-only!", nil);
    return NO;
#endif
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:sourceURL cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"MOVE"];
    
    // .Mac WebDAV accepts the just path the portion as the Destination, but normal OSXS doesn't.  It'll give a 400 Bad Request if we try that.  So, we send the full URL as the Destination.
    NSString *destination = [destURL absoluteString];
    [request setValue:destination forHTTPHeaderField:@"Destination"];
    [request setValue:@"T" forHTTPHeaderField:@"Overwrite"];

    NSError *error = nil;
    if ([self _runRequestExpectingEmptyResultData:request error:&error])
        return YES;

    // Work around for <bug://bugs/48303> (Some https servers incorrectly return Bad Gateway (502) for a MOVE to a destination with an https URL [bingodisk])
    if ([[error domain] isEqualToString:OFSDAVHTTPErrorDomain] && [error code] == 502 && [destination hasPrefix:@"https"]) {        
        // Try again with an http destination instead
        destination = [@"http" stringByAppendingString:[destination stringByRemovingPrefix:@"https"]];
        [request setValue:destination forHTTPHeaderField:@"Destination"];
        if (![self _runRequestExpectingEmptyResultData:request error:&error]) {
            if (outError != NULL)
                *outError = error;
            return NO;
        }
        error = nil; // clear our error since if we return YES with a non-nil error, the calling code can do things like release autorelease pools, expecting us to not have put anything here.  In this case we were crashing in an @finally that did a -retain/-autorelease of the error, expecting that it was still valid, but it had been released by clearing a pool in an inner loop (which kept going since we return YES on success).
        return YES;
    }

    if (outError != NULL)
        *outError = error;
    return NO;
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: DELETE %@", url);
#ifdef OFSDAVForceReadOnly
    OFSError(outError, OFSCannotWriteFile, @"Read-only!", nil);
    return NO;
#endif
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"DELETE"];
    
    return ( [self _runRequestExpectingEmptyResultData:request error:outError] != nil )? YES : NO;
}

@end

@implementation OFSDAVFileManager (Private)

static NSString * const DAVNamespaceString = @"DAV:";

- (NSArray *)_propfind:(NSURL *)url depth:(NSString *)depth redirects:(NSMutableArray *)redirections error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: PROPFIND depth=%@ %@", depth, url);
    
    url = [url absoluteURL];
    //NSLog(@"url: %@", url);
    
    
    // Build the propfind request.  Can do this dynamically but for now we have a static request...
    NSData *requestXML;
    {
        OFXMLDocument *requestDocument = [[OFXMLDocument alloc] initWithRootElementName:@"propfind"
                                                                           namespaceURL:[NSURL URLWithString:DAVNamespaceString]
                                                                     whitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior]
                                                                         stringEncoding:kCFStringEncodingUTF8
                                                                                  error:outError];
        if (!requestDocument)
            return nil;
        
        //[[requestDocument topElement] setAttribute:@"xmlns" string:DAVNamespaceString];
        [requestDocument pushElement:@"prop"];
        {
            [requestDocument pushElement:@"resourcetype"];
            [requestDocument popElement];
            [requestDocument pushElement:@"getcontentlength"];
            [requestDocument popElement];
            [requestDocument pushElement:@"getlastmodified"];
            [requestDocument popElement];
        }
        [requestDocument popElement];
        
        requestXML = [requestDocument xmlData:outError];
        
        if (OFSFileManagerDebug > 2)
            NSLog(@"requestXML = %@", [NSString stringWithData:requestXML encoding:NSUTF8StringEncoding]);
        
        [requestDocument release];
        
        if (!requestXML)
            return nil;
        
        //NSData *requestXML = [@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<propfind xmlns=\"DAV:\"><prop>\n<resourcetype xmlns=\"DAV:\"/>\n</prop></propfind>" dataUsingEncoding:NSUTF8StringEncoding];
    }
    
    OFXMLDocument *doc;
    OFSDAVOperation *ranOperation = nil;
    {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
        OFSDAVAddUserAgentStringToRequest(self, request);
        [request setHTTPMethod:@"PROPFIND"];
        [request setHTTPBody:requestXML];
        [request setValue:depth forHTTPHeaderField:@"Depth"];

        // Specify that we are sending XML
        [request setValue:@"text/xml; charset=\"utf-8\"" forHTTPHeaderField:@"Content-Type"];

        // ... and that we want XML back
        [request setValue:@"text/xml,application/xml" forHTTPHeaderField:@"Accept"];

        doc = [self _documentBySendingRequest:request operation:&ranOperation error:outError];
        if (OFSFileManagerDebug > 1)
            NSLog(@"PROPFIND doc = %@", doc);
    }
    
    if (!doc) {
        OBASSERT(outError && *outError);
        return nil;
    }
    
    // If we followed redirects while doing the PROPFIND, it's important to interpret the result URLs relative to the URL of the request we actually got them from, instead of from some earlier request which may have been to a different scheme/host/whatever.
    NSURL *resultsBaseURL = url;
    {
        NSArray *redirs = [ranOperation redirects];
        if ([redirs count]) {
            [redirections addObjectsFromArray:redirs];  // Our caller may also be interested in redirects.
            resultsBaseURL = [[redirs lastObject] objectForKey:kOFSRedirectedTo];
        }
    }
    
    NSMutableArray *fileInfos = [NSMutableArray array];
    
    // We'll get back a <multistatus> with multiple <response> elements, each having <href> and <propstat>
    OFXMLCursor *cursor = [doc cursor];
    if (![[cursor name] isEqualToString:@"multistatus"]) {
        // TODO: Log error
        OBRequestConcreteImplementation(self, _cmd);
        return nil;
    }
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss 'GMT'"];   /* rfc 1123 */
    /* reference: http://developer.apple.com/library/ios/#qa/qa2010/qa1480.html */
    [dateFormatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    
    while ([cursor openNextChildElementNamed:@"response"]) {

        OBASSERT([[cursor name] isEqualToString:@"response"]);
        {
            if (![cursor openNextChildElementNamed:@"href"]) {
                OBRequestConcreteImplementation(self, _cmd);
                break;
            }
            
            NSString *encodedPath = OFCharacterDataFromElement([cursor currentElement]);
            [cursor closeElement]; // href
            //NSLog(@"encodedPath = %@", encodedPath);
            
            // There will one propstat element per status.  If there is a directory, for example, we'll get one for the resource type with status200 and one for the getcontentlength with status=404.
            // For files, there should be one propstat with both in the same <prop>.
            
            BOOL exists = NO;
            BOOL directory = NO;
            BOOL hasPropstat = NO;
            off_t size = 0;
            NSDate *dateModified = nil;
            
            while ([cursor openNextChildElementNamed:@"propstat"]) {
                hasPropstat = YES;
                
                OFXMLElement *anElement;
                while( (anElement = [cursor nextChild]) != nil ) {
                    NSString *childName = [anElement name];
                    if ([childName isEqualToString:@"prop"]) {
                        OFXMLElement *propElement;
                        if ([anElement firstChildAtPath:@"resourcetype/collection"])
                            directory = YES;
                        else if ( (propElement = [anElement firstChildNamed:@"getcontentlength"]) != nil ) {
                            NSString *sizeString = OFCharacterDataFromElement(propElement);
                            size = [sizeString unsignedLongLongValue];
                        } 
                        
                        if ( (propElement = [anElement firstChildNamed:@"getlastmodified"]) != nil ) {
                            NSString *lastModified = OFCharacterDataFromElement(propElement);
                            dateModified = [dateFormatter dateFromString:lastModified];
                        }
                    } else if ([childName isEqualToString:@"status"]) {
                        NSString *statusLine = OFCharacterDataFromElement(anElement);
                        // statusLine ~ "HTTP/1.1 200 OK we rule"
                        NSRange l = [statusLine rangeOfString:@" "];
                        if (l.length > 0 && [[statusLine substringWithRange:(NSRange){NSMaxRange(l), 1}] isEqualToString:@"2"])
                            exists = YES;
                        
                        // If we get a 404, or other error, that doesn't mean this resource doesn't exist: it just means this property doesn't exist on this resource.
                        // But every resource should have either a resourcetype or getcontentlength property, which will be returned to us with a 2xx status.
                    } else {
                        NSLog(@"Unexpected propstat element: %@", [anElement name]);
                    }
                }
                [cursor closeElement]; // propstat
            }
            
            if (!hasPropstat) {
                NSLog(@"No propstat element found for path '%@' of propfind of %@", encodedPath, url);
                continue;
            }
            
            // We used to remove the trailing slash here to normalize, but now we do that closer to where we need it.
            // If we make a request for this URL later, we should use the URL exactly as the server gave it to us, slash or not.
            
            NSURL *fullURL = [NSURL URLWithString:encodedPath relativeToURL:resultsBaseURL];
            
            OFSFileInfo *info = [[OFSFileInfo alloc] initWithOriginalURL:fullURL name:nil exists:exists directory:directory size:size lastModifiedDate:dateModified];
            [fileInfos addObject:info];
            [info release];
        }
        [cursor closeElement]; // response
    }
    
    [dateFormatter release];

    if (OFSFileManagerDebug > 1)
        NSLog(@"  Found files:\n%@", fileInfos);
    return fileInfos;
}

- (NSMutableArray *)_recursivelyCollectDirectoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections options:(OFSDirectoryEnumerationOptions)options error:(NSError **)outError;
{
    NSMutableArray *folderContents = [self directoryContentsAtURL:url collectingRedirects:redirections options:(options | OFSDirectoryEnumerationSkipsSubdirectoryDescendants) error:outError];
    
    NSMutableIndexSet *directoryReferences = [[NSMutableIndexSet alloc] init];
    NSUInteger counter = 0;
    
    NSMutableArray *children = [[NSMutableArray alloc] init];
    for (OFSFileInfo *nextFile in folderContents) {
        if ([nextFile isDirectory]) {
            [directoryReferences addIndex:counter];
            
            NSMutableArray *moreFiles = [self _recursivelyCollectDirectoryContentsAtURL:[nextFile originalURL] collectingRedirects:redirections options:(options | OFSDirectoryEnumerationSkipsSubdirectoryDescendants) error:outError];
            [children addObjectsFromArray:moreFiles];
        }
        
        counter++;
    }
    [folderContents removeObjectsAtIndexes:directoryReferences];
    [folderContents addObjectsFromArray:children];
    [children release];
    [directoryReferences release];
    
    return folderContents;
}

@end
