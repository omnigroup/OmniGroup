// Copyright 2008, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUnzip/OUZipMember.h>

@interface OUZipDirectoryMember : OUZipMember

- initRootDirectoryWithChildren:(NSArray *)children;
- initWithName:(NSString *)name date:(NSDate *)date children:(NSArray *)children archive:(BOOL)shouldArchive;

- (BOOL)isRootDirectory;
- (NSArray *)children;
- (OUZipMember *)childNamed:(NSString *)childName;
- (void)addChild:(OUZipMember *)child;

- (BOOL)appendToZipArchive:(OUZipArchive *)zip error:(NSError **)outError;

@end

