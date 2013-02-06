// Copyright 1997-2005, 2007-2008, 2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSUserDefaults-OFExtensions.h>

#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$")

NSString * const OFUserDefaultsRegistrationItemName = @"defaultsDictionary";

@implementation NSUserDefaults (OFExtensions)

// OFBundleRegistryTarget informal protocol

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
    if ([itemName isEqualToString:OFUserDefaultsRegistrationItemName]) {
        [[self standardUserDefaults] registerDefaults:description];
        [OFPreference recacheRegisteredKeys];
    }
}

@end
