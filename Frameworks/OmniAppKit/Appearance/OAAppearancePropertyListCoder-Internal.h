// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

/// Exposed for unit testing purposes only.
@interface OAAppearancePropertyListClassKeypathExtractor: NSObject
- (NSMutableSet <NSString *> *)_keyPaths;
- (NSMutableSet <NSString *> *)_localDynamicPropertyNames;
- (NSMutableSet <NSString *> *)_localKeyPaths;
- (NSMutableSet <NSString *> *)_inheritedKeyPaths;
@end

@interface OAAppearancePropertyListCoder (PrivateTestable)
@property (nonatomic, readonly) OAAppearancePropertyListClassKeypathExtractor *keyExtractor;
+ (NSDictionary *)_pathComponentsTreeFromKeyPaths:(NSArray <NSString *> *)keyPaths;
@end

