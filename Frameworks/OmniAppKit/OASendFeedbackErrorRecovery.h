// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/OmniGroup/Frameworks/OmniAppKit/OAController.h 89915 2007-08-10 20:39:48Z bungi $

#import <OmniFoundation/OFErrorRecovery.h>

@interface OASendFeedbackErrorRecovery : OFErrorRecovery
- (void)getFeedbackAddress:(NSString **)feedbackAddress andSubject:(NSString **)subjectLine;
- (NSString *)bodyForError:(NSError *)error;
@end
