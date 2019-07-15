// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>

typedef void (^OBLoadAction)(void);

typedef NS_ENUM(NSUInteger, OBLoadActionKind) {
    OBLoadActionKindPerformPosing,
    OBLoadActionKindDidLoad,
};

extern void _OBRegisterLoadAction(OBLoadActionKind kind, const char *file, unsigned line, OBLoadAction action);

#define _OBRegisterAction(counter, kind, file, line, action) \
static void _OBRegisterAction_ ## counter(void) __attribute__((constructor)); \
static void _OBRegisterAction_ ## counter(void) { \
    _OBRegisterLoadAction(kind, file, line, action); \
}

#define _OBRegisterAction_(counter, kind, file, line, action) _OBRegisterAction(counter, kind, file, line, action)

#define OBPerformPosing(action) _OBRegisterAction_(__COUNTER__, OBLoadActionKindPerformPosing, __FILE__, __LINE__, action)
#define OBDidLoad(action) _OBRegisterAction_(__COUNTER__, OBLoadActionKindDidLoad, __FILE__, __LINE__, action)

extern void OBInvokeRegisteredLoadActions(void);

@interface NSObject (OBPostLoaderDeprecated)
// These are no longer automatically called.
+ (void)becomingMultiThreaded OB_DEPRECATED_ATTRIBUTE;
+ (void)performPosing OB_DEPRECATED_ATTRIBUTE;
+ (void)didLoad OB_DEPRECATED_ATTRIBUTE;
@end

