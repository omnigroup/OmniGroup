// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWFTPProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWFTPSession.h>
#import <OWF/OWContentType.h>
#import <OWF/OWURL.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Processors.subproj/Protocols.subproj/FTP.subproj/OWFTPProcessor.m 68913 2005-10-03 19:36:19Z kc $")

@implementation OWFTPProcessor

+ (void)didLoad;
{
    [self registerProcessorClass:self fromContentType:[OWURL contentTypeForScheme:@"ftp"] toContentType:[OWContentType wildcardContentType] cost:1.0 producingSource:YES];
}

+ (BOOL)processorUsesNetwork
{
    return YES;
}

- (void)process;
{
    ftpSession = [OWFTPSession ftpSessionForAddress:sourceAddress];
    [ftpSession fetchForProcessor:self inContext:pipeline];
    ftpSession = nil;
}

- (void)abortProcessing;
{
    [ftpSession abortOperation];
    ftpSession = nil;
    [super abortProcessing];
}

@end
