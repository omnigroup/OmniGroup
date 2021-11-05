// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAbstractTableViewInspectorSlice.h>

@interface OUIOptionListInspectorSlice : OUIAbstractTableViewInspectorSlice

+ (instancetype)optionListSliceWithObjectClass:(Class)objectClass
                                       keyPath:(NSString *)keyPath
                titlesSubtitlesAndObjectValues:(NSString *)title, ... NS_REQUIRES_NIL_TERMINATION;

@property(nonatomic,copy) void (^optionChangedBlock)(NSString *valueKeyPath, NSNumber *value);
@property(nonatomic,assign) CGFloat topPadding; // 0 = default
@property(nonatomic,strong) NSString *groupTitle;
@property(nonatomic,assign) BOOL dismissesSelf;

@end
