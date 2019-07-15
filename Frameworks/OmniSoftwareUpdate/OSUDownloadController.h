// Copyright 2007-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSWindowController.h>

@class OSUItem;

@interface OSUDownloadController : NSWindowController

+ (OSUDownloadController *)currentDownloadController;

// Do not instantiate the controller directly. Use +beginWithPackageURL:item:error:. This will return NO if a download is already in progress.
+ (BOOL)beginWithPackageURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;

@end
