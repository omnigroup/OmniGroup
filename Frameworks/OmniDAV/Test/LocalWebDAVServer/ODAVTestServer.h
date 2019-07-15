// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@interface ODAVTestServer : NSObject

- (NSMutableDictionary *)substitutions;

@property (readonly, nonatomic) int processIdentifier;
@property (readonly, nonatomic) NSTask *process;
@property (readonly, nonatomic) NSURL *baseURL;

- (void)startWithConfiguration:(NSString *)configfile;
- (void)stop;

@end

