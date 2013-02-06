// Copyright 1997-2005, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSBundle.h>

@interface NSBundle (OAExtensions)

+ (NSBundle *)OmniAppKit;

// This method has been deprecated because of its ambigous ownership policy for top level objects.
// This ambiguous policy has led to writing code which leaks the top-level objects.
// Additional, the current calling interface makes it cumbersome to do the right thing.
//
// Currently only deprecated in DEBUG builds (so we don't break builds for shipping products), but will be removed entirely in the near future.

#ifdef DEBUG_correia0
- (void)loadNibNamed:(NSString *)nibName owner:(id <NSObject>)owner __attribute__((deprecated));
#else
- (void)loadNibNamed:(NSString *)nibName owner:(id <NSObject>)owner;
#endif

// Convenience method for loading a nib with ownership policy for top level objects that is the same as UINibLoading.
//
// The return value is an array containing the top-level objects in the nib file. The array only contains those objects that were instantiated when the nib file was unarchived. You should retain either the returned array or the objects it contains (either manually, or via strong IBOutlets) to prevent the nib file objects from being released prematurely.
//
// The class method version follows the same bundle semantics as +[NSBundle loadNibNamed:owner:]: if the class of the owner has an associated bundle, it looks for the nib file in that bundle. Otherwise it looks in +[NSBundle mainBundle:].
//
// 'options' is currently unused. Pass nil, or an empty dictionary.
//
// See also -[NSNib(OAExtensions) instantiateNibWithOwner:options:].
+ (NSArray *)loadNibNamed:(NSString *)nibName owner:(id <NSObject>)owner options:(NSDictionary *)options;
- (NSArray *)loadNibNamed:(NSString *)nibName owner:(id)owner options:(NSDictionary *)options;

@end
