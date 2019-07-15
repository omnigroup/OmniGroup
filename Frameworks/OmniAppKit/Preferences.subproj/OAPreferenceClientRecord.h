// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSArray, NSDictionary, NSNumber;
@class NSImage;
@class OAPreferenceClient, OAPreferenceController;

@interface OAPreferenceClientRecord : OFObject

- (instancetype)initWithCategoryName:(NSString *)newName;
    // Designated initializer.

@property (nonatomic, strong, readonly) NSImage *iconImage;
@property (nonatomic, strong, readonly) NSString *categoryName;
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *shortTitle;
@property (nonatomic, strong) NSString *iconName;
@property (nonatomic, strong) NSString *nibName;
@property (nonatomic, strong) NSString *helpURL;
@property (nonatomic, strong) NSNumber *ordering;
@property (nonatomic, strong) NSDictionary *defaultsDictionary;
@property (nonatomic, strong) NSArray *defaultsArray;

- (NSComparisonResult)compare:(OAPreferenceClientRecord *)other;
- (NSComparisonResult)compareOrdering:(OAPreferenceClientRecord *)other;

- (OAPreferenceClient *)newClientInstanceInController:(OAPreferenceController *)controller;


@end
