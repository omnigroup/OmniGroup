// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@interface OSUInstallerScript : NSObject

+ (BOOL)runWithArguments:(NSArray *)arguments localizationBundle:(NSBundle *)localizationBundle error:(NSError **)error;

@end

