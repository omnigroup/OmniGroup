// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSDAVFileManager-Network.h"

RCS_ID("$Id$");

#import "OFSDAVOperation.h"

@implementation OFSDAVFileManager (Network)

- (NSData *)_rawDataByRunningRequest:(NSURLRequest *)message error:(NSError **)outError;
{
    NSTimeInterval start = 0;
    if (OFSFileManagerDebug > 0)
        start = [NSDate timeIntervalSinceReferenceDate];
    
    OFSDAVOperation *operation = [[[OFSDAVOperation alloc] initWithFileManager:self request:message target:nil] autorelease];
    if (!operation)
        return nil;
    
    NSData *result = [operation run:outError];
    
    if (OFSFileManagerDebug > 0) {
        static NSTimeInterval totalWait = 0;
        NSTimeInterval operationWait = [NSDate timeIntervalSinceReferenceDate] - start;
        totalWait += operationWait;
        NSLog(@"  ... network: %gs (total %g)", operationWait, totalWait);
    }
    
    return result;
}

- (BOOL)_runRequestExpectingEmptyResultData:(NSURLRequest *)message error:(NSError **)outError;
{
    NSData *responseData = [self _rawDataByRunningRequest:message error:outError];
    if (!responseData)
        return NO;
    
    if (OFSFileManagerDebug > 1 && [responseData length] > 0) {
        NSString *xmlString = [NSString stringWithData:responseData encoding:NSUTF8StringEncoding];
        NSLog(@"Unused response data: %@", xmlString);
        // still, we didn't get an error code, so let it pass
    }
    
    return YES;
}

- (OFXMLDocument *)_documentBySendingRequest:(NSURLRequest *)message error:(NSError **)outError;
{
    OFXMLDocument *doc = nil;
    OMNI_POOL_START {
        NSData *responseData = [self _rawDataByRunningRequest:message error:outError];
        if (!responseData) {
            OBASSERT(outError && *outError);
            return nil;
        }
        
        // It was found and we got data back.  Parse the response.
        if (OFSFileManagerDebug > 1)
            NSLog(@"xmlString: %@", [NSString stringWithData:responseData encoding:NSUTF8StringEncoding]);
        
        NSTimeInterval start = 0;
        if (OFSFileManagerDebug > 0)
            start = [NSDate timeIntervalSinceReferenceDate];

        doc = [[OFXMLDocument alloc] initWithData:responseData whitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior] error:outError];
        
        if (OFSFileManagerDebug > 0) {
            static NSTimeInterval totalWait = 0;
            NSTimeInterval operationWait = [NSDate timeIntervalSinceReferenceDate] - start;
            totalWait += operationWait;
            NSLog(@"  ... xml: %gs (total %g)", operationWait, totalWait);
        }
        
    } OMNI_POOL_ERROR_END;
    
    if (!doc)
        NSLog(@"Unable to decode XML from WebDAV response: %@", outError ? (id)[*outError toPropertyList] : (id)@"Unknown error");
    return [doc autorelease];
}

@end
