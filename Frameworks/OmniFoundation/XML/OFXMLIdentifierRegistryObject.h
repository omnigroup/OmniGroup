// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/XML/OFXMLIdentifierRegistryObject.h 66043 2005-07-25 21:17:05Z kc $

@class OFXMLIdentifierRegistry;

@protocol OFXMLIdentifierRegistryObject
- (void)addedToIdentifierRegistry:(OFXMLIdentifierRegistry *)identifierRegistry withIdentifier:(NSString *)identifier;
- (void)removedFromIdentifierRegistry:(OFXMLIdentifierRegistry *)identifierRegistry;
@end

