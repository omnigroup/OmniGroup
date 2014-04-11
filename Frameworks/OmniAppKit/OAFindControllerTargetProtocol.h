// Copyright 1997-2005, 2007, 2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>
#import <OmniAppKit/OAFindPattern.h>

@class NSString;

@protocol OAFindControllerTarget

- (BOOL)findPattern:(id <OAFindPattern>)pattern backwards:(BOOL)backwards wrap:(BOOL)wrap;

@optional

// selected string for finding
- (NSString *)selectedString;
- (BOOL)isSelectedTextEditable;

// replacement
- (void)replaceSelectionWithString:(NSString *)aString;
- (void)replaceAllOfPattern:(id <OAFindPattern>)pattern;

// replace in selection
- (void)replaceAllOfPatternInCurrentSelection:(id <OAFindPattern>)pattern;

@end

@interface NSObject (OAFindControllerAware)
- (id <OAFindControllerTarget>)omniFindControllerTarget;
@end
