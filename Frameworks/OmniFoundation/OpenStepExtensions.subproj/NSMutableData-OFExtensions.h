// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSMutableData-OFExtensions.h 98770 2008-03-17 22:25:33Z kc $

#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#import <stdio.h>

@interface NSMutableData (OFExtensions)

- (void) andWithData: (NSData *) aData;
/*.doc.
Sets each byte of the receiver to be the bitwise and of that byte and the corresponding byte in aData.

PRECONDITION(aData);
PRECONDITION([self length] == [aData length]);
*/

- (void) orWithData: (NSData *) aData;
/*.doc.
Sets each byte of the receiver to be the bitwise and of that byte and the corresponding byte in aData.

PRECONDITION(aData);
PRECONDITION([self length] == [aData length]);
*/


- (void) xorWithData: (NSData *) aData;
/*.doc.
Sets each byte of the receiver to be the bitwise and of that byte and the corresponding byte in aData.

PRECONDITION(aData);
PRECONDITION([self length] == [aData length]);
*/

- (void)appendString:(NSString *)aString encoding:(NSStringEncoding)anEncoding;

@end
