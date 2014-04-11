// Copyright 2006, 2008, 2010, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSDateFormatter.h>

@class NSDateComponents;

@interface OFRelativeDateFormatter : NSDateFormatter

@property(nonatomic,copy) NSDateComponents *defaultTimeDateComponents;
@property(nonatomic,assign) BOOL useEndOfDuration;
@property(nonatomic,strong) NSDate *referenceDate;

- (void)setUseRelativeDayNames:(BOOL)useRelativeDayNames;
- (BOOL)useRelativeDayNames;
- (void)setWantsTruncatedTime:(BOOL)wantsTruncatedTime;
- (BOOL)wantsTruncatedTime;
@end

