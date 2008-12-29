// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OAFindControllerTargetProtocol.h 89466 2007-08-01 23:35:13Z kc $

#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>

@class NSView;
@class NSString;
@class OFRegularExpression;

@protocol OAFindPattern <NSObject>
- (BOOL)findInString:(NSString *)aString foundRange:(NSRangePointer)rangePtr;
- (BOOL)findInRange:(NSRange)range ofString:(NSString *)aString foundRange:(NSRangePointer)rangePtr;

- (void)setReplacementString:(NSString *)aString;
- (NSString *)replacementStringForLastFind;

// Allow the caller to inspect the contents of the find pattern (very helpful when they cannot efficiently reduce their target content to a string)
- (NSString *)findPattern;
- (BOOL)isCaseSensitive;
- (BOOL)isBackwards;
- (BOOL)isRegularExpression;
@end

@protocol OAFindControllerTarget
- (BOOL)findPattern:(id <OAFindPattern>)pattern backwards:(BOOL)backwards wrap:(BOOL)wrap;
@end

@interface NSObject (OAOptionalSelectedStringForFinding)
- (NSString *)selectedString;
@end

@interface NSObject (OAOptionalReplacement)
- (void)replaceSelectionWithString:(NSString *)aString;
- (void)replaceAllOfPattern:(id <OAFindPattern>)pattern;
@end

@interface NSObject (OAOptionalCurrentSelection)
- (void)replaceAllOfPatternInCurrentSelection:(id <OAFindPattern>)pattern;
@end

@interface NSObject (OAFindControllerAware)
- (id <OAFindControllerTarget>)omniFindControllerTarget;
@end

@protocol OASearchableContent
- (BOOL)findPattern:(id <OAFindPattern>)pattern backwards:(BOOL)backwards ignoreSelection:(BOOL)ignoreSelection;
@end

@interface NSObject (OAOptionalSearchableCellProtocol)
- (id <OASearchableContent>)searchableContentView;
@end

@interface NSObject (OAOptionalSelectionEditable)
- (BOOL)isSelectedTextEditable;
@end
