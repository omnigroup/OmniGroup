// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIChangePreferenceURLCommand.h>

/// A default command implementation for /change-group-preference?... URLs.
/// Use when changing preferences in the group-prefixed suite for the containing application's bundle identifier.
@interface OUIChangeGroupBundleIdentifierPreferenceURLCommand : OUIChangePreferenceURLCommand
@end
