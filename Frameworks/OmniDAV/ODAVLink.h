// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface ODAVLink : NSObject

+ (NSArray <ODAVLink *> *)linksWithHeaderValue:(NSString *)linkHeader;

@property(nonatomic,readonly) NSURL *URL;
@property(nonatomic,readonly) NSString *relation;
@property(nonatomic,readonly,nullable) NSDictionary <NSString *, NSString *> *parameters; // rel is not included

@end

NS_ASSUME_NONNULL_END
