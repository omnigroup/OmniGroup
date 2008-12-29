// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OASendFeedbackErrorRecovery.h"
#import "OAController.h"

#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@implementation OASendFeedbackErrorRecovery

#pragma mark -
#pragma mark OFErrorRecovery subclass

+ (NSString *)defaultLocalizedRecoveryOption;
{
    return NSLocalizedStringFromTableInBundle(@"Report Error via Email", @"OmniAppKit", OMNI_BUNDLE, @"error recovery description for button title");
}

- (BOOL)attemptRecoveryFromError:(NSError *)error;
{
    NSString *body = [self bodyForError:error];
    
    NSString *feedbackAddress, *subjectLine;
    [self getFeedbackAddress:&feedbackAddress andSubject:&subjectLine];

    OAController *controller = (OAController *)[OFController sharedController];
    [controller sendFeedbackEmailTo:feedbackAddress subject:subjectLine body:body];
    
    // We did _not_ actually recover from the error.  This will be returned from the various -presentError:... methods to indicate if recovery was done.  We didn't make anything better with our action.
    return NO;
}

#pragma mark -
#pragma mark API

- (void)getFeedbackAddress:(NSString **)feedbackAddress andSubject:(NSString **)subjectLine;
{
    OAController *controller = (OAController *)[OFController sharedController];
    [controller getFeedbackAddress:feedbackAddress andSubject:subjectLine];
}

- (NSString *)bodyForError:(NSError *)error;
{
    NSMutableString *body = [NSMutableString string];
    
    // These are going to be read by the developer, not necessarily the user, so don't localize them (or if we did, we'd want to localize to the main bundle's development language).
    [body appendFormat:@"Error: %@\n", [error localizedDescription]];
    [body appendFormat:@"Reason: %@\n", [error localizedFailureReason]];
    
    [body appendString:@"\nDetails:\n\n"];
    
    NSError *detailError = error;
    while (detailError) {
        NSDictionary *userInfo = [detailError userInfo];
        [body appendFormat:@"%@\n\n", [userInfo description]];
        detailError = [userInfo objectForKey:NSUnderlyingErrorKey];
    }
    
    return body;
}

@end
