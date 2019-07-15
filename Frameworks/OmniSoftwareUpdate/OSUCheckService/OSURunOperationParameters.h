// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@interface OSURunOperationParameters : NSObject <NSSecureCoding>
@property(nonatomic,copy) NSString *firstHopHost;
@property(nonatomic,copy) NSString *baseURLString;
@property(nonatomic,copy) NSString *appIdentifier;
@property(nonatomic,copy) NSString *appVersionString;
@property(nonatomic,copy) NSString *track;
@property(nonatomic) BOOL includeHardwareInfo;
@property(nonatomic) BOOL reportMode;
@property(nonatomic,copy) NSString *uuidString;
@property(nonatomic,copy) NSString *licenseType;
@property(nonatomic,copy) NSString *osuVersionString;
@end

