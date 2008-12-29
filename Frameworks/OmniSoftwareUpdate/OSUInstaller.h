// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniSoftwareUpdate/OSUInstaller.h 95000 2007-11-23 22:58:40Z bungi $

#import <Foundation/NSObject.h>

#import <OmniFoundation/OFBinding.h>

@interface OSUInstaller : NSObject

+ (NSArray *)supportedPackageFormats;
+ (NSString *)preferredPackageFormat;

+ (BOOL)installAndRelaunchFromPackage:(NSString *)packagePath
               archiveExistingVersion:(BOOL)archiveExistingVersion
             deleteDiskImageOnSuccess:(BOOL)deleteDiskImageOnSuccess
                   statusBindingPoint:(OFBindingPoint)statusBindingPoint
                                error:(NSError **)outError;
@end
