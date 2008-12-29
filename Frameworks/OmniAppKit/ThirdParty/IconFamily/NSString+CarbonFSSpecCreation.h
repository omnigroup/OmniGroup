// Copyright 2005 Omni Development, Inc.  All rights reserved.
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/ThirdParty/IconFamily/NSString+CarbonFSSpecCreation.h 66043 2005-07-25 21:17:05Z kc $
#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>

@interface NSString (CarbonFSSpecCreation)

// Fills in the given FSRef struct so it specifies the file whose path is in this string.
// If the file doesn't exist, and "createFile" is YES, this method will attempt to create
// an empty file with the specified path.  (The caller should insure that the directory
// the file is to be placed in already exists.)

- (BOOL) getFSRef:(FSRef*)fsRef createFileIfNecessary:(BOOL)createFile;

// Fills in the given FSSpec struct so it specifies the file whose path is in this string.
// If the file doesn't exist, and "createFile" is YES, this method will attempt to create
// an empty file with the specified path.  (The caller should insure that the directory
// the file is to be placed in already exists.)

- (BOOL) getFSSpec:(FSSpec*)fsSpec createFileIfNecessary:(BOOL)createFile;

@end
