// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSDateFormatter.h>

@class NSDateComponents;

NS_ASSUME_NONNULL_BEGIN

@interface OFRelativeDateFormatter : NSDateFormatter

- init;

@property(nonatomic,copy) NSDateComponents *defaultTimeDateComponents;
@property(nonatomic,assign) BOOL useEndOfDuration;
@property(nonatomic,strong) NSDate *referenceDate;

@property(nonatomic) BOOL useRelativeDayNames;
@property(nonatomic) BOOL wantsLowercaseRelativeDayNames;
@property(nonatomic) BOOL wantsTruncatedTime;

@end

NS_ASSUME_NONNULL_END
