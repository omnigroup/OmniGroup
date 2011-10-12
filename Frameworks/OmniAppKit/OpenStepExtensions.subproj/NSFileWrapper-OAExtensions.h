// Copyright 2006-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFFileWrapper.h>

#if (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE) && defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    #import <AppKit/NSFileWrapperExtensions.h>
#endif

@interface NSFileWrapper (OAExtensions)
+ (NSFileWrapper *)fileWrapperWithFilename:(NSString *)filename contents:(NSData *)data;
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSString *)fileType:(BOOL *)isHFSType;
#endif
- (void)addFileWrapperMovingAsidePreviousWrapper:(NSFileWrapper *)wrapper;
@end
