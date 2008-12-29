// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/branches/Staff/bungi/OmniFocus-20080310-iPhoneFactor/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSString-OFExtensions.h 98502 2008-03-11 04:44:44Z bungi $

#import <Foundation/NSString.h>

#define OF_CHARACTER_BUFFER_SIZE (1024u)

#define OFStringStartLoopThroughCharacters(string, ch)			\
{									\
    unichar characterBuffer[OF_CHARACTER_BUFFER_SIZE];			\
    unsigned int charactersProcessed, length;				\
									\
    charactersProcessed = 0;						\
    length = [string length];						\
    while (charactersProcessed < length) {				\
        unsigned int charactersInThisBuffer;				\
        unichar *input;							\
									\
        charactersInThisBuffer = MIN(length - charactersProcessed, OF_CHARACTER_BUFFER_SIZE); \
        [string getCharacters:characterBuffer range:NSMakeRange(charactersProcessed, charactersInThisBuffer)]; \
        charactersProcessed += charactersInThisBuffer;			\
        input = characterBuffer;					\
									\
        while (charactersInThisBuffer--) {				\
        unichar ch = *input++;

// your code here

#define OFStringEndLoopThroughCharacters	 			\
        }								\
    }									\
}
