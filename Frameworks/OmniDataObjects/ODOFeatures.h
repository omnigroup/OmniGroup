// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


// The iPhone doesn't have NSUndoManager, or you know, cmd-z.
#ifdef TARGET_OS_IPHONE
    #define ODO_SUPPORT_UNDO 0
#else
    #define ODO_SUPPORT_UNDO 1
#endif
