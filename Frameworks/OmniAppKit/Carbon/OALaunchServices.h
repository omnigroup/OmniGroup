// Copyright 2018-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSWorkspace.h>
#import <OmniBase/macros.h>

// Wrappers for LaunchServices API that are friendlier to Swift
NS_ASSUME_NONNULL_BEGIN

@interface NSWorkspace (OAExtensions)

// Passes either kLSRolesViewer or kLSRolesEditor for now. The first method has an analog in base NSWorkspace, but it doesn't let us specify we only want editors.
- (nullable NSArray<NSURL *> *)applicationURLsForURL:(NSURL *)fileURL editor:(BOOL)editor;
- (nullable NSURL *)defaultApplicationURLForURL:(NSURL *)fileURL editor:(BOOL)editor error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
