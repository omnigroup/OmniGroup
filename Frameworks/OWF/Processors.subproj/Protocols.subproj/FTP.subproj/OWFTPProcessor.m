// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
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

RCS_ID("$Id$")

@implementation OWFTPProcessor

OBDidLoad(^{
    Class self = [OWFTPProcessor class];
    [self registerProcessorClass:self fromContentType:[OWURL contentTypeForScheme:@"ftp"] toContentType:[OWContentType wildcardContentType] cost:1.0f producingSource:YES];
});

+ (BOOL)processorUsesNetwork
{
    return YES;
}

- (void)process;
{
    ftpSession = [OWFTPSession ftpSessionForAddress:sourceAddress];
    [ftpSession fetchForProcessor:self inContext:self.pipeline];
    ftpSession = nil;
}

- (void)abortProcessing;
{
    [ftpSession abortOperation];
    ftpSession = nil;
    [super abortProcessing];
}

@end
