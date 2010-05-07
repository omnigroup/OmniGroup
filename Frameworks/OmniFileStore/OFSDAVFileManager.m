// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
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
#import <OmniFoundation/OFXMLIdentifier.h>

#import <sys/sysctl.h>

RCS_ID("$Id$");

@interface OFSDAVFileManager (Private)
- (NSArray *)_collectorFileInfosAtURL:(NSURL *)url depth:(int)depth error:(NSError **)outError;
@end

static const NSURLRequestCachePolicy DefaultCachePolicy = NSURLRequestUseProtocolCachePolicy;
static const NSTimeInterval DefaultTimeoutInterval = 300.0;
static NSString *StandardUserAgentString;

NSString * const OFSMobileMeHost = @"idisk.me.com";

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
    
    NSString *hardwareModel = (NSString *)CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, value, kCFStringEncodingUTF8, kCFAllocatorMalloc);
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

+ (void)initialize;
{
    NSString *osVersionString = [[OFVersionNumber userVisibleOperatingSystemVersionNumber] originalVersionString];
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [bundleInfo objectForKey:(NSString *)kCFBundleNameKey];
    NSString *appVersionString = [bundleInfo objectForKey:(NSString *)kCFBundleVersionKey];
    NSString *hardwareModel = [NSString encodeURLString:OFSDAVHardwareModel() asQuery:NO leaveSlashes:YES leaveColons:YES];
    NSString *clientName = [NSString encodeURLString:ClientComputerName() asQuery:NO leaveSlashes:YES leaveColons:YES];
    
    StandardUserAgentString = [[NSString alloc] initWithFormat:@"%@/%@ Darwin/%@ (%@) (%@)", appName, appVersionString, osVersionString, hardwareModel, clientName];
}

- initWithBaseURL:(NSURL *)baseURL error:(NSError **)outError;
{    
    if (!(self = [super initWithBaseURL:baseURL error:outError]))
        return nil;
    
    if (![[[self baseURL] path] isAbsolutePath]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The path of the url \"%@\" is not absolute.", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [self baseURL]];
        OFSError(outError, OFSBaseURLIsNotAbsolute, NSLocalizedStringFromTableInBundle(@"Cannot create DAV-based file manager.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), reason);
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

static void XMLDAVAddUserAgentStringToRequest(OFSDAVFileManager *manager, NSMutableURLRequest *request)
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

#pragma mark OFSFileManager subclass

- (id)asynchronousReadContentsOfURL:(NSURL *)url forTarget:(id <OFSFileManagerAsynchronousReadTarget, NSObject>)target;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: GET %@", url);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    XMLDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"GET"]; // really the default, but just for conformity with the others...
    
    OFSDAVOperation *operation = [[[OFSDAVOperation alloc] initWithFileManager:self request:request target:target] autorelease];
    OBASSERT(operation != nil); // Otherwise we should call [target fileManager:self didFailWithError:nil];
    [operation runAsynchronously];
    return operation;
}

- (id)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically forTarget:(id <OFSFileManagerAsynchronousReadTarget, NSObject>)target;
{
    // We need to PUT to a temporary location and the MOVE for this to work.  Right now we don't need atomic support.
    OBPRECONDITION(atomically == NO);
    
    // TODO: What guarantees does WebDAV make about PUT command atomicity?  Do servers have bugs with this?  We could generate a crazy tmp file name and move it afterward, but we'd have to make assumptions about where we can put that file or what we can name it to make it 'invisible' while we are writing it.
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: PUT %@ (data of %ld bytes)", url, [data length]);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    XMLDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:data];
    
    OFSDAVOperation *operation = [[[OFSDAVOperation alloc] initWithFileManager:self request:request target:target] autorelease];
    OBASSERT(operation != nil); // Otherwise we should call [target fileManager:self didFailWithError:nil];
    [operation runAsynchronously];
    return operation;
}

#pragma mark OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;
{
    return YES;
}

// TODO: Ensure that the input urls are within the specified URL.  Either need to check this directly, or require that they are relative.

static NSURL *_noSlashURL(NSURL *url)
{
    // Normalize to not having a trailing '/'.
    url = [url absoluteURL];
    NSString  *urlString = [url absoluteString];
    if ([urlString hasSuffix:@"/"]) {
        urlString = [urlString stringByRemovingSuffix:@"/"];
        return [NSURL URLWithString:[urlString stringByRemovingSuffix:@"/"]];
    }
    return url;
}

- (OFSFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    url = _noSlashURL(url);
    
    NSError *localError = nil;
    NSArray *fileInfos = [self _collectorFileInfosAtURL:url depth:0 error:&localError];

    if ([fileInfos count] == 0) {
        if ([[localError domain] isEqualToString:OFSDAVHTTPErrorDomain] && [localError code] == 404) {
            // The resource was legitimately not found.
            return [[[OFSFileInfo alloc] initWithOriginalURL:url name:[OFSFileInfo nameForURL:url] exists:NO directory:NO size:0] autorelease];
        }
        
        // Some other error; pass it up
        if (outError)
            *outError = localError;
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

- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    url = _noSlashURL(url);
    
    NSArray *fileInfos = [self _collectorFileInfosAtURL:url depth:1 error:outError];
    if (!fileInfos) {
        OBASSERT(outError && *outError);
        return nil;
    }
    
    NSMutableArray *contents = [NSMutableArray array];
    
    for (OFSFileInfo *info in fileInfos) {
        if (![info exists]) {
            OBASSERT_NOT_REACHED("Why would we list something that doesn't exist?"); // Maybe if a <prop> element comes back 404 or with some other error?  We aren't event looking at the per entry status yet.
            continue;
        }
        
        // The directory itself will be in the property results.
        NSURL *infoURL = [info originalURL];
        if ([infoURL isEqual:url])
            continue;

        NSString *path = [infoURL path];

        if ([[path lastPathComponent] hasPrefix:@"._"]) {
            // Ignore split resource fork files; these presumably happen when moving between filesystems.
            continue;
        }

        // Verify the extension after decoding, in case the extension has something quote-worth.
        if (extension && [[path pathExtension] caseInsensitiveCompare:extension] != NSOrderedSame)
            continue;
        
        [contents addObject:info];
    }
    
    return contents;
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: GET %@", url);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    XMLDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"GET"]; // really the default, but just for conformity with the others...
    return [self _rawDataByRunningRequest:request error:outError];
}

- (BOOL)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: PUT %@ (data of %ld bytes) atomically:%d", url, [data length], atomically);

    // PUT is not atomic.  By itself it will just stream the file right into place; if the transfer is iterrupted, it'll just leave a partial turd there.
    if (atomically) {
        // Do a non-atomic PUT to a temporary location.  The name needs to be something that won't get picked up by XMLTransactionGraph or XMLSynchronizer (which use file extensions).  We don't have a temporary directory on the DAV server.
        NSString *temporaryURLString = [[url absoluteString] stringByRemovingSuffix:@"/"];
        temporaryURLString = [temporaryURLString stringByAppendingFormat:@"-write-in-progress-%@", [OFXMLCreateID() autorelease]];
        
        NSURL *temporaryURL = [NSURL URLWithString:temporaryURLString];
        
        if (![self writeData:data toURL:temporaryURL atomically:NO error:outError])
            return NO;
        
        // MOVE the fully written data into place.
        return [self moveURL:temporaryURL toURL:url error:outError];
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    XMLDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:data];
    return [self _runRequestExpectingEmptyResultData:request error:outError];
}

- (BOOL)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: MKCOL %@", url);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    XMLDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"MKCOL"];
    return [self _runRequestExpectingEmptyResultData:request error:outError];
}

- (BOOL)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: MOVE %@ to %@", sourceURL, destURL);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:sourceURL cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    XMLDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"MOVE"];
    
    // .Mac WebDAV accepts the just path the portion as the Destination, but normal OSXS doesn't.  It'll give a 400 Bad Request if we try that.  So, we send the full URL as the Destination.
    NSString *destination = [destURL absoluteString];
    [request setValue:destination forHTTPHeaderField:@"Destination"];
    [request setValue:@"T" forHTTPHeaderField:@"Overwrite"];

    if (outError)
        *outError = nil;
    if ([self _runRequestExpectingEmptyResultData:request error:outError])
        return YES;

    // Work around for <bug://bugs/48303> (Some https servers incorrectly return Bad Gateway (502) for a MOVE to a destination with an https URL [bingodisk])
    if (outError && [[*outError domain] isEqualToString:OFSDAVHTTPErrorDomain] && [*outError code] == 502 && [destination hasPrefix:@"https"]) {        
        // Try again with an http destination instead
        destination = [@"http" stringByAppendingString:[destination stringByRemovingPrefix:@"https"]];
        [request setValue:destination forHTTPHeaderField:@"Destination"];
        if (![self _runRequestExpectingEmptyResultData:request error:outError])
            return NO;
        *outError = nil; // clear our error since if we return YES with a non-nil error, the calling code can do things like release autorelease pools, expecting us to not have put anything here.  In this case we were crashing in an @finally that did a -retain/-autorelease of the error, expecting that it was still valid, but it had been released by clearing a pool in an inner loop (which kept going since we return YES on success).
        return YES;
    }

    return NO;
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: DELETE %@", url);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
    XMLDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"DELETE"];
    
    return [self _runRequestExpectingEmptyResultData:request error:outError];
}

@end

@implementation OFSDAVFileManager (Private)

static NSString * const DAVNamespaceString = @"DAV:";

- (NSArray *)_collectorFileInfosAtURL:(NSURL *)url depth:(int)depth error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: PROPFIND depth=%d %@", depth, url);
    
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
        }
        [requestDocument popElement];
        
        requestXML = [requestDocument xmlData:outError];
        //NSLog(@"requestXML = %@", [NSString stringWithData:requestXML encoding:NSUTF8StringEncoding]);
        [requestDocument release];
        
        if (!requestXML)
            return nil;
        
        //NSData *requestXML = [@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<propfind xmlns=\"DAV:\"><prop>\n<resourcetype xmlns=\"DAV:\"/>\n</prop></propfind>" dataUsingEncoding:NSUTF8StringEncoding];
    }
    
    OFXMLDocument *doc;
    {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:DefaultTimeoutInterval];
        XMLDAVAddUserAgentStringToRequest(self, request);
        [request setHTTPMethod:@"PROPFIND"];
        [request setHTTPBody:requestXML];
        [request setValue:[NSString stringWithFormat:@"%d", depth] forHTTPHeaderField:@"Depth"];

        // Specify that we are sending XML
        [request setValue:@"text/xml; charset=\"utf-8\"" forHTTPHeaderField:@"Content-Type"];

        // ... and that we want XML back
        [request setValue:@"text/xml,application/xml" forHTTPHeaderField:@"Accept"];

        doc = [self _documentBySendingRequest:request error:outError];
        if (OFSFileManagerDebug > 1)
            NSLog(@"PROPFIND doc = %@", doc);
    }
    
    if (!doc) {
        OBASSERT(outError && *outError);
        return nil;
    }
    
    NSMutableArray *fileInfos = [NSMutableArray array];
    
    // We'll get back a <multistatus> with multiple <response> elements, each haveing <href> and <propstat>
    OFXMLCursor *cursor = [doc cursor];
    if (![[cursor name] isEqualToString:@"multistatus"]) {
        // TODO: Log error
        OBRequestConcreteImplementation(self, _cmd);
        return nil;
    }
    
    while (YES) {
        if (![cursor openNextChildElementNamed:@"response"])
            break;

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
            
            if (![cursor openNextChildElementNamed:@"propstat"]) {
                NSLog(@"No propstat element found for path '%@' of propfind of %@", encodedPath, url);
                break;
            } else {
                BOOL exists = YES; // Look at the 'status' subelement?
                BOOL directory = NO;
                off_t size = 0;
                
                if ([[cursor currentElement] firstChildAtPath:@"prop/resourcetype/collection"])
                    directory = YES;
                else {
                    OFXMLElement *sizeElement = [[cursor currentElement] firstChildAtPath:@"prop/getcontentlength"];
                    if (sizeElement) {
                        NSString *sizeString = OFCharacterDataFromElement(sizeElement);
                        size = [sizeString unsignedLongLongValue];
                    }
                }

#ifdef DEBUG_kc0
                NSLog(@"encodedPath = '%@'", encodedPath);
#endif
                // Normalize to not having a trailing '/'.
                if ([encodedPath hasSuffix:@"/"])
                    encodedPath = [encodedPath stringByRemovingSuffix:@"/"];

                NSURL *fullURL = [NSURL URLWithString:encodedPath relativeToURL:url];
                
                OFSFileInfo *info = [[OFSFileInfo alloc] initWithOriginalURL:[fullURL absoluteURL] name:[OFSFileInfo nameForURL:fullURL] exists:exists directory:directory size:size];
                [fileInfos addObject:info];
                [info release];
                [cursor closeElement]; // propstat
            }
        }
        [cursor closeElement]; // response
    }

    if (OFSFileManagerDebug > 1)
        NSLog(@"  Found files:\n%@", fileInfos);
    return fileInfos;
}

@end
