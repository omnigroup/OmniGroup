// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWCannedHTTPSourceProcessor.h"

#import <OmniBase/OmniBase.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Tests/OWFWebPounder/OWCannedHTTPSourceProcessor.m 68913 2005-10-03 19:36:19Z kc $")

#ifdef USE_CANNED_HTTP_SOURCE_PROCESSOR

@implementation OWCannedHTTPSourceProcessor

+ (void)didLoad;
{
    // Register ourselves at a lower cost than OWHTTPProcessor
    [self registerProcessorClass: self
                 fromContentType: [OWURL contentTypeForScheme:@"http"]
                   toContentType: [OWContentType sourceContentType]
                            cost: 1.0
                 producingSource: YES];
}

@end

#endif
