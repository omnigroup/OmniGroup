// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>

#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, ODOSQLConnectionOptions) {
    ODOSQLConnectionAsynchronousWrites = 1 << 0,
    ODOSQLConnectionKeepTemporaryStoreInMemory = 1 << 1,
    ODOSQLConnectionReadOnly = 1 << 2,
};

typedef void (^ODOSQLPerformBlock)(struct sqlite3 *);
typedef BOOL (^ODOSQLFailablePerformBlock)(struct sqlite3 *, NSError **);

@interface ODOSQLConnection : NSObject

- (id)init NS_UNAVAILABLE;
- (nullable id)initWithURL:(NSURL *)fileURL options:(ODOSQLConnectionOptions)options error:(NSError **)outError NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NSURL *URL;

@property(nonatomic,readonly) dispatch_queue_t queue;

/// Closes the connection and blocks until it is actually closed.
- (void)close;

/// Invokes the given block on a background queue, passing a valid sqlite3 structure for the caller to use.
- (void)performSQLBlock:(ODOSQLPerformBlock)block;

/// Invokes the given block on a background queue, passing a valid sqlite3 structure and an out NSError pointer for the caller to use. Blocks the calling thread until the block has finished running on the background queue. Passes the return BOOL and NSError, if any, from the block to the caller.
- (BOOL)performSQLAndWaitWithError:(NSError **)outError block:(ODOSQLFailablePerformBlock)block;

/// Convenience for calling -performSQLAndWaitWithError:block:, invoking the given SQL string instead of taking a block. The SQL query should be a single statement, already quoted properly, that returns no result rows.
- (BOOL)executeSQLWithoutResults:(NSString *)sql error:(NSError **)outError;

/// Convenience for calling -performSQLAndWaitWithError:block:, invoking the given SQL string instead of taking a block. Results are ignored.
- (BOOL)executeSQLIgnoringResults:(NSString *)sql error:(NSError **)outError;

@end

#if defined(OMNI_ASSERTIONS_ON)
@interface ODOSQLConnection (Assertions)

- (BOOL)checkExecutingOnDispatchQueue;
- (BOOL)checkIsManagedSQLite:(struct sqlite3 *)sqlite;

@end
#endif

NS_ASSUME_NONNULL_END
