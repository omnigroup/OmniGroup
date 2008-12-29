// Copyright 2006-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/AppleScript/OFScriptHelpers.h 89476 2007-08-01 23:59:32Z kc $

extern BOOL _OFCheckClass(id *object, Class cls, const char *name);
#define OFCheckClass(var, cls) \
do { \
    if (!_OFCheckClass(&var, [cls class], #var)) \
        return nil; \
} while(0)
#define OFCheckClassVoid(var, cls) \
do { \
    if (!_OFCheckClass(&var, [cls class], #var)) \
        return; \
} while(0)

extern BOOL _OFRequireNonNil(id object, const char *name);
#define OFRequireNonNil(var) \
do { \
    if (!_RequireNonNil(var, #var)) \
        return; \
} while(0)
