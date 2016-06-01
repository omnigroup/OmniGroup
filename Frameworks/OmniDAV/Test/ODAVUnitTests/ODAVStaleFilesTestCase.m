// Copyright 2016 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

RCS_ID("$Id$");

#import <XCTest/XCTest.h>
#import <OmniDAV/OmniDAV.h>

static NSString * const TestCaseIdentifier1 = @"testCaseIdentifier1";
static NSString * const TestCaseIdentifier2 = @"testCaseIdentifier2";

@interface ODAVStaleFilesTestCase : XCTestCase
@property (nonatomic) NSMutableDictionary *userDefaultsMock;
@property (nonatomic) ODAVStaleFiles *staleFiles1;
@property (nonatomic) ODAVStaleFiles *staleFiles2;
@end

@implementation ODAVStaleFilesTestCase

- (void)setUp {
    [super setUp];
    
    self.userDefaultsMock = [NSMutableDictionary new];

    self.staleFiles1 = [[ODAVStaleFiles alloc] initWithIdentifier:TestCaseIdentifier1];
    self.staleFiles1.userDefaultsMock = self.userDefaultsMock;

    self.staleFiles2 = [[ODAVStaleFiles alloc] initWithIdentifier:TestCaseIdentifier2];
    self.staleFiles2.userDefaultsMock = self.userDefaultsMock;
}

- (void)testEmptyDirectory {
    self.userDefaultsMock[ODAVStaleFilesPreferenceKey] = [self emptiedExistingRecord];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[] serverDate:[NSDate date]];

    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    XCTAssertNil(self.userDefaultsMock[ODAVStaleFilesPreferenceKey]);
}

- (void)testNonExistentFile {
    self.userDefaultsMock[ODAVStaleFilesPreferenceKey] = [self emptiedExistingRecord];
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:NO directory:NO size:0 lastModifiedDate:[NSDate date]];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];

    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    XCTAssertNil(self.userDefaultsMock[ODAVStaleFilesPreferenceKey]);
}

- (void)testDirectory {
    self.userDefaultsMock[ODAVStaleFilesPreferenceKey] = [self emptiedExistingRecord];
    ODAVFileInfo *file = [self fileInfoWithName:@"Inbox" exists:YES directory:YES size:0 lastModifiedDate:[NSDate date]];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];

    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    XCTAssertNil(self.userDefaultsMock[ODAVStaleFilesPreferenceKey]);
}

- (void)testPatternMismatch {
    self.userDefaultsMock[ODAVStaleFilesPreferenceKey] = [self emptiedExistingRecord];
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:0 lastModifiedDate:[NSDate date]];
    self.staleFiles1.pattern = [NSRegularExpression regularExpressionWithPattern:@"nope" options:0 error:NULL];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    XCTAssertNil(self.userDefaultsMock[ODAVStaleFilesPreferenceKey]);
}

- (void)testPatternMatch {
    self.userDefaultsMock[ODAVStaleFilesPreferenceKey] = [self emptiedExistingRecord];
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:0 lastModifiedDate:[NSDate date]];
    self.staleFiles1.pattern = [NSRegularExpression regularExpressionWithPattern:@"foo.bar" options:0 error:NULL];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:0];
}

- (void)testNewMatch {
    self.userDefaultsMock[ODAVStaleFilesPreferenceKey] = [self emptiedExistingRecord];
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:0 lastModifiedDate:[NSDate date]];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:0];
}

- (void)testNewMatchNoPrefs {
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:0 lastModifiedDate:[NSDate date]];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:0];
}

- (void)testSecondMatchTooSoon {
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:0 lastModifiedDate:[NSDate date]];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    
    // Shouldn't bump count because interval between tests is too short:
    NSDate *tenMinutes = tenMinutesFrom([NSDate date]);
    filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] localDate:tenMinutes serverDate:tenMinutes];
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:0];
}

- (void)testSecondMatchLater {
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:0 lastModifiedDate:[NSDate date]];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];

    // Should bump count because simulated interval is two days:
    NSDate *twoDays = twoDaysFrom([NSDate date]);
    filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] localDate:twoDays serverDate:twoDays];
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:1];
}

- (void)testShouldDelete {
    NSDate *fakeNow = [NSDate date];
    NSInteger matches = 7;
    
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:0 lastModifiedDate:fakeNow];
    NSArray <ODAVFileInfo *> *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] localDate:fakeNow serverDate:fakeNow];
    
    for (NSInteger i = 0; i < matches; i++) {
        XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
        [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:i];
        
        fakeNow = twoDaysFrom(fakeNow);
        filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] localDate:fakeNow serverDate:fakeNow];
    }
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 1);
    XCTAssertEqual(filesToDelete[0].name, @"foo.bar");
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:matches];
}

- (void)testVaryingFileSize {
    NSDate *fileDate = [NSDate date];
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:111 lastModifiedDate:fileDate];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    
    // Shouldn't bump count because file size changed:
    NSDate *twoDays = twoDaysFrom([NSDate date]);
    file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:999 lastModifiedDate:fileDate];
    filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] localDate:twoDays serverDate:twoDays];
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:0];
}

- (void)testVaryingModificationDate {
    NSDate *fileDate = [NSDate date];
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:111 lastModifiedDate:fileDate];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    
    // Shouldn't bump count because file date changed:
    NSDate *twoDays = twoDaysFrom([NSDate date]);
    fileDate = oneDayFrom(fileDate);
    file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:111 lastModifiedDate:fileDate];
    filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] localDate:twoDays serverDate:twoDays];
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:0];
}

- (void)testGarbageCollection {
    NSDate *fileDate = [NSDate date];
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:111 lastModifiedDate:fileDate];
    NSArray *filesToDelete1 = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    NSArray *filesToDelete2 = [self.staleFiles2 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    XCTAssertEqual(filesToDelete1.count, (NSUInteger) 0);
    XCTAssertEqual(filesToDelete2.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:0];
    [self expectIdentifier:TestCaseIdentifier2 mapsToFileNamed:@"foo.bar" withCount:0];

    // Should bump count for one "server" and garbage collect the other
    NSDate *fiftyDays = daysFrom(fileDate, 50);
    filesToDelete1 = [self.staleFiles1 examineDirectoryContents:@[file] localDate:fiftyDays serverDate:fiftyDays];
    
    XCTAssertEqual(filesToDelete1.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:1];
    XCTAssertNil(self.userDefaultsMock[ODAVStaleFilesPreferenceKey][TestCaseIdentifier2]);
}

- (void)testClockSkew {
    NSDate *now = [NSDate date];
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:0 lastModifiedDate:now];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] localDate:now serverDate:now];
    
    // Shouldn't bump count just because of local clock skew
    NSDate *tenMinutes = tenMinutesFrom(now);
    NSDate *testerMonkeyingWithSystemClock = daysFrom(now, 7);
    filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] localDate:testerMonkeyingWithSystemClock serverDate:tenMinutes];
    
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:0];
}

- (void)testBadPrefs {
    // Malformed at deepest level
    self.userDefaultsMock[ODAVStaleFilesPreferenceKey] = @{
                                                           @"ident": @[
                                                                   [NSDate date],
                                                                   [NSDate date],
                                                                   @{@"foo.bar": @{
                                                                             @"mtime": @"NotADateAsExpected"
                                                                             },
                                                                     },
                                                                   ]
                                                           };
 
    ODAVFileInfo *file = [self fileInfoWithName:@"foo.bar" exists:YES directory:NO size:0 lastModifiedDate:[NSDate date]];
    NSArray *filesToDelete = [self.staleFiles1 examineDirectoryContents:@[file] serverDate:[NSDate date]];
    
    // Should have cleared preferences, erasing this mapping:
    XCTAssertNil(self.userDefaultsMock[ODAVStaleFilesPreferenceKey][@"ident"]);
    
    // But continued with the new work
    XCTAssertEqual(filesToDelete.count, (NSUInteger) 0);
    [self expectIdentifier:TestCaseIdentifier1 mapsToFileNamed:@"foo.bar" withCount:0];
}

#pragma mark Helpers

static NSDate *hence(NSDate *start, NSDateComponents *components)
{
    NSDate *result = [[NSCalendar currentCalendar] dateByAddingComponents:components toDate:start options:0];
    return result;
}

static NSDate *daysFrom(NSDate *start, NSInteger days) {
    NSDateComponents *delta = [NSDateComponents new];
    delta.day = days;
    return hence(start, delta);
}

static NSDate *oneDayFrom(NSDate *start) {
    return daysFrom(start, 1);
}

static NSDate *twoDaysFrom(NSDate *start) {
    return daysFrom(start, 2);
}

static NSDate *tenMinutesFrom(NSDate *start) {
    NSDateComponents *tenMinutes = [NSDateComponents new];
    tenMinutes.minute = 10;
    return hence(start, tenMinutes);
}

- (ODAVFileInfo *)fileInfoWithName:(NSString *)name exists:(BOOL)exists directory:(BOOL)directory size:(off_t)size lastModifiedDate:(NSDate *)date;
{
    NSURL *url = [[NSURL URLWithString:@"https://www.example.com/"] URLByAppendingPathComponent:name];
    ODAVFileInfo *result = [[ODAVFileInfo alloc] initWithOriginalURL:url name:name exists:exists directory:directory size:size lastModifiedDate:date];
    return result;
}

- (void)expectIdentifier:(NSString *)identifier mapsToFileNamed:(NSString *)fileName withCount:(NSUInteger)count;
{
    NSArray *arrayForIdent = self.userDefaultsMock[ODAVStaleFilesPreferenceKey][identifier];
    XCTAssertNotNil(arrayForIdent);
    NSDictionary *fileMap = arrayForIdent[2];
    XCTAssertNotNil(fileMap);
    NSDictionary *fileData = fileMap[fileName];
    XCTAssertNotNil(fileData);
    NSNumber *savedCount = fileData[@"n"];
    XCTAssertNotNil(savedCount);
    XCTAssertEqual(savedCount.unsignedIntegerValue, count);
}

- (NSDictionary *)emptiedExistingRecord
{
    return @{
             TestCaseIdentifier1 : @[
                     [NSDate date],
                     [NSDate date],
                     @{},
                     ]
             };
}

@end
