// Copyright 2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/OmniGroup/Templates/Developer%20Tools/File%20Templates/%20Omni/Omni%20sekrit%20source%20code%20class.pbfiletemplate/class.h 70671 2005-11-22 01:01:39Z kc $

#import <OmniSoftwareUpdate/OSUChecker.h>

@interface OSUTAChecker : OSUChecker
{
}

+ (NSString *)defaultBundleIdentifier;
+ (NSString *)defaultBundleBuildVersionString;
+ (NSString *)defaultBundleMarketingVersionString;
+ (NSString *)defaultUserVisibleSystemVersion;

@end
