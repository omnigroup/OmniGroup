// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDAVConnection.h>

#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/NSString-OFURLEncoding.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDAVOperation.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/NSURL-OFExtensions.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#endif
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIDevice.h>
#endif

#import <sys/sysctl.h>

RCS_ID("$Id$")

// TODO: This is kinda lame if we are just doing OFSDAVConnection
extern NSInteger OFSFileManagerDebug;

@implementation OFSDAVMultipleFileInfoResult
@end
@implementation OFSDAVSingleFileInfoResult
@end

@implementation OFSDAVConnection

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
    
    return CFBridgingRelease(CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, value, kCFStringEncodingUTF8, kCFAllocatorMalloc));
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
    OBINITIALIZE;
    
#if defined(OMNI_ASSERTIONS_ON) && (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE)
    if ([[NSProcessInfo processInfo] isSandboxed]) {
        // Sandboxed Mac applications cannot talk to the network by default. Give a better hint about why stuff is failing than the default (NSPOSIXErrorDomain+EPERM).
        
        NSDictionary *entitlements = [[NSProcessInfo processInfo] codeSigningEntitlements];
        OBASSERT([entitlements[@"com.apple.security.network.client"] boolValue]);
    }
#endif
    
    NSString *osVersionString = [[OFVersionNumber userVisibleOperatingSystemVersionNumber] originalVersionString];
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    
    NSString *appName = [bundleInfo objectForKey:(NSString *)kCFBundleNameKey];
    if ([NSString isEmptyString:appName])
        appName = [[NSProcessInfo processInfo] processName]; // command line tool?
    
    NSString *appInfo = appName;
    NSString *appVersionString = [bundleInfo objectForKey:(NSString *)kCFBundleVersionKey];
    if (![NSString isEmptyString:appVersionString])
        appInfo = [appInfo stringByAppendingFormat:@"/%@", appVersionString];
    
    NSString *hardwareModel = [NSString encodeURLString:OFSDAVHardwareModel() asQuery:NO leaveSlashes:YES leaveColons:YES];
    NSString *clientName = [NSString encodeURLString:ClientComputerName() asQuery:NO leaveSlashes:YES leaveColons:YES];
    
    StandardUserAgentString = [[NSString alloc] initWithFormat:@"%@ Darwin/%@ (%@) (%@)", appInfo, osVersionString, hardwareModel, clientName];
}

- (void)deleteURL:(NSURL *)url withETag:(NSString *)ETag completionHandler:(OFSDAVConnectionBasicCompletionHandler)completionHandler;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: DELETE %@", url);
    
    NSMutableURLRequest *request = [self _requestForURL:url];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"DELETE"];
    
    if (![NSString isEmptyString:ETag])
        [request setValue:ETag forHTTPHeaderField:@"If-Match"];
    
    completionHandler = [completionHandler copy];
    
    [self _runRequestExpectingEmptyResultData:request completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
        if (!resultURL) {
            if ([errorOrNil hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND]) {
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such file \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [url absoluteString]];
                __autoreleasing NSError *error = errorOrNil;
                OFSError(&error, OFSNoSuchFile, NSLocalizedStringFromTableInBundle(@"Unable to delete file.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), reason);
                errorOrNil = error;
            }
        }
        completionHandler(errorOrNil);
    }];
}

- (void)makeCollectionAtURL:(NSURL *)url completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: MKCOL %@", url);
    
    NSMutableURLRequest *request = [self _requestForURL:url];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"MKCOL"];
    
    completionHandler = [completionHandler copy];

    [self _runRequestExpectingEmptyResultData:request completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
        completionHandler(resultURL, errorOrNil);
    }];
}

static NSString * const DAVNamespaceString = @"DAV:";

static NSString *OFSDAVDepthName(OFSDAVDepth depth)
{
    NSString *depthString = nil;
    switch (depth) {
        case OFSDAVDepthLocal: /* local; returns file */
            depthString = @"0";
            break;
        case OFSDAVDepthChildren: /* children; returns direct descendants */
            depthString = @"1";
            break;
        case OFSDAVDepthInfinite: /* all; deep, recursive descendants */
            depthString = @"infinity";
            break;
        default:
            OBASSERT_NOT_REACHED("Bad depth specified");
            depthString = @"0";
            break;
    }
    return depthString;
}

- (void)fileInfosAtURL:(NSURL *)url ETag:(NSString *)predicateETag depth:(OFSDAVDepth)depth completionHandler:(OFSDAVConnectionMultipleFileInfoCompletionHandler)completionHandler;
{
    NSString *depthName = OFSDAVDepthName(depth);
    
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: PROPFIND ETag:%@ depth=%@ %@", predicateETag, depthName, url);
    
    url = [url absoluteURL];
    //NSLog(@"url: %@", url);
    
    
    // Build the propfind request.  Can do this dynamically but for now we have a static request...
    NSData *requestXML;
    {
        __autoreleasing NSError *error;
        OFXMLDocument *requestDocument = [[OFXMLDocument alloc] initWithRootElementName:@"propfind"
                                                                           namespaceURL:[NSURL URLWithString:DAVNamespaceString]
                                                                     whitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior]
                                                                         stringEncoding:kCFStringEncodingUTF8
                                                                                  error:&error];
        if (!requestDocument) {
            completionHandler(nil, error);
            return;
        }
        
        //[[requestDocument topElement] setAttribute:@"xmlns" string:DAVNamespaceString];
        [requestDocument pushElement:@"prop"];
        {
            [requestDocument pushElement:@"resourcetype"];
            [requestDocument popElement];
            [requestDocument pushElement:@"getcontentlength"];
            [requestDocument popElement];
            [requestDocument pushElement:@"getlastmodified"];
            [requestDocument popElement];
            [requestDocument pushElement:@"getetag"];
            [requestDocument popElement];
        }
        [requestDocument popElement];
        
        requestXML = [requestDocument xmlData:&error];
        
        if (OFSFileManagerDebug > 2)
            NSLog(@"requestXML = %@", [NSString stringWithData:requestXML encoding:NSUTF8StringEncoding]);
        
        
        if (!requestXML) {
            completionHandler(nil, error);
            return;
        }
        
        //NSData *requestXML = [@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<propfind xmlns=\"DAV:\"><prop>\n<resourcetype xmlns=\"DAV:\"/>\n</prop></propfind>" dataUsingEncoding:NSUTF8StringEncoding];
    }
    
    NSMutableURLRequest *request = [self _requestForURL:url];
    {
        OFSDAVAddUserAgentStringToRequest(self, request);
        [request setHTTPMethod:@"PROPFIND"];
        [request setHTTPBody:requestXML];
        [request setValue:depthName forHTTPHeaderField:@"Depth"];
        
        if (![NSString isEmptyString:predicateETag])
            [request setValue:predicateETag forHTTPHeaderField:@"If-Match"];
        
        // Specify that we are sending XML
        [request setValue:@"text/xml; charset=\"utf-8\"" forHTTPHeaderField:@"Content-Type"];
        
        // ... and that we want XML back
        [request setValue:@"text/xml,application/xml" forHTTPHeaderField:@"Accept"];
    }
    
    completionHandler = [completionHandler copy];
    
    [self _runRequestExpectingDocument:request completionHandler:^(OFXMLDocument *doc, OFSDAVOperation *op, NSError *errorOrNil){
        if (OFSFileManagerDebug > 1)
            NSLog(@"PROPFIND doc = %@", doc);
        if (!doc) {
            OBASSERT(errorOrNil);
            completionHandler(nil, errorOrNil);
            return;
        }
        
        OFSDAVMultipleFileInfoResult *result = [OFSDAVMultipleFileInfoResult new];
        
        // If we followed redirects while doing the PROPFIND, it's important to interpret the result URLs relative to the URL of the request we actually got them from, instead of from some earlier request which may have been to a different scheme/host/whatever.
        NSURL *resultsBaseURL = url;
        {
            NSArray *redirs = op.redirects;
            if ([redirs count]) {
                result.redirects = redirs;
                NSDictionary *lastRedirect = [redirs lastObject];
                resultsBaseURL = [lastRedirect objectForKey:kOFSRedirectedTo];
            }
        }
        
        NSMutableArray *fileInfos = [NSMutableArray array];
        
        // We'll get back a <multistatus> with multiple <response> elements, each having <href> and <propstat>
        OFXMLCursor *cursor = [doc cursor];
        if (![[cursor name] isEqualToString:@"multistatus"]) {
            __autoreleasing NSError *error;
            NSString *reason = [NSString stringWithFormat:@"Expected “multistatus” but found “%@” in PROPFIND result from %@.", cursor.name, [request shortDescription]];
            OFSError(&error, OFSDAVOperationInvalidMultiStatusResponse, @"Expected “multistatus” element missing in PROPFIND result.", reason);
            completionHandler(nil, error);
            return;
        }
        
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss 'GMT'"];   /* rfc 1123 */
        /* reference: http://developer.apple.com/library/ios/#qa/qa2010/qa1480.html */
        [dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        
        // Date header
        {
            // We could avoid parsing the Date header unless it is requested, but for now I'd like to get assertion failures when a server doesn't return it.
            NSString *dateHeader = [op valueForResponseHeader:@"Date"];
            OBASSERT(![NSString isEmptyString:dateHeader]);
            
            result.serverDate = [dateFormatter dateFromString:dateHeader];
            OBASSERT(result.serverDate);
        }
        
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
                NSString *ETag = nil;
                
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
                            
                            if ( (propElement = [anElement firstChildNamed:@"getetag"]) != nil ) {
                                ETag = OFCharacterDataFromElement(propElement);
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
                
                OFSFileInfo *info = [[OFSFileInfo alloc] initWithOriginalURL:fullURL name:nil exists:exists directory:directory size:size lastModifiedDate:dateModified ETag:ETag];
                [fileInfos addObject:info];
            }
            [cursor closeElement]; // response
        }
        
        
        if (OFSFileManagerDebug > 0) {
            NSLog(@"  Found %ld files", [fileInfos count]);
            for (OFSFileInfo *fileInfo in fileInfos)
                NSLog(@"    %@", fileInfo.originalURL);
        }
        result.fileInfos = fileInfos;
        
        completionHandler(result, nil);
    }];
}

- (void)fileInfoAtURL:(NSURL *)url ETag:(NSString *)predicateETag completionHandler:(void (^)(OFSDAVSingleFileInfoResult *result, NSError *error))completionHandler;
{
    completionHandler = [completionHandler copy];
    
    [self fileInfosAtURL:url ETag:predicateETag depth:OFSDAVDepthLocal completionHandler:^(OFSDAVMultipleFileInfoResult *result, NSError *errorOrNil) {
        if (!result) {
            if ([[errorOrNil domain] isEqualToString:OFSDAVHTTPErrorDomain]) {
                NSInteger code = [errorOrNil code];
                
                // A 406 Not Acceptable means that there is something possibly similar to what we asked for with a different content type than we specified in our Accepts header.
                // This is goofy since we didn't ASK for the resource contents, but its properties and our "text/xml" Accepts entry was for the format of the returned properties.
                // Apache does this on sync.omnigroup.com (at least with the current configuration as of this writing) if we do a PROPFIND for "Foo" and there is a "Foo.txt".
                if (code == OFS_HTTP_NOT_FOUND || code == OFS_HTTP_NOT_ACCEPTABLE) {
                    // The resource was legitimately not found.
                    OFSDAVSingleFileInfoResult *singleResult = [OFSDAVSingleFileInfoResult new];
                    singleResult.fileInfo = [[OFSFileInfo alloc] initWithOriginalURL:url name:nil exists:NO directory:NO size:0 lastModifiedDate:nil];
                    singleResult.redirects = result.redirects;
                    singleResult.serverDate = result.serverDate;
                    completionHandler(singleResult, nil);
                    return;
                }
            }
            
            // Some other error; pass it up
            completionHandler(nil, errorOrNil);
            return;
        }
        
        NSArray *fileInfos = result.fileInfos;
        if ([fileInfos count] == 0) {
            // This really doesn't make sense. But translate it to an error rather than raising an exception below.
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:[NSDictionary dictionaryWithObject:url forKey:OFSURLErrorFailingURLErrorKey]];
            completionHandler(nil, error);
            return;
        }
        
        OBASSERT([fileInfos count] == 1); // We asked for Depth=0, so we should only get one result.
        OFSFileInfo *fileInfo = [fileInfos objectAtIndex:0];
#ifdef OMNI_ASSERTIONS_ON
        {
            NSURL *foundURL = [fileInfo originalURL];
            if (!OFURLEqualsURL(url, foundURL)) {
                // The URLs will legitimately not be equal if we got a redirect -- don't spuriously warn in that case.
                if (OFNOTEQUAL([OFSFileInfo nameForURL:url], [OFSFileInfo nameForURL:foundURL])) {
                    OBASSERT_NOT_REACHED("Any issues with encoding normalization or whatnot?");
                    NSLog(@"url: %@", url);
                    NSLog(@"foundURL: %@", foundURL);
                }
            }
        }
#endif
        
        OFSDAVSingleFileInfoResult *singleResult = [OFSDAVSingleFileInfoResult new];
        singleResult.fileInfo = fileInfo;
        singleResult.redirects = result.redirects;
        singleResult.serverDate = result.serverDate;
        completionHandler(singleResult, nil);
    }];
}

- (void)getContentsOfURL:(NSURL *)url ETag:(NSString *)ETag completionHandler:(OFSDAVConnectionOperationCompletionHandler)completionHandler;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: GET %@", url);
    
    NSMutableURLRequest *request = [self _requestForURL:url];
    OFSDAVAddUserAgentStringToRequest(self, request);
    
    [request setHTTPMethod:@"GET"]; // really the default, but just for conformity with the others...
    
    if (![NSString isEmptyString:ETag])
        [request setValue:ETag forHTTPHeaderField:@"If-Match"];
    
    [self _runRequest:request completionHandler:completionHandler];
}

- (OFSDAVOperation *)asynchronousGetContentsOfURL:(NSURL *)url; // Returns an unstarted operation
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: GET %@", url);
    
    NSMutableURLRequest *request = [self _requestForURL:url];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"GET"]; // really the default, but just for conformity with the others...
    
    OFSDAVOperation *operation = [self _operationForRequest:request];
    
    // DO NOT launch the operation here. The caller should do this so it can assign it to an ivar or otherwise store it before it has to expect any callbacks.
    
    return operation;
}

// PUT is not atomic, so if you want an atomic replace, you should write to a temporary URL and the MOVE it into place.
- (void)putData:(NSData *)data toURL:(NSURL *)url completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    completionHandler = [completionHandler copy];
    
    NSMutableURLRequest *request = [self _requestForURL:url];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:data];
    
    [self _runRequestExpectingEmptyResultData:request completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
        completionHandler(resultURL, errorOrNil);
    }];
}

- (OFSDAVOperation *)asynchronousPutData:(NSData *)data toURL:(NSURL *)url;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: PUT %@ (data of %ld bytes)", url, [data length]);
    
    NSMutableURLRequest *request = [self _requestForURL:url];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:data];
    
    OFSDAVOperation *operation = [self _operationForRequest:request];
    
    // DO NOT launch the operation here. The caller should do this so it can assign it to an ivar or otherwise store it before it has to expect any callbacks.
    
    return operation;
}

typedef void (^OFSAddPredicate)(NSMutableURLRequest *request, NSURL *sourceURL, NSURL *destURL);

// COPY supports Depth=0 as well, but we haven't neede that yet.
- (void)_moveOrCopy:(NSString *)method sourceURL:(NSURL *)sourceURL toURL:(NSURL *)destURL overwrite:(BOOL)overwrite predicate:(OFSAddPredicate)predicate completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    completionHandler = [completionHandler copy];

    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: %@ %@ to %@, overwrite:%d", method, sourceURL, destURL, overwrite);
    
    NSMutableURLRequest *request = [self _requestForURL:sourceURL];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:method];
    
    // .Mac WebDAV accepts the just path the portion as the Destination, but normal OSXS doesn't.  It'll give a 400 Bad Request if we try that.  So, we send the full URL as the Destination.
    NSString *destination = [destURL absoluteString];
    [request setValue:destination forHTTPHeaderField:@"Destination"];
    [request setValue:overwrite ? @"T" : @"F" forHTTPHeaderField:@"Overwrite"];
    
    if (predicate)
        predicate(request, sourceURL, destURL);
    
    [self _runRequestExpectingEmptyResultData:request completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
        if (resultURL) {
            completionHandler(resultURL, nil);
            return;
        }
    
        // Work around for <bug://bugs/48303> (Some https servers incorrectly return Bad Gateway (502) for a MOVE to a destination with an https URL [bingodisk])
        if ([errorOrNil hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_BAD_GATEWAY] && [destination hasPrefix:@"https"]) {
            // Try again with an http destination instead
            NSString *updatedDestination = [@"http" stringByAppendingString:[destination stringByRemovingPrefix:@"https"]];
            [request setValue:updatedDestination forHTTPHeaderField:@"Destination"];
            
            if (predicate) {
                NSURL *updatedDestURL = [NSURL URLWithString:updatedDestination];
                predicate(request, sourceURL, updatedDestURL);
            }
            
            [self _runRequestExpectingEmptyResultData:request completionHandler:^(NSURL *workaroundResultURL, NSError *workaroundErrorOrNil){
                if (workaroundResultURL)
                    completionHandler(workaroundResultURL, nil);
                else
                    completionHandler(nil, workaroundErrorOrNil);
            }];
        } else {
            completionHandler(nil, errorOrNil);
        }
    }];
}

static void OFSAddIfPredicateForURLAndETag(NSMutableURLRequest *request, NSURL *url, NSString *ETag)
{
    if (![NSString isEmptyString:ETag]) {
        NSString *ifValue = [NSString stringWithFormat:@"<%@> ([%@])", [url absoluteString], ETag];
        [request setValue:ifValue forHTTPHeaderField:@"If"];
    }
}
static void OFSAddIfPredicateForURLAndLockToken(NSMutableURLRequest *request, NSURL *url, NSString *lockToken)
{
    if (![NSString isEmptyString:lockToken]) {
        NSString *ifValue = [NSString stringWithFormat:@"<%@> (%@)", [url absoluteString], lockToken];
        [request setValue:ifValue forHTTPHeaderField:@"If"];
    }
}

- (void)copyURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    // TODO: COPY can return OFS_HTTP_MULTI_STATUS if there is an error copying a sub-resource
    [self _moveOrCopy:@"COPY" sourceURL:sourceURL toURL:destURL overwrite:overwrite predicate:^(NSMutableURLRequest *request, NSURL *copySourceURL, NSURL *copyDestURL) {
        OFSAddIfPredicateForURLAndETag(request, copySourceURL, ETag);
    } completionHandler:completionHandler];
}

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    [self _moveOrCopy:@"MOVE" sourceURL:sourceURL toURL:destURL overwrite:YES predicate:nil completionHandler:completionHandler];
}

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    [self _moveOrCopy:@"MOVE" sourceURL:sourceURL toURL:destURL overwrite:overwrite predicate:^(NSMutableURLRequest *request, NSURL *moveSourceURL, NSURL *moveDestURL) {
        OFSAddIfPredicateForURLAndETag(request, moveSourceURL, ETag);
    } completionHandler:completionHandler];
}

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationETag:(NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    [self _moveOrCopy:@"MOVE" sourceURL:sourceURL toURL:destURL overwrite:overwrite predicate:^(NSMutableURLRequest *request, NSURL *moveSourceURL, NSURL *moveDestURL) {
        OFSAddIfPredicateForURLAndETag(request, moveDestURL, ETag);
    } completionHandler:completionHandler];
}

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceLock:(NSString *)lock overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    [self _moveOrCopy:@"MOVE" sourceURL:sourceURL toURL:destURL overwrite:overwrite predicate:^(NSMutableURLRequest *request, NSURL *moveSourceURL, NSURL *moveDestURL) {
        // The untagged list approach is supposed to use the source URI, but Apache 2.4.3 screws up and returns OFS_HTTP_PRECONDITION_FAILED in that case.
        // If we explicitly give the source URL, it works. It may be that Apache is checking based on the path? Anyway, it is no pain to be specific about which resource we think has the lock.
        OFSAddIfPredicateForURLAndLockToken(request, moveSourceURL, lock);
    } completionHandler:completionHandler];
}

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationLock:(NSString *)lock overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    [self _moveOrCopy:@"MOVE" sourceURL:sourceURL toURL:destURL overwrite:overwrite predicate:^(NSMutableURLRequest *request, NSURL *moveSourceURL, NSURL *moveDestURL) {
        OFSAddIfPredicateForURLAndLockToken(request, moveDestURL, lock);
    } completionHandler:completionHandler];
}

- (void)moveURL:(NSURL *)sourceURL toMissingURL:(NSURL *)destURL completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    // No predicate needed. The default for Overwrite: F is to return a precondition failure if the destination exists
    [self _moveOrCopy:@"MOVE" sourceURL:sourceURL toURL:destURL overwrite:NO predicate:nil completionHandler:completionHandler];
}

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL ifURLExists:(NSURL *)tagURL completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    [self _moveOrCopy:@"MOVE" sourceURL:sourceURL toURL:destURL overwrite:NO predicate:^(NSMutableURLRequest *request, NSURL *moveSourceURL, NSURL *moveDestURL) {
        // If-Match applies to teh URL in the command, but we want to be able to check an arbitrary header (not even the one in the Destination header). We can write this as a tagged condition list with the "If" header.
        NSString *ifValue = [NSString stringWithFormat:@"<%@> ([*])", [tagURL absoluteString]];
        [request setValue:ifValue forHTTPHeaderField:@"If"];
    } completionHandler:completionHandler];
}

- (void)lockURL:(NSURL *)url completionHandler:(OFSDAVConnectionStringCompletionHandler)completionHandler;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: LOCK %@", url);
    
    completionHandler = [completionHandler copy];
    
    NSData *requestXML;
    {
        __autoreleasing NSError *error;
        OFXMLDocument *requestDocument = [[OFXMLDocument alloc] initWithRootElementName:@"lockinfo"
                                                                           namespaceURL:[NSURL URLWithString:DAVNamespaceString]
                                                                     whitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior]
                                                                         stringEncoding:kCFStringEncodingUTF8
                                                                                  error:&error];
        if (!requestDocument) {
            completionHandler(nil, error);
            return;
        }
        
        __weak OFXMLDocument *doc = requestDocument; // Avoid capture warnings inside the blocks
        
        //[[requestDocument topElement] setAttribute:@"xmlns" string:DAVNamespaceString];
        [requestDocument addElement:@"locktype" childBlock:^{
            [doc appendElement:@"write"];
        }];
        [requestDocument addElement:@"lockscope" childBlock:^{
            [doc appendElement:@"exclusive"];
        }];
        [requestDocument addElement:@"owner" childBlock:^{
            OBFinishPortingLater("Add actual href for owner");
            [doc appendElement:@"href" containingString:@"http://example.com"];
        }];
        
        requestXML = [requestDocument xmlData:&error];
        
        if (OFSFileManagerDebug > 2)
            NSLog(@"requestXML = %@", [NSString stringWithData:requestXML encoding:NSUTF8StringEncoding]);
        if (!requestXML) {
            completionHandler(nil, error);
            return;
        }
    }
    
    NSMutableURLRequest *request;
    {
        request = [self _requestForURL:url];
        OFSDAVAddUserAgentStringToRequest(self, request);
        [request setHTTPMethod:@"LOCK"];
        [request setHTTPBody:requestXML];
        [request setValue:OFSDAVDepthName(OFSDAVDepthInfinite) forHTTPHeaderField:@"Depth"];
        
        // Specify that we are sending XML
        [request setValue:@"text/xml; charset=\"utf-8\"" forHTTPHeaderField:@"Content-Type"];
        
        // ... and that we want XML back
        [request setValue:@"text/xml,application/xml" forHTTPHeaderField:@"Accept"];
        
        // TODO: Add a Timeout header?
        // If we add refreshing of locks, the refresh request should have an empty body. Depth is ignored on refresh.
    }
    
    [self _runRequestExpectingDocument:request completionHandler:^(OFXMLDocument *doc, OFSDAVOperation *op, NSError *errorOrNil) {
        if (OFSFileManagerDebug > 1)
            NSLog(@"LOCK doc = %@", doc);
        
        if (!doc) {
            completionHandler(nil, errorOrNil);
            return;
        }
        
        // Lock-Token header is in result
        // "If the lock cannot be granted to all resources, the server must return a Multi-Status response with a 'response' element for at least one resource that prevented the lock from being granted, along with a suitable status code for that failure (e.g., 403 (Forbidden) or 423 (Locked)). Additionally, if the resource causing the failure was not the resource requested, then the server should include a 'response' element for the Request-URI as well, with a 'status' element containing 424 Failed Dependency."
        
        NSString *token = [op valueForResponseHeader:@"Lock-Token"];
        if (OFSFileManagerDebug > 1)
            NSLog(@"  --> token %@", token);
        
        // OBFinishPorting: Handle bad response from the server that doesn't contain a lock token.
        OBASSERT(![NSString isEmptyString:token]);
        
        completionHandler(token, errorOrNil);
    }];
}

- (void)unlockURL:(NSURL *)url token:(NSString *)lockToken completionHandler:(OFSDAVConnectionBasicCompletionHandler)completionHandler;
{
    completionHandler = [completionHandler copy];
    
    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: UNLOCK %@ token:%@", url, lockToken);
    
    NSMutableURLRequest *request = [self _requestForURL:url];
    OFSDAVAddUserAgentStringToRequest(self, request);
    [request setHTTPMethod:@"UNLOCK"];
    [request addValue:lockToken forHTTPHeaderField:@"Lock-Token"];
    
    [self _runRequestExpectingEmptyResultData:request completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
        if (!resultURL)
            completionHandler(errorOrNil);
        else
            completionHandler(nil);
    }];
}

#pragma mark - Private

static NSString *StandardUserAgentString;

static void OFSDAVAddUserAgentStringToRequest(OFSDAVConnection *manager, NSMutableURLRequest *request)
{
    [request setValue:StandardUserAgentString forHTTPHeaderField:@"User-Agent"];
}

- (NSMutableURLRequest *)_requestForURL:(NSURL *)url;
{
    static const NSURLRequestCachePolicy DefaultCachePolicy = NSURLRequestUseProtocolCachePolicy;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:DefaultCachePolicy timeoutInterval:[self _timeoutForURL:url]];
    if (_shouldDisableCellularAccess)
        [request setAllowsCellularAccess:NO];
    return request;
}

- (NSTimeInterval)_timeoutForURL:(NSURL *)url;
{
    static const NSTimeInterval DefaultTimeoutInterval = 300.0;
    
    return DefaultTimeoutInterval;
}

- (OFSDAVOperation *)_operationForRequest:(NSURLRequest *)request;
{
    OFSDAVOperation *operation = [[OFSDAVOperation alloc] initWithRequest:request];
    
    // Bridge operations that we have. This will (intentionally) retain us while the operation is running.
    if (_findCredentialsForChallenge) {
        operation.findCredentialsForChallenge = ^NSURLCredential *(OFSDAVOperation *op, NSURLAuthenticationChallenge *challenge){
            return _findCredentialsForChallenge(self, challenge);
        };
    }
    if (_validateCertificateForChallenge) {
        operation.validateCertificateForChallenge = ^(OFSDAVOperation *op, NSURLAuthenticationChallenge *challenge){
            _validateCertificateForChallenge(self, challenge);
        };
    }
    
    return operation;
}

- (void)_runRequest:(NSURLRequest *)request completionHandler:(void (^)(OFSDAVOperation *operation))completionHandler;
{
    NSTimeInterval start = 0;
    if (OFSFileManagerDebug > 1)
        start = [NSDate timeIntervalSinceReferenceDate];
    
    completionHandler = [completionHandler copy];
    OFSDAVOperation *operation = [self _operationForRequest:request];
    
    operation.didFinish = ^(OFSDAVOperation *op, NSError *error) {
        if (OFSFileManagerDebug > 1) {
            static NSTimeInterval totalWait = 0;
            NSTimeInterval operationWait = [NSDate timeIntervalSinceReferenceDate] - start;
            totalWait += operationWait;
            NSLog(@"  ... network: %gs (total %g)", operationWait, totalWait);
        }
        completionHandler(op);
    };

    [operation startOperationOnQueue:[NSOperationQueue currentQueue]];
}

- (void)_runRequestExpectingEmptyResultData:(NSURLRequest *)request completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
{
    completionHandler = [completionHandler copy];
    
    [self _runRequest:request completionHandler:^(OFSDAVOperation *operation) {
        if (operation.error) {
            completionHandler(nil, operation.error);
            return;
        }
        NSData *responseData = operation.resultData;
        
        if (OFSFileManagerDebug > 1 && [responseData length] > 0) {
            NSString *xmlString = [NSString stringWithData:responseData encoding:NSUTF8StringEncoding];
            NSLog(@"Unused response data: %@", xmlString);
            // still, we didn't get an error code, so let it pass
        }
        
        NSURL *resultLocation;
        
        // If the response specified a Location header, use that (this will be set to the the Destination for COPY/MOVE, possibly already redirected).
        NSString *resultLocationString = [operation valueForResponseHeader:@"Location"];
        if (![NSString isEmptyString:resultLocationString]) {
            resultLocation = [NSURL URLWithString:resultLocationString];
            
            // This fails so often on stock Apache that I'm turning it off.
            // Apache 2.4.3 doesn't properly URI encode the Location header <See https://issues.apache.org/bugzilla/show_bug.cgi?id=54611> (though our patched version does), but hopefully the location we *asked* to move it to will be valid. Note this won't help for PUT <https://issues.apache.org/bugzilla/show_bug.cgi?id=54367> since it doesn't have a destination header. But in this case we'll fall through and use the original URI.
            // OBASSERT(resultLocation, @"Location header couldn't be parsed as a URL, %@", resultLocationString);
            
            // If we couldn't parse the Location header, try the Destination header (for COPY/MOVE).
            if (!resultLocation) {
                NSString *destinationHeader = [request valueForHTTPHeaderField:@"Destination"];
                if (![NSString isEmptyString:destinationHeader]) {
                    resultLocation = [NSURL URLWithString:destinationHeader];
                }
            }
        }

        if ([[resultLocation host] isEqualToString:@"localhost"] && ![[[request URL] host] isEqualToString:@"localhost"]) {
            // Work around a bug in OS X Server's WebDAV hosting on 10.8.3 where the proxying server passes back Location headers which are unreachable from the outside world rather than rewriting them into its own namespace.  (It doesn't ever make sense to redirect a WebDAV request to localhost from somewhere other than localhost.)  Hopefully the Location headers in question are always predictable!  Fixes <bug:///87276> (Syncs after initial sync fail on 10.8.3 WebDAV server (error -1004, kCFURLErrorCannotConnectToHost)).
            resultLocation = nil;
        }

        if (!resultLocation) {
            // Otherwise use the original URL, looking up any redirection that happened on it.
            resultLocation = request.URL;
        
            NSArray *redirects = operation.redirects;
            if ([redirects count]) {
                NSDictionary *lastRedirect = [redirects lastObject];
                NSURL *lastLocation = [lastRedirect objectForKey:kOFSRedirectedTo];
                if (![lastLocation isEqual:resultLocation])
                    resultLocation = lastLocation;
            }
        }
        
        completionHandler(resultLocation, nil);
    }];
}

typedef void (^OFSDAVConnectionDocumentCompletionHandler)(OFXMLDocument *document, OFSDAVOperation *op, NSError *errorOrNil);

- (void)_runRequestExpectingDocument:(NSURLRequest *)request completionHandler:(OFSDAVConnectionDocumentCompletionHandler)completionHandler;
{
    completionHandler = [completionHandler copy];
    
    [self _runRequest:request completionHandler:^(OFSDAVOperation *operation) {
        NSData *responseData = operation.resultData;
        if (!responseData) {
            completionHandler(nil, operation, operation.error);
            return;
        }
        
        OFXMLDocument *doc = nil;
        NSError *documentError = nil;
        NSTimeInterval start = 0;
        @autoreleasepool {
            // It was found and we got data back.  Parse the response.
            if (OFSFileManagerDebug > 1)
                NSLog(@"xmlString: %@", [NSString stringWithData:responseData encoding:NSUTF8StringEncoding]);
            
            if (OFSFileManagerDebug > 1)
                start = [NSDate timeIntervalSinceReferenceDate];
            
            __autoreleasing NSError *error = nil;
            doc = [[OFXMLDocument alloc] initWithData:responseData whitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior] error:&error];
            if (!doc)
                documentError = error; // strongify this to live past the pool
        }
        
        if (OFSFileManagerDebug > 1) {
            static NSTimeInterval totalWait = 0;
            NSTimeInterval operationWait = [NSDate timeIntervalSinceReferenceDate] - start;
            totalWait += operationWait;
            NSLog(@"  ... xml: %gs (total %g)", operationWait, totalWait);
        }

        if (!doc) {
            NSLog(@"Unable to decode XML from WebDAV response: %@", [documentError toPropertyList]);
            completionHandler(nil, nil, documentError);
        } else
            completionHandler(doc, operation, nil);
    }];
}

@end
