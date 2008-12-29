// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Processors.subproj/Protocols.subproj/FTP.subproj/OWFTPListingProcessor.h 68913 2005-10-03 19:36:19Z kc $

#import <OWF/OWDataStreamCharacterProcessor.h>

@class OWAddress, OWObjectStream;

@interface OWFTPListingProcessor : OWDataStreamCharacterProcessor
{
    OWObjectStream *objectStream;
    OWAddress *baseAddress;
    unsigned int lineNumber;
}

// convenience method used by subclasses for no particular reason
+ (void)registerForContentTypeString:(NSString *)sourceType cost:(int)cost;

// API implemented by subclasses
- (void)addFileForLine:(NSString *)line;
- (OWFileInfo *)fileInfoForLine:(NSString *)line;

@end

