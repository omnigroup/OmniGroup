// Copyright 2013 The Omni Group.  All rights reserved.
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

inline void OBLog(OBLogger *logger, NSInteger messageLevel, NSString *format, ...)
{
    if (logger == nil || messageLevel < logger.level)
        return;
    
    va_list args;
    va_start(args, format);
    [logger log:format arguments:args];
    va_end(args);
}

void _OBLoggerInitializeLogLevel(OBLogger **outLogger, NSString *name, BOOL useFile)
{
    OBLogger *logger = [[OBLogger alloc] initWithName:name shouldLogToFile:useFile];
    if (logger != nil)
        *outLogger = logger;
}

static NSURL * _DocumentsDirectoryURL()
{
    NSArray *documentsDirectories = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    if (documentsDirectories == nil || documentsDirectories.count != 1) {
        OBASSERT_NOT_REACHED(@"Expected to find document directory.");
        return nil;
    }
    NSURL *documentsDirectoryURL = documentsDirectories[0];
    return  documentsDirectoryURL;
}

static NSString *_logFileSuffix = @".log";
// This is hacky time math, but we're only using it for cleaning up old log files, so approximations suffice:
static NSTimeInterval _oneDayInSeconds = 24 * 60 * 60;
static NSTimeInterval _oneWeekInSeconds = 7 * 24 * 60 * 60;

static void _RemoveLogFiles(NSString *loggerName, NSDate *olderThanDate)
{
    OBPRECONDITION(loggerName != nil);
    OBPRECONDITION(![loggerName isEqualToString:@""]);
    
    NSURL *documentsDirectoryURL = _DocumentsDirectoryURL();
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
            OB_AUTORELEASING NSError *error = nil;
            if (![[NSFileManager defaultManager] removeItemAtURL:itemURL error:&error]) {
                NSLog(@"Couldn't remove log file with URL \"%@\": %@", itemURL, error);
            }
        }
    }
}

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
    
    const char *env = getenv([name UTF8String]); /* easier for command line tools */
    if (env)
        level = strtoul(env, NULL, 0);
    else
        level = [[NSUserDefaults standardUserDefaults] integerForKey:name];
    
    if (level == 0) {
        _RemoveLogFiles(name, nil);
        return nil;
    }

    NSLog(@"%@: DEBUG LEVEL = %ld", name, level);
    _level = level;
    _name = [name copy];
    
    _messageDateFormatter = [[NSDateFormatter alloc] init];
    [_messageDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
    [_messageDateFormatter setDateFormat:@"yyyy-MM-dd hh:mm:ss.mmm ZZZ"];
    
    _fileNameDateFormatter = [[NSDateFormatter alloc] init];
    [_fileNameDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
    [_fileNameDateFormatter setDateFormat:@"yyyy-MM-dd"];
    
    _fileLoggingQueue = [[NSOperationQueue alloc] init];
    _fileLoggingQueue.maxConcurrentOperationCount = 1;

    NSDate *purgeBeforeDate = [NSDate dateWithTimeIntervalSinceNow: - _oneWeekInSeconds];
    _RemoveLogFiles(self.name, purgeBeforeDate);
    
    _logPurgeTimer = [NSTimer timerWithTimeInterval:_oneDayInSeconds target:self selector:@selector(_purgeOldLogFiles:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_logPurgeTimer forMode:NSDefaultRunLoopMode];
    
    return self;
}

- (void)dealloc;
{
    [_logPurgeTimer invalidate];
}

- (void)log:(NSString *)format arguments:(va_list)args;
{
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    
    NSLog(@"%@: %@", self.name, message);
    
    if (!self.shouldLogToFile)
        return;

    __weak OBLogger *weakSelf = self;
    [_fileLoggingQueue addOperationWithBlock:^{
        NSString *timeStamp = [weakSelf.messageDateFormatter stringFromDate:[NSDate date]];
        NSString *timeStampedMessage = [[NSString alloc] initWithFormat:@"%@: %@\n", timeStamp, message];
        
        NSURL *logFileURL = [weakSelf _currentLogFile];
        if (logFileURL == nil) {
            NSLog(@"No log file URL for %@", weakSelf.name);
            return;
        }
        
        OB_AUTORELEASING NSError *error = nil;
        if (![timeStampedMessage appendToURL:logFileURL atomically:YES error:&error]) {
            NSLog(@"Error logging for %@: %@", weakSelf.name, error);
        }
    }];
}

#pragma mark - Private API

- (NSURL *)_currentLogFile;
{
    NSURL *documentsDirectory = _DocumentsDirectoryURL();
    NSString *dateString = [_fileNameDateFormatter stringFromDate:[NSDate date]];
    NSString *logFileName = [NSString stringWithFormat:@"%@ %@%@", self.name, dateString, _logFileSuffix];
    NSURL *logFileURL = [documentsDirectory URLByAppendingPathComponent:logFileName isDirectory:NO];
    
    return logFileURL;
}

- (void)_purgeOldLogFiles:(NSTimer *)timer;
{
    NSDate *purgeBeforeDate = [NSDate dateWithTimeIntervalSinceNow: - _oneWeekInSeconds];
    _RemoveLogFiles(self.name, purgeBeforeDate);
}
@end
