// Copyright 2012-2013 The Omni Group. All rights reserved.

#import "OFXAccountActivity.h"

#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXFileMetadata.h>
#import <OmniFileExchange/OFXRegistrationTable.h>
#import <OmniFileExchange/OFXServerAccount.h>

RCS_ID("$Id$")

#define TIME_BETWEEN_UPDATES 0.5

static unsigned OFXAccountActivityContext;

@interface OFXAccountActivity ()
{
    NSTimeInterval _lastUpdateTime;
    NSTimer *_updateTimer;
}

@property(nonatomic,readonly) OFXAgent *agent;
@property(nonatomic) OFXServerAccount *account;

@property(nonatomic) NSUInteger downloadingFileCount;
@property(nonatomic) unsigned long long downloadingSize;

@property(nonatomic) NSUInteger uploadingFileCount;
@property(nonatomic) unsigned long long uploadingSize;

@property(nonatomic) BOOL isActive;
@property(nonatomic) NSError *lastError;

@property(nonatomic) NSDate *lastSyncDate;

@end


@implementation OFXAccountActivity

- initWithRunningAccount:(OFXServerAccount *)account agent:(OFXAgent *)agent;
{
    OBPRECONDITION([NSThread isMainThread], @"Do KVO and globals access on the main thread only");
    OBPRECONDITION(agent);
    OBPRECONDITION(account);
    
    if (!(self = [super init]))
        return nil;
    
    _agent = agent;
    
    _account = account;
    [_account addObserver:self forKeyPath:OFValidateKeyPath(_account, isSyncInProgress) options:0 context:&OFXAccountActivityContext];
    [_account addObserver:self forKeyPath:OFValidateKeyPath(_account, lastError) options:0 context:&OFXAccountActivityContext];
    
    _registrationTable = [agent metadataItemRegistrationTableForAccount:account];
    OBASSERT(_registrationTable);

    [_registrationTable addObserver:self forKeyPath:OFValidateKeyPath(_registrationTable, values) options:0 context:&OFXAccountActivityContext];
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_account);
    
    [_account removeObserver:self forKeyPath:OFValidateKeyPath(_account, isSyncInProgress) context:&OFXAccountActivityContext];
    [_account removeObserver:self forKeyPath:OFValidateKeyPath(_account, lastError) context:&OFXAccountActivityContext];
    [_registrationTable removeObserver:self forKeyPath:OFValidateKeyPath(_registrationTable, values)];
}

#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    OBPRECONDITION([NSThread isMainThread], @"Do KVO and globals access on the main thread only");

    if (context != &OFXAccountActivityContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    
    if (object == _registrationTable) {
        if (_updateTimer)
            return;
        
        NSTimeInterval nowTime = [[NSDate date] timeIntervalSinceReferenceDate];
        NSTimeInterval timePassed = (nowTime - _lastUpdateTime);
        
        if (timePassed >= TIME_BETWEEN_UPDATES) {
            _lastUpdateTime = nowTime;
            [self _updateValues];
        } else {
            NSTimeInterval timeUntilNextUpdate = TIME_BETWEEN_UPDATES - timePassed;
            _lastUpdateTime = nowTime + timeUntilNextUpdate;
            _updateTimer = [NSTimer scheduledTimerWithTimeInterval:timeUntilNextUpdate target:self selector:@selector(_updateValues) userInfo:nil repeats:NO];
        }
    } else if (object == _account) {
        self.isActive = _account.isSyncInProgress;
        self.lastError = _account.lastError;
        DEBUG_ACTIVITY(1, @"active:%d lastError:%@", self.isActive, self.lastError);
    }
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, _account.uuid];
}

#pragma mark - Private

- (void)_updateValues;
{
    OBPRECONDITION([NSThread isMainThread], @"Do KVO and globals access on the main thread only");
    
    _updateTimer = nil;
    
    NSUInteger newDownloadCount = 0;
    unsigned long long newDownloadSize = 0;
    NSUInteger newUploadCount = 0;
    unsigned long long newUploadSize = 0;
    NSUInteger newDeletingCount = 0;
    
    for (OFXFileMetadata *metadata in _registrationTable.values) {
        if (metadata.deleting) {
            newDeletingCount++;
        } else {
            if (metadata.isDownloading || metadata.hasDownloadQueued || (!metadata.isDownloaded && _agent.automaticallyDownloadFileContents)) {
                newDownloadCount++;
                newDownloadSize += (1.0 - metadata.percentDownloaded) * metadata.fileSize;
            }
            if (metadata.isUploading || !metadata.isUploaded) {
                newUploadCount++;
                newUploadSize += (1.0 - metadata.percentUploaded) * metadata.fileSize;
            }
        }
    }
    
    if (newDownloadCount != _downloadingFileCount)
        self.downloadingFileCount = newDownloadCount;
    if (newDownloadSize != _downloadingSize)
        self.downloadingSize = newDownloadSize;
    if (newUploadCount != _uploadingFileCount)
        self.uploadingFileCount = newUploadCount;
    if (newUploadSize != _uploadingSize)
        self.uploadingSize = newUploadSize;
    DEBUG_ACTIVITY(1, @"download: %ld@%qd upload: %ld@%qd", self.downloadingFileCount, self.downloadingSize, self.uploadingFileCount, self.uploadingSize);
    
    BOOL newActive = (newDownloadCount > 0 || newUploadCount > 0 || newDeletingCount > 0);
    if (newActive != _isActive) {
        self.isActive = newActive;
        if (!newActive)
            self.lastSyncDate = [NSDate date];
        DEBUG_ACTIVITY(1, @"active:%d lastSyncDate:%@", self.isActive, self.lastSyncDate);
    }
}

@end
