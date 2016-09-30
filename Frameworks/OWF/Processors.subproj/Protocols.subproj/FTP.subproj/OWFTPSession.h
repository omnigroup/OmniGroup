// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSData, NSMutableArray;
@class ONSocket, ONSocketStream;
@class OWAddress, OWPipeline, OWProcessor;
@protocol OWProcessorContext;

enum OWFTP_ServerFeature { OWFTP_Yes, OWFTP_No, OWFTP_Maybe };

@interface OWFTPSession : OFObject

+ (void)readDefaults;
+ (OWFTPSession *)ftpSessionForAddress:(OWAddress *)anAddress;
+ (OWFTPSession *)ftpSessionForNetLocation:(NSString *)aNetLocation;

- initWithNetLocation:(NSString *)aNetLocation;

// Operations
- (void)fetchForProcessor:(OWProcessor *)aProcessor inContext:(id <OWProcessorContext>)aPipeline;
- (void)abortOperation;

@end
