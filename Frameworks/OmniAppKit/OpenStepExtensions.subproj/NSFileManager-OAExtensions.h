// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSFileManager.h>

@interface NSFileManager (OAExtensions)

- (NSArray *)directoryContentsAtPath:(NSString *)path ofTypes:(NSArray *)someUTIs deep:(BOOL)recurse fullPath:(BOOL)fullPath error:(NSError **)errOut;
    // This method is dependent on NSWorkspace, which is an AppKit class

@end
