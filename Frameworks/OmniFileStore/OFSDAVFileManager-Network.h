// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDAVFileManager.h>

@class OFSDAVOperation;
@class OFXMLDocument;

@interface OFSDAVFileManager (Network)
- (NSData *)_rawDataByRunningRequest:(NSURLRequest *)message operation:(OFSDAVOperation **)op error:(NSError **)outError;
- (NSURL *)_runRequestExpectingEmptyResultData:(NSURLRequest *)message error:(NSError **)outError;
- (OFXMLDocument *)_documentBySendingRequest:(NSURLRequest *)message operation:(OFSDAVOperation **)op error:(NSError **)outError;
@end
