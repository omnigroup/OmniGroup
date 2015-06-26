// Copyright 2001-2008, 2010, 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OSURunOperationParameters;
@protocol OSULookupCredential;

#import "OSUReportKeys.h"

typedef void (^OSURunOperationCompletionHandler)(NSDictionary *result, NSError *error);
extern void OSURunOperation(OSURunOperationParameters *params, NSDictionary *runtimeStatsAndProbes, id <OSULookupCredential> lookupCredential, OSURunOperationCompletionHandler completionHandler);


// A local error domain for the check operation itself. In particular, there are no localized descriptions or suggestions here. The caller to OSURunOperation() should add these if it cares.
#define OSUCheckServiceErrorDomain @"com.omnigroup.OmniSoftwareUpdate.OSUCheckService"

enum {
    OSUCheckServiceNoError, // Zero means no error
    
    OSUCheckServiceServerError,
    OSUCheckServiceExceptionRaisedError,
};
