// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSScanner.h>

@interface NSScanner (OFExtensions)
- (BOOL)scanStringOfLength:(unsigned int)length intoString:(NSString **)result;
- (BOOL)scanStringWithEscape:(NSString *)escape terminator:(NSString *)quoteMark intoString:(NSString **)output;

// Scans one line of input at time in a * separated values string, with quote character '"'.  Correctly handles quoted newlines, separators, and escaped literatal quotations (two quotes in a row w/in a quoted string)
- (BOOL)scanLineComponentsSeparatedByString:(NSString *)separator intoArray:(NSArray **)returnComponents;
- (BOOL)scanUpToStringFromArray:(NSArray *)stringArray intoString:(NSString **)string;
@end
