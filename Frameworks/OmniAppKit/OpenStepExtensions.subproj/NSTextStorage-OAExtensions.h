// Copyright 2002-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSTextStorage-OAExtensions.h 79079 2006-09-07 22:35:32Z kc $

#import <AppKit/NSTextStorage.h>

#import <OmniAppKit/OAFindPattern.h>

@class NSNumber, NSScriptCommand;

@interface NSTextStorage (OAExtensions)

- (NSUndoManager *)undoManager;

- (BOOL)isUnderlined;
- (void)setIsUnderlined:(BOOL)value;
- (NSNumber *)superscriptLevel;
- (void)setSuperscriptLevel:(NSNumber *)value;
- (NSNumber *)baselineOffset;
- (void)setBaselineOffset:(NSNumber *)value;
- (int)textAlignment;
- (void)setTextAlignment:(int)value;

- (void)convertFontsToHaveTrait:(NSFontTraitMask)trait;

// Regex stuff
+ (NSObject <OAFindPattern>*)findPatternForReplaceCommand:(NSScriptCommand *)command;
- (void)replaceUsingPattern:(NSObject <OAFindPattern>*)aPattern;

- (BOOL)findPattern:(id <OAFindPattern>)pattern inRange:(NSRange)searchRange foundRange:(NSRange *)foundRange;

- (id)attachmentAtCharacterIndex:(unsigned int)characterIndex;

@end
