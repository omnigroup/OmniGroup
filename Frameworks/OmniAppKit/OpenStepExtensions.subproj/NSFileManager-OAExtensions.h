// Copyright 2002-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSFileManager.h>
#import <OmniBase/OBUtilities.h>

@class NSImage;

@interface NSFileManager (OAExtensions)
- (void)setIconImage:(NSImage *)newImage forPath:(NSString *)path OB_DEPRECATED_ATTRIBUTE;
- (void)setComment:(NSString *)aComment forPath:(NSString *)path;
    // This implementation is dependent on AppleScript, which we don't have in Foundation
- (void)updateForFileAtPath:(NSString *)path;
    // This implementation is dependent on AppleScript, which we don't have in Foundation

- (NSArray *)directoryContentsAtPath:(NSString *)path ofTypes:(NSArray *)someUTIs deep:(BOOL)recurse fullPath:(BOOL)fullPath error:(NSError **)errOut;
    // This method is dependent on NSWorkspace, which is an AppKit class

- (BOOL)deleteFileUsingFinder:(NSString *)path;

@end
