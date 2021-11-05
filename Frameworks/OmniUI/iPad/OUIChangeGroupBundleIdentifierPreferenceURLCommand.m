// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIChangeGroupBundleIdentifierPreferenceURLCommand.h>

#import <OmniFoundation/OFPreference.h>

@implementation OUIChangeGroupBundleIdentifierPreferenceURLCommand

- (OFPreferenceWrapper *)preferenceWrapper;
{
    return [OFPreferenceWrapper groupContainerIdentifierForContainingApplicationBundleIdentifierPreferenceWrapper];
}

@end
