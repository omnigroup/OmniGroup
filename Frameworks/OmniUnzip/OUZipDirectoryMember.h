// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipMember.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUZipDirectoryMember : OUZipMember

- (instancetype)initRootDirectoryWithChildren:(NSArray <OUZipMember *> * _Nullable)children;
- (instancetype)initWithName:(NSString *)name date:(NSDate * _Nullable)date children:(NSArray <OUZipMember *> * _Nullable)children archive:(BOOL)shouldArchive;

- (BOOL)isRootDirectory;
- (NSArray <OUZipMember *> *)children;
- (OUZipMember * _Nullable)childNamed:(NSString *)childName;
- (void)addChild:(OUZipMember *)child;
- (void)prependChild:(OUZipMember *)child;

- (BOOL)appendToZipArchive:(OUZipArchive *)zip error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
