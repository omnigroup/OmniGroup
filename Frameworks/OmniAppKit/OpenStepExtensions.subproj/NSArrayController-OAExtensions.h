// Copyright 2018-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSArrayController.h>

@interface NSArrayController (OAExtensions)

- (void)moveObjectsAtArrangedObjectIndexes:(NSIndexSet *)rowIndexes toArrangedObjectIndex:(NSInteger)row;

@end
