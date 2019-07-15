// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

// Runs a modal alert asking the user if it is OK first.
extern BOOL OAHandleChangeConfigurationValueURL(NSURL *url, NSError **outError);

@interface OAChangeConfigurationValuesWindowController : NSWindowController
@end
