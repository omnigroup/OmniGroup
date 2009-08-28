// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


// The iPhone doesn't have NSUndoManager, or you know, cmd-z.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    #define ODO_SUPPORT_UNDO 0
#else
    #define ODO_SUPPORT_UNDO 1
#endif


#if 0 && defined(DEBUG) && defined(ODO_SUPPORT_UNDO)
    #define DEBUG_UNDO(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_UNDO(format, ...)
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_DYNAMIC_METHODS(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_DYNAMIC_METHODS(format, ...)
#endif

// <rdar://6663569> Lazy method resolution and KVO can conflict such that resolution is invoked on the NSKVONotifying_* subclass and the method is added to the real class.  Method lookup then doesn't restart and the bogus cache entry is used, resulting in a bogus -doesNotRecognizeSelector:.
#if 0 && defined(DEBUG)
    #define LAZY_DYNAMIC_ACCESSORS 1
#else
    #define LAZY_DYNAMIC_ACCESSORS 0
#endif
