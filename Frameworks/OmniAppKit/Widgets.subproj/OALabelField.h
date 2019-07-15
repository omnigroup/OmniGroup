// Copyright 2012-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// A simple text field subclass that knows it is a label, and therefore changes its text color as appropriate when it is enabled/disabled.

#import <AppKit/NSTextField.h>

@interface OALabelField : NSTextField

- (void)setLabelAsToolTipIfTruncated;

@end
