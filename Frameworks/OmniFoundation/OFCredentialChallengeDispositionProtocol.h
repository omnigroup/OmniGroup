// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSURLSession.h>

@class NSOperation, NSURLCredential;

@protocol OFCredentialChallengeDisposition
/* Note that if the challenge operation is canceled, the disposition must still be set (e.g., to NSURLSessionAuthChallengeCancelAuthenticationChallenge) */
@property(readonly) NSURLSessionAuthChallengeDisposition disposition;
@property(readonly,retain,atomic) NSURLCredential *credential;
@end

// This returns an already-complete NSOperation containing the supplied disposition+credential. We should evaluate the places this is used and see if it would be better to return an asynchronous result.
// The returned operation is already finished; it should not be added to any queue.
extern NSOperation <OFCredentialChallengeDisposition> *OFImmediateCredentialResponse(NSURLSessionAuthChallengeDisposition, NSURLCredential *);

