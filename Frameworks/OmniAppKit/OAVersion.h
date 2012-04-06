// Copyright 2003-2005, 2008-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#define OAAppKitVersionNumber10_2   (663.0)
#define OAAppKitVersionNumber10_2_3 (663.6)

#define OAAppKitVersionNumber10_3   (739.0)

#define OAAppKitVersionNumber10_4   (824.0)
#define OAAppKitVersionNumber10_4_1 (824.1)
#define OAAppKitVersionNumber10_4_2 (824.11)
#define OAAppKitVersionNumber10_4_9 (824.41)  // 824.41 on ppc, 824.42 on x86

#define OAAppKitVersionNumber10_5   (949)
#define OAAppKitVersionNumber10_5_2 (949.27)
#define OAAppKitVersionNumber10_5_3 (949.33)

#define OAAppKitVersionNumber10_6   (1038)

#define OAAppKitVersionNumber10_7   (1121)

#define OAAppKitVersionNumber10_8   (1162)  // DP2 is 1162.3

/* This defines a conditional, OALionAvailable, and a macro, OA_LION_ONLY( stmt; ), which handles executing code only on 10.7 and above and compiling it only for SDKs 10.7 and above. For longer pieces of code you should probably use #if, but for ORing in a single flag or calling a method, this is nicer. */

#if defined(MAC_OS_X_VERSION_10_7) && (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)
#  if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
#    define OALionAvailable  (NSAppKitVersionNumber >= OAAppKitVersionNumber10_7)
#  else
#    define OALionAvailable 1
#  endif
#  define OA_LION_ONLY(x)  do{ if(OALionAvailable) { x } }while(0)
#else
#  define OALionAvailable 0
#  define OA_LION_ONLY(x)  /* Not available */
#endif

/* A similar set of macros for 10.8 Mountain Lion */

#if defined(MAC_OS_X_VERSION_10_8) && (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_8)
#  if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_8
#    define OAMountainLionAvailable  (NSAppKitVersionNumber >= OAAppKitVersionNumber10_8)
#  else
#    define OAMountainLionAvailable 1
#  endif
#  define OA_MOUNTAINLION_ONLY(x)  do{ if(OAMountainLionAvailable) { x } }while(0)
#else
#  define OAMountainLionAvailable 0
#  define OA_MOUNTAINLION_ONLY(x)  /* Not available */
#endif

