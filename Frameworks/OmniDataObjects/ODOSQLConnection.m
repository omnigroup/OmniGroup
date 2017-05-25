// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOSQLConnection.h>

#import <OmniDataObjects/Errors.h>
#import <OmniDataObjects/ODOSQLStatement.h>

#import <OmniFoundation/OFXMLIdentifier.h> // for OFXMLCreateID

RCS_ID("$Id$");

@interface ODOSQLConnection () {
    struct sqlite3 *_sqlite;
}

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy, readwrite) NSURL *URL;
@property (nonatomic, strong) NSOperationQueue *operationQueue;

@end

@implementation ODOSQLConnection

- (id)initWithURL:(NSURL *)fileURL options:(ODOSQLConnectionOptions)options error:(NSError **)outError;
{
    OBPRECONDITION([fileURL isFileURL]);
    
    if (!(self = [super init])) {
        return nil;
    }
    
    _identifier = OFXMLCreateID();
    _URL = [[fileURL absoluteURL] copy];
    
    // Set a custom serial underlying queue so that we can make assertions later about whether or not certain methods are executing on that queue
    NSString *queueName = [NSString stringWithFormat:@"com.omnigroup.framework.OmniDataObjects.ODOSQLConnection.%@", _identifier];
    dispatch_queue_t underlyingQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
    
    _operationQueue = [[NSOperationQueue alloc] init];
    _operationQueue.name = queueName;
    _operationQueue.maxConcurrentOperationCount = 1;
    _operationQueue.underlyingQueue = underlyingQueue;
    
    dispatch_release(underlyingQueue);
    
    if (![self _init_connectWithOptions:options error:outError]) {
        [self release];
        return nil;
    }
    
    return self;
}

- (void)dealloc;
{
    /* From the docs:
     ** All SQL statements prepared using sqlite3_prepare() or
     ** sqlite3_prepare16() must be deallocated using sqlite3_finalize() before
     ** this routine is called. Otherwise, SQLITE_BUSY is returned and the
     ** database connection remains open.
     */
    int rc = sqlite3_close(_sqlite);
    if (rc != SQLITE_OK) {
        NSString *reason = [NSString stringWithFormat:@"Unable to disconnect from database at '%@'.", [_URL absoluteString]];
        NSMutableDictionary *userInfo = [[@{ NSUnderlyingErrorKey : [NSError errorWithDomain:ODOSQLiteErrorDomain code:rc userInfo:nil] } mutableCopy] autorelease];
        
        if (rc == SQLITE_BUSY) {
            NSString *suggestion = [NSString stringWithFormat:@"Make sure that all outstanding ODOSQLStatements using %p as their connection have been invalidated.", self];
            [userInfo setObject:suggestion forKey:NSLocalizedRecoverySuggestionErrorKey];
        }
        
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:userInfo] raise];
    }
    
    _sqlite = NULL;
    
    [_operationQueue release];
    
    [_URL release];
    [_identifier release];
    
    [super dealloc];
}

#pragma mark API

- (void)performSQLBlock:(ODOSQLPerformBlock)block;
{
    [_operationQueue addOperationWithBlock:^{
        OBPRECONDITION(_sqlite != NULL);
        block(_sqlite);
    }];
}

- (BOOL)performSQLAndWaitWithError:(NSError **)outError block:(ODOSQLFailablePerformBlock)block;
{
    // It's dangerous to call into this method if already executing on the dispatch queue underlying our operation queue – since we wait on any operations we add, it's possible for reentrant calls here to deadlock.
    OBASSERT_DISPATCH_QUEUE_NOT([self.operationQueue underlyingQueue]);
    
    __block BOOL success = YES;
    __block NSError *localError = nil;
    
    block = [block copy];
    
    NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        OBPRECONDITION(_sqlite != NULL);
        NSError *blockError = nil;
        
        if (!block(_sqlite, &blockError)) {
            localError = [blockError retain]; // retain to get the error out of the block
            success = NO;
        }
    }];
    [self.operationQueue addOperation:operation];
    [operation waitUntilFinished];
    
    [block release];
    
    if (!success) {
        if (outError != NULL) {
            *outError = localError;
        }
        [localError autorelease]; // autorelease to balance the in-block retain; the net result is an autoreleased NSError in the caller's error variable
        return NO;
    }
    
    return YES;
}

- (BOOL)executeSQLWithoutResults:(NSString *)sql error:(NSError **)outError;
{
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initWithConnection:self sql:sql error:outError];
    if (!statement)
        return NO;
    
    BOOL success = [self performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        return ODOSQLStatementRunWithoutResults(sqlite, statement, blockError);
    }];
    
    OBExpectDeallocation(statement);
    [statement release];
    return success;
}

#pragma mark Private

- (BOOL)_init_connectWithOptions:(ODOSQLConnectionOptions)options error:(NSError **)outError;
{
    OBPRECONDITION(_URL != nil);
    NSString *path = [_URL path];
    
    // Even on error the output sqlite will supposedly be set and we need to close it.
    sqlite3 *sql = NULL;
    int rc = sqlite3_open([path UTF8String], &sql);
    if (rc != SQLITE_OK) {
        ODOSQLiteError(outError, rc, sql); // stack the underlying error
        sqlite3_close(sql);
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to open database.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot open database at '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), [_URL absoluteString]];
        ODOError(outError, ODOUnableToConnectDatabase, description, reason);
        return NO;
    }
    
    _sqlite = sql;
    
    if (options & ODOSQLConnectionAsynchronousWrites) {
        if (![self executeSQLWithoutResults:@"PRAGMA synchronous = off" error:outError])
            return NO;
    } else {
        if (![self executeSQLWithoutResults:@"PRAGMA synchronous = normal" error:outError])
            return NO;
    }
    
    if (options & ODOSQLConnectionKeepTemporaryStoreInMemory) {
        if (![self executeSQLWithoutResults:@"PRAGMA temp_store = memory" error:outError])
            return NO;
    }
    
    if (![self executeSQLWithoutResults:@"PRAGMA auto_vacuum = none" error:outError]) // According to the sqlite documentation: "Auto-vacuum does not defragment the database nor repack individual database pages the way that the VACUUM command does. In fact, because it moves pages around within the file, auto-vacuum can actually make fragmentation worse."
        return NO;
    
#if 0
    // "The maximum size of any string or BLOB or table row."
    int blobSize = sqlite3_limit(_sqlite, SQLITE_LIMIT_LENGTH, -1/* negative means to not change*/);
    NSLog(@"blobSize = %d", blobSize);
#endif
    
    return YES;
}

@end

#if defined(OMNI_ASSERTIONS_ON)
@implementation ODOSQLConnection (Assertions)

- (BOOL)checkExecutingOnDispatchQueue;
{
    OBASSERT_DISPATCH_QUEUE([self.operationQueue underlyingQueue]); // crashes on failure
    return YES;
}

- (BOOL)checkIsManagedSQLite:(struct sqlite3 *)sqlite;
{
    OBPRECONDITION(sqlite == _sqlite); // crashes on failure
    return YES;
}

@end
#endif
