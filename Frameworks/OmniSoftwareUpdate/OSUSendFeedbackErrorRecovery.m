// Copyright 2007, 2010, 2012 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUSendFeedbackErrorRecovery.h"
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation OSUSendFeedbackErrorRecovery

- (void)getFeedbackAddress:(NSString **)feedbackAddress andSubject:(NSString **)subjectLine;
{
    OBPRECONDITION(feedbackAddress != NULL);

    [super getFeedbackAddress:feedbackAddress andSubject:subjectLine];
    
    if (feedbackAddress) {
        *feedbackAddress = [*feedbackAddress stringByReplacingAllOccurrencesOfString:@"@" withString:@"+omnisoftwareupdate@"];
    }
}

@end
