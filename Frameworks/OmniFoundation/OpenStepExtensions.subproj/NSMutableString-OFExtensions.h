// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSMutableString-OFExtensions.h 98770 2008-03-17 22:25:33Z kc $

#import <Foundation/NSString.h>
#import <OmniBase/OBUtilities.h> // for OB_DEPRECATED_ATTRIBUTE

#import <OmniFoundation/NSString-OFReplacement.h> // Some simpler replacement methods are in a NSMutableString(OFReplacement) category here

@interface NSMutableString (OFExtensions)
- (void)collapseAllOccurrencesOfCharactersInSet:(NSCharacterSet *)set toString:(NSString *)replaceString;

- (BOOL)replaceAllOccurrencesOfString:(NSString *)matchString withString:(NSString *)newString;
- (BOOL)replaceAllOccurrencesOfRegularExpressionString:(NSString *)matchString withString:(NSString *)newString;
- (void)replaceAllLineEndingsWithString:(NSString *)newString;

- (void)appendCharacter:(unsigned int)aCharacter;
- (void)appendStrings: (NSString *)first, ...;

- (void)removeSurroundingWhitespace OB_DEPRECATED_ATTRIBUTE;

@end
