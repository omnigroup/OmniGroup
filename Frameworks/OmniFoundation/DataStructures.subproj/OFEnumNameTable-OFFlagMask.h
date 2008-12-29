// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/branches/Staff/bungi/OmniFocus-20080310-iPhoneFactor/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFEnumNameTable.h 79079 2006-09-07 22:35:32Z kc $

#import <OmniFoundation/OFEnumNameTable.h>

@interface OFEnumNameTable (OFFlagMask)
- (NSString *)copyStringForMask:(unsigned int)mask withSeparator:(unichar)separator;
- (unsigned int)maskForString:(NSString *)string withSeparator:(unichar)separator;
@end
