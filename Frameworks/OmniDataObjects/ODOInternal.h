// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if 0 && defined(DEBUG)
    #define DEBUG_UNDO(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_UNDO(format, ...) do {} while (0)
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_DYNAMIC_METHODS(format, ...) NSLog(@"ODO METHODS: " format, ## __VA_ARGS__)
#else
    #define DEBUG_DYNAMIC_METHODS(format, ...) do {} while (0)
#endif

// <rdar://6663569> Lazy method resolution and KVO can conflict such that resolution is invoked on the NSKVONotifying_* subclass and the method is added to the real class.  Method lookup then doesn't restart and the bogus cache entry is used, resulting in a bogus -doesNotRecognizeSelector:.
#if 0 && defined(DEBUG)
    #define LAZY_DYNAMIC_ACCESSORS 1
#else
    #define LAZY_DYNAMIC_ACCESSORS 0
#endif
