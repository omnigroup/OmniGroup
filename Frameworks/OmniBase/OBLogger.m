// Copyright 2013-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBLogger.h>

#import <Foundation/Foundation.h>

#import <OmniBase/assertions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>

RCS_ID("$Id$");

// Right now log files go into ~/Documents, which is OK to clean up on iOS, but seems bad on the Mac since the user could intentionally be storing stuff there.
#if TARGET_OS_IOS
    #define REMOVE_OLD_LOG_FILES 1
#else
    #define REMOVE_OLD_LOG_FILES 0
#endif

void OBLog(OBLogger *logger, NSInteger messageLevel, NSString *format, ...)
{
    if (logger == nil || messageLevel < logger.level)
        return;
    
    va_list args;
    va_start(args, format);
    [logger log:format arguments:args];
    va_end(args);
}

// should only be called from OBLogger.swift
void OBLogSwiftVariadicCover(OBLogger *logger, NSInteger messageLevel, NSString *message) {
    OBLog(logger, messageLevel, @"%@", message);
}

void _OBLoggerInitializeLogLevel(OBLogger * __strong *outLogger, NSString *name, BOOL useFile)
{
    OBLogger *logger = [[OBLogger alloc] initWithName:name shouldLogToFile:useFile];
    if (logger != nil)
        *outLogger = logger;
}

static NSURL *_LogFileFolderForLoggerName(NSString *loggerName)
{
    NSArray *documentsDirectories = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    if (documentsDirectories == nil || documentsDirectories.count != 1) {
        OBASSERT_NOT_REACHED(@"Expected to find document directory.");
        return nil;
    }
    NSURL *documentsDirectoryURL = documentsDirectories[0];
    
    NSString *logFileFolderName = [NSString stringWithFormat:@".%@", loggerName];
    
    NSURL *logFileFolder = [documentsDirectoryURL URLByAppendingPathComponent:logFileFolderName];
    
    BOOL isDirectory;
    if (![[NSFileManager defaultManager] fileExistsAtPath:logFileFolder.path isDirectory:&isDirectory]) {
        if (![[NSFileManager defaultManager] createDirectoryAtURL:logFileFolder withIntermediateDirectories:NO attributes:nil error:nil]) {
            return nil;
        }
    }
    
    return logFileFolder;
}

static NSString *_logFileSuffix = @".log";

#if REMOVE_OLD_LOG_FILES
// This is hacky time math, but we're only using it for cleaning up old log files, so approximations suffice:
static NSTimeInterval _oneDayInSeconds = 24 * 60 * 60;
static NSTimeInterval _oneWeekInSeconds = 7 * 24 * 60 * 60;
#endif

static void _ProcessLogFiles(NSString *loggerName, NSDate *olderThanDate, OBLogFileHandler handler)
{
    OBPRECONDITION(loggerName != nil);
    OBPRECONDITION(![loggerName isEqualToString:@""]);
    
    NSURL *documentsDirectoryURL = _LogFileFolderForLoggerName(loggerName);
    NSArray *subitems = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:documentsDirectoryURL includingPropertiesForKeys:@[NSURLNameKey, NSURLCreationDateKey] options:0 error:NULL];
    
    for (NSURL *itemURL in subitems) {
        OB_AUTORELEASING NSString *itemName = nil;
        BOOL fetchSucceeded = [itemURL getResourceValue:&itemName forKey:NSURLNameKey error:NULL];
        OB_AUTORELEASING NSDate *creationDate = nil;
        fetchSucceeded |= [itemURL getResourceValue:&creationDate forKey:NSURLCreationDateKey error:NULL];
        if (!fetchSucceeded)
            continue; // default to keeping data
        
        if (olderThanDate != nil && [olderThanDate earlierDate:creationDate] == olderThanDate)
            continue; // new enough to keep
        
        if ([itemName hasPrefix:loggerName] && [itemName hasSuffix:_logFileSuffix]) {
            handler(itemURL);
        }
    }
}

#if REMOVE_OLD_LOG_FILES
static void _RemoveLogFiles(NSString *loggerName, NSDate *olderThanDate)
{
    _ProcessLogFiles(loggerName, olderThanDate, ^(NSURL *itemURL) {
        OB_AUTORELEASING NSError *error = nil;
        if (![[NSFileManager defaultManager] removeItemAtURL:itemURL error:&error]) {
            NSLog(@"Couldn't remove log file with URL \"%@\": %@", itemURL, error);
        }
    });
}
#endif

@interface NSString (OBLoggerExtensions)
- (BOOL)appendToURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)error;
@end

static void _setPOSIXError(NSError **error, NSString *description)
{
    if (error != NULL)
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey:description}];
}

@implementation NSString (OBLoggerExtensions)
- (BOOL)appendToURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)error;
{
    if ([self length] > PIPE_BUF)
        NSLog(@"Can't guarantee atomic writes of strings longer than %d. This string has length %ld", PIPE_BUF, [self length]);
    
    NSData *stringData = [self dataUsingEncoding:NSUTF8StringEncoding];
    
    const char *filePath = [[url path] UTF8String];
    FILE *cFile = fopen(filePath, "a");
    if (cFile == NULL) {
        _setPOSIXError(error, @"error opening file");
        return NO;
    }

    @try {
        size_t bytesWritten = fwrite([stringData bytes], 1, [stringData length], cFile);
        if (bytesWritten < [stringData length]) {
            _setPOSIXError(error, @"error writing to file");
            return NO;
        }
        
        int syncSuccess = fsync(fileno(cFile));
        if (syncSuccess != 0) {
            _setPOSIXError(error, @"error synchronizing file");
            return NO;
        }
    }
    @finally {
        int closeSuccess = fclose(cFile);
        if (closeSuccess != 0) {
            _setPOSIXError(error, @"error closing file");
            return NO;
        }
        return YES;
    }
}
@end

@interface OBLogger ()
@property (nonatomic, strong) NSDateFormatter *messageDateFormatter;
@end

@implementation OBLogger
{
    NSDateFormatter *_fileNameDateFormatter;
    NSOperationQueue *_fileLoggingQueue;
    NSTimer *_logPurgeTimer;
}

- (id)initWithName:(NSString *)name shouldLogToFile:(BOOL)shouldLogToFile;
{
    return [self initWithSuiteName:nil key:name shouldLogToFile:shouldLogToFile];
}

- (id)initWithSuiteName:(nullable NSString *)suiteName key:(NSString *)key shouldLogToFile:(BOOL)shouldLogToFile;
{
    self = [super init];
    if (self == nil)
        return nil;
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    _shouldLogToFile = shouldLogToFile;
#else
    OBASSERT(!shouldLogToFile, @"Don't log to file on OS X. Console isn't truncated there.");
    _shouldLogToFile = NO;
#endif
    
    NSInteger level;
    
    const char *env = getenv([key UTF8String]); /* easier for command line tools */
    if (env) {
        level = strtol(env, NULL, 0);
    } else {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName] ?: [NSUserDefaults standardUserDefaults];
        level = [defaults integerForKey:key];
    }
    
    if (level == 0) {
#if REMOVE_OLD_LOG_FILES
        _RemoveLogFiles(key, nil);
#endif
        return nil;
    }

    NSLog(@"%@: DEBUG LEVEL = %ld", key, level);
    _level = level;
    _suiteName = [suiteName copy];
    _key = [key copy];
    
    _messageDateFormatter = [[NSDateFormatter alloc] init];
    [_messageDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
    [_messageDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.mmm ZZZ"];
    
    _fileNameDateFormatter = [[NSDateFormatter alloc] init];
    [_fileNameDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
    [_fileNameDateFormatter setDateFormat:@"yyyy-MM-dd"];
    
    _fileLoggingQueue = [[NSOperationQueue alloc] init];
    _fileLoggingQueue.maxConcurrentOperationCount = 1;

#if REMOVE_OLD_LOG_FILES
    NSDate *purgeBeforeDate = [NSDate dateWithTimeIntervalSinceNow: - _oneWeekInSeconds];
    _RemoveLogFiles(self.key, purgeBeforeDate);
    
    _logPurgeTimer = [NSTimer timerWithTimeInterval:_oneDayInSeconds target:self selector:@selector(_purgeOldLogFiles:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_logPurgeTimer forMode:NSDefaultRunLoopMode];
#endif

    return self;
}

- (void)dealloc;
{
    [_logPurgeTimer invalidate];
}

- (void)log:(NSString *)format arguments:(va_list)args;
{
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    
    NSLog(@"%@: %@", self.key, message);
    
    if (!self.shouldLogToFile)
        return;

    __weak OBLogger *weakSelf = self;
    [_fileLoggingQueue addOperationWithBlock:^{
        __strong OBLogger *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSString *timeStamp = [strongSelf.messageDateFormatter stringFromDate:[NSDate date]];
        NSString *timeStampedMessage = [[NSString alloc] initWithFormat:@"%@: %@\n", timeStamp, message];
        
        NSURL *logFileURL = [strongSelf _currentLogFile];
        if (logFileURL == nil) {
            NSLog(@"No log file URL for %@", strongSelf.key);
            return;
        }
        
        OB_AUTORELEASING NSError *error = nil;
        if (![timeStampedMessage appendToURL:logFileURL atomically:YES error:&error]) {
            NSLog(@"Error logging for %@: %@", strongSelf.key, error);
        }
    }];
}

- (void)processLogFilesWithHandler:(OBLogFileHandler)handler;
{
    _ProcessLogFiles(self.key, [NSDate distantFuture], handler);
}

- (NSString *)name;
{
    return self.key;
}

#pragma mark - Private API

- (NSURL *)_currentLogFile;
{
    NSString *dateString = [_fileNameDateFormatter stringFromDate:[NSDate date]];
    NSString *logFileName = [NSString stringWithFormat:@"%@ %@%@", self.key, dateString, _logFileSuffix];
    NSURL *logFileURL = [_LogFileFolderForLoggerName(self.name) URLByAppendingPathComponent:logFileName isDirectory:NO];
    
    return logFileURL;
}

#if REMOVE_OLD_LOG_FILES
- (void)_purgeOldLogFiles:(NSTimer *)timer;
{
    NSDate *purgeBeforeDate = [NSDate dateWithTimeIntervalSinceNow: - _oneWeekInSeconds];
    _RemoveLogFiles(self.key, purgeBeforeDate);
}
#endif

@end
