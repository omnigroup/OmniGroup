// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@class OSURunOperationParameters;
@protocol OSULookupCredential;

@protocol OSUCheckService

// The runtimeStats and probes are passed on their own since XPC's secure coding doesn't allow for complex data.
- (void)performCheck:(OSURunOperationParameters *)parameters runtimeStats:(NSDictionary *)runtimeStats probes:(NSDictionary *)probes lookupCredential:(id <OSULookupCredential>)lookupCredential withReply:(void (^)(NSDictionary *results, NSError *error))reply;

@end
