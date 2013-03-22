// Copyright 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UITextInput.h>

// Trivial UITextPosition / UITextRange implementations. We can do better than this?
@interface OUEFTextPosition : UITextPosition <NSCopying>

- initWithIndex:(NSUInteger)ix;
- (NSComparisonResult)compare:other;

@property(nonatomic,readonly) NSUInteger index;
@property(nonatomic) UITextStorageDirection affinity; // For text insertion positions; should the caret stick to the character before this index or at it.
@property(nonatomic) NSUInteger generation;

@end

