// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OASlowLoadingImage.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OASlowLoadingImage (Private)
- (void)_start;
@end

@implementation OASlowLoadingImage

- initWithURL:(NSURL *)url;
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];    // allow default timeout interval to get set
    [request setCachePolicy:NSURLRequestReturnCacheDataElseLoad];
    return [self initWithURLRequest:request startImmediately:YES];
}

- initWithURLRequest:(NSURLRequest *)req startImmediately:(BOOL)startImmediately;  // D.I.
{
    [super init];
    
    source = [req copy];
    slowLoadingState = OASlowLoadNotStarted;
    if (startImmediately)
        [self _start];
    
    return self;
}

- (void)dealloc
{
    if (transfer) {
        [transfer cancel];
        [transfer autorelease];
        transfer = nil;
    }
    
    if (imageParser != NULL) {
        CFRelease(imageParser);
        imageParser = NULL;
    }
    if (mostRecentCGImage != NULL) {
        CFRelease(mostRecentCGImage);
        mostRecentCGImage = NULL;
    }
    if (typeHint != NULL) {
        CFRelease(typeHint);
        typeHint = NULL;
    }
    
    [dataBuffer release];
    [finalError release];
    [source release];
    
    [super dealloc];
}

// The following properties are KVO-observable. Calling them will not block.
- (CGImageRef)CGImage;        // The fully loaded image, or nil.
{
    if (slowLoadingState == OASlowLoadNotStarted)
        [self _start];
    
    if (slowLoadingState != OASlowLoadFinished)
        return NULL;
    
    return [self partialCGImage];
}

- (CGImageRef)partialCGImage;    // The partially loaded image, or fully loaded image, or nil.
{
    if (slowLoadingState == OASlowLoadNotStarted)
        [self _start];
    
    return mostRecentCGImage;
}

- (NSSize)imageSize;          // The size of the image, or NSZeroSize. May become valid before -image does.
{
    if (slowLoadingState == OASlowLoadNotStarted)
        [self _start];
    
    return mostRecentSize;
}

- (NSError *)loadingError;    // If the image fails to load, this will become non-nil.
{
    if (slowLoadingState == OASlowLoadNotStarted)
        [self _start];
    
    return finalError;
}

@end

@implementation OASlowLoadingImage (Private)

- (void)_start;
{
    if (slowLoadingState != OASlowLoadNotStarted)
        return;
    
    OBASSERT(transfer == nil);
    OBASSERT(imageParser == NULL);
    
    slowLoadingState = OASlowLoadStarted;
    transfer = [[NSURLConnection alloc] initWithRequest:source delegate:self];
}

- (void)_update:(BOOL)final error:(NSError *)err
{
    if (!final && imageParser) {
        CGImageSourceStatus stat = CGImageSourceGetStatus(imageParser);
        if (stat == kCGImageStatusReadingHeader || stat == kCGImageStatusIncomplete || stat == kCGImageStatusComplete) {
            // Fall through
        } else if (stat == kCGImageStatusInvalidData) {
            [transfer cancel];
            return;
        } else {
            return;
        }
    }
    
    if (final && imageParser) {
#if 1
        CGImageSourceUpdateData(imageParser, (CFDataRef)dataBuffer, TRUE);
#else
        CFRelease(imageParser);
        NSMutableDictionary *opts = [NSMutableDictionary dictionary];
        if (typeHint)
            [opts setObject:(id)typeHint forKey:(id)kCGImageSourceTypeIdentifierHint];
        imageParser = CGImageSourceCreateWithData((CFDataRef)dataBuffer, (CFDictionaryRef)opts);
#endif
    }
    
    NSSize newSize;
    CGImageRef newImageRef;
    enum OASlowLoadingImageState newState;
  
    newSize = (NSSize){ 0, 0 };
    newImageRef = NULL;
    newState = slowLoadingState;
    
    switch(CGImageSourceGetStatus(imageParser)) {
        case kCGImageStatusUnexpectedEOF:
        case kCGImageStatusInvalidData:
        case kCGImageStatusUnknownType:
        default:
            if (!err)
                err = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:[NSDictionary dictionaryWithObject:[source URL] forKey:NSURLErrorKey]];
            break;
        case kCGImageStatusReadingHeader:
        case kCGImageStatusIncomplete:
        case kCGImageStatusComplete:
        {
            CGImageSourceStatus partialStat = CGImageSourceGetStatusAtIndex(imageParser, 0);
            // For some reason, images in JPEGs have state==kCGImageStatusUnknownType even when they're fully loaded.
            if (partialStat == kCGImageStatusUnknownType || partialStat == kCGImageStatusIncomplete || partialStat == kCGImageStatusComplete) {
                CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(imageParser, 0, NULL);
                CFNumberRef width  = CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
                CFNumberRef height = CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
                CFNumberRef xdpi = CFDictionaryGetValue(props, kCGImagePropertyDPIWidth);
                CFNumberRef ydpi = CFDictionaryGetValue(props, kCGImagePropertyDPIHeight);
                
                float imageWidth, imageHeight;
                
                if (width && CFNumberGetValue(width, kCFNumberFloatType, &imageWidth) &&
                    height && CFNumberGetValue(height, kCFNumberFloatType, &imageHeight)) {
                    newSize.width = imageWidth;
                    newSize.height = imageHeight;
                    
                    if (xdpi && CFNumberGetValue(xdpi, kCFNumberFloatType, &imageWidth) &&
                        ydpi && CFNumberGetValue(ydpi, kCFNumberFloatType, &imageHeight)) {
                        newSize.width = newSize.width * imageWidth / 72.0;
                        newSize.height = newSize.height * imageHeight / 72.0;
                    }
                }
                CFRelease(props);
                
                newImageRef = CGImageSourceCreateImageAtIndex(imageParser, 0, NULL);
            }
            break;
        }
    }
    
    if (err && !finalError) {
        [self willChangeValueForKey:@"loadingError"];
        finalError = [err copy];
        [self didChangeValueForKey:@"loadingError"];
    }
    
    if (final)
        newState = OASlowLoadFinished;
    
    if (newState != slowLoadingState || !NSEqualSizes(newSize, mostRecentSize) || (newImageRef != mostRecentCGImage)) {
        if (newState == OASlowLoadFinished)
            [self willChangeValueForKey:@"CGImage"];
        [self willChangeValueForKey:@"partialCGImage"];
        [self willChangeValueForKey:@"imageSize"];
        
        if(mostRecentCGImage)
            CFRelease(mostRecentCGImage);
        mostRecentCGImage = newImageRef;
        newImageRef = NULL;
        
        mostRecentSize = newSize;
        
        slowLoadingState = newState;

        [self didChangeValueForKey:@"imageSize"];
        [self didChangeValueForKey:@"partialCGImage"];
        if (newState == OASlowLoadFinished)
            [self didChangeValueForKey:@"CGImage"];
    }
    
    if (newImageRef != NULL)
        CFRelease(newImageRef);
}

#pragma mark NSURLConnection delegate methods

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
{
    OBASSERT(transfer == connection);

    // Possible but unlikely, according to the docs, to receive multiple responses interspersed with data. Discard earlier responses.
    if (imageParser != NULL) {
        CFRelease(imageParser);
        imageParser = NULL;
    }
    
    if (dataBuffer)
        [dataBuffer release];
    if ([response expectedContentLength] > 0)
        dataBuffer = [[NSMutableData alloc] initWithCapacity:[response expectedContentLength]];
    else
        dataBuffer = [[NSMutableData alloc] init];
    
    if (typeHint) {
        CFRelease(typeHint);
        typeHint = NULL;
    }
    
    if ([response MIMEType])
        typeHint = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (CFStringRef)[response MIMEType], kUTTypeImage);
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    OBASSERT(transfer == connection);

    if (imageParser == NULL) {
        NSMutableDictionary *opts = [NSMutableDictionary dictionary];
        if (typeHint)
            [opts setObject:(id)typeHint forKey:(id)kCGImageSourceTypeIdentifierHint];
        imageParser = CGImageSourceCreateIncremental((CFDictionaryRef)opts);
    }
    
    if (data && [data length]) {
        [dataBuffer appendData:data];
        CGImageSourceUpdateData(imageParser, (CFDataRef)dataBuffer, FALSE);
        [self _update:NO error:nil];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
{
    [self _update:YES error:nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
{
    [self _update:YES error:error];
}

@end

