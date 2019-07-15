// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSUndoManager.h>

extern NSString * const OFUndoManagerEnablednessDidChangeNotification;

enum {
    OFUndoManagerNoLogging = 0,
    OFUndoManagerLogToConsole = 1<<0,
    OFUndoManagerLogToBuffer = 1<<1,
    OFUndoManagerShortLogging = 1<<2,
};

@interface NSUndoManager (OFExtensions)

@property (nonatomic, readonly, getter=isUndoingOrRedoing) BOOL undoingOrRedoing;
    // Sometimes you just don't care which it is, just that whatever is currently happening is because of the NSUndoManager.

- (void)setActionNameIfGrouped:(NSString *)newActionName;

- (void)registerUndoWithValue:(id)oldValue forKey:(NSString *)aKey of:(NSObject *)kvcCompliantTarget;

// Debug logging
+ (unsigned int)loggingOptions;
+ (void)setLoggingOptions:(unsigned int)options;
- (NSString *)loggingBuffer;
- (void)clearLoggingBuffer;

@end

// Support for debugging undo operations by wrapping blocks of undo operations in the log.
extern void _OFUndoManagerPushCallSite(NSUndoManager *undoManager, id self, SEL _cmd);
extern void _OFUndoManagerPopCallSite(NSUndoManager *undoManager);

#define OFUndoManagerPushCallSite(undoManager) _OFUndoManagerPushCallSite(undoManager, self, _cmd)
#define OFUndoManagerPopCallSite(undoManager) _OFUndoManagerPopCallSite(undoManager)


@interface NSObject (OFUndoExtensions)
// Preserves the type-checking ability by casting the result of -prepareWithInvocationTarget: instead of casting it to id.
- (instancetype)prepareInvocationWithUndoManager:(NSUndoManager *)undoManager;
@end
