// Copyright 2003-2005, 2007, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/branches/Staff/bungi/OmniFocus-20080107-Syncing/OmniGroup/Frameworks/OmniFoundation/XML/OFXMLDocument.h 92222 2007-10-03 00:00:44Z wiml $

#import <OmniFoundation/OFXMLDocument.h>

@interface OFXMLDocument (Parsing)
- (BOOL)_parseData:(NSData *)xmlData defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior error:(NSError **)outError;
@end
