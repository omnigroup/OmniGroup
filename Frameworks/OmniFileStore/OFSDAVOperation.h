// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniFileStore/OFSFileManagerAsynchronousReadTarget.h>

@class OFSDAVFileManager;

@interface OFSDAVOperation : OFObject
{
    OFSDAVFileManager *_nonretained_fileManager;
    
    NSURLRequest *_request;
    NSURLConnection *_connection;
    NSHTTPURLResponse *_response;
    NSMutableData *_resultData;
    BOOL _finished;
    NSError *_error;
    id <OFSFileManagerAsynchronousReadTarget, NSObject> _target;
}

- initWithFileManager:(OFSDAVFileManager *)fileManager request:(NSURLRequest *)request target:(id <OFSFileManagerAsynchronousReadTarget, NSObject>)target;
- (NSError *)prettyErrorForDAVError:(NSError *)davError;
- (NSData *)run:(NSError **)outError;
- (void)runAsynchronously;

@end

