// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OWF/OWAbstractObjectStream.h>

@class NSArray;

@interface OWImmutableObjectStream : OWAbstractObjectStream

// API
- (instancetype)initWithObject:(NSObject *)anObject;
- (instancetype)initWithArray:(NSArray *)contents;   // D.I.

@end
