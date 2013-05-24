// Copyright 2007, 2010, 2012-2013 Omni Development, Inc. All rights reserved.
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

+ (BOOL)shouldOfferToReportError:(NSError *)error;
{
    if (error == nil)
        return NO; // There isn't an error, so don't report one

    if ([error causedByUnreachableHost])
        return NO; // Unreachable hosts cannot be solved by the app

    if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOSPC]) {
        // Local filesystem is out of space.
        return NO;
    }

    if ([error hasUnderlyingErrorDomain:NSOSStatusErrorDomain code:errAuthorizationDenied]) {
        // User did not enter admin credentials
        return NO;
    }
    
    return YES; // Let's report everything else
}

- (BOOL)isApplicableToError:(NSError *)error;
{
    return [[self class] shouldOfferToReportError:error];
}

- (void)getFeedbackAddress:(NSString **)feedbackAddress andSubject:(NSString **)subjectLine;
{
    OBPRECONDITION(feedbackAddress != NULL);

    [super getFeedbackAddress:feedbackAddress andSubject:subjectLine];
    
    if (feedbackAddress) {
        *feedbackAddress = [*feedbackAddress stringByReplacingOccurrencesOfString:@"@" withString:@"+omnisoftwareupdate@"];
    }
}

@end
