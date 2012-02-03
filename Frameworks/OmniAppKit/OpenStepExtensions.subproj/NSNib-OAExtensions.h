// Copyright 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSNib.h>

@interface NSNib (OAExtensions)

// Instantiates a nib with an ownership policy for top level objects that is the same as UINibLoading.
// The return value is an array containing the top-level objects in the nib file. The array only contains those objects that were instantiated when the nib file was unarchived. You should retain either the returned array or the objects it contains (either manually, or via strong IBOutlets) to prevent the nib file objects from being released prematurely.
//
// 'options' is currently unused. Pass nil, or an empty dictionary.
- (NSArray *)instantiateNibWithOwner:(id)owner options:(NSDictionary *)optionsOrNil;

@end
