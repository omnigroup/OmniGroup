// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAStrings.h>

@import Foundation;
@import OmniBase;
@import OmniFoundation;

RCS_ID("$Id$");

NSString *OAOK(void)
{
    static NSString *string;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        string = NSLocalizedStringFromTableInBundle(@"OK", @"OmniAppKit", OMNI_BUNDLE, @"button title");
    });
    return string;
}

NSString *OACancel(void)
{
    static NSString *string;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        string = NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", OMNI_BUNDLE, @"button title");
    });
    return string;
}
