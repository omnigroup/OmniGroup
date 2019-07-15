// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class OFXServerAccount;

@protocol OFXServerAccountValidator <NSObject>

@property(nonatomic,readonly) OFXServerAccount *account;
@property(nonatomic,readonly) NSString *state;
@property(nonatomic,readonly) double percentDone;
@property(nonatomic,readonly) NSArray *errors;

@property(nonatomic,copy) void (^stateChanged)(id <OFXServerAccountValidator> validator);
@property(nonatomic,copy) void (^finished)(NSError *errorOrNil);

@property(nonatomic) BOOL shouldSkipConformanceTests; // This should only be used for unit tests (which bridge to the conformance tests directly).

- (void)startValidation;

@end
