// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>

RCS_ID("$Id$");

@interface OFFileTests : OFTestCase
{
    NSString *scratchDir;
}

@end


@implementation OFFileTests

- (void)setUp
{
    if (!scratchDir) {
        scratchDir = [[[NSFileManager defaultManager] scratchDirectoryPath] copy];
        NSLog(@"%@: Scratch directory is %@", OBShortObjectDescription(self), scratchDir);
    }
}

- (void)tearDown
{
    if (scratchDir) {
        NSLog(@"%@: Deleting directory %@", OBShortObjectDescription(self), scratchDir);
        [[NSFileManager defaultManager] removeItemAtPath:scratchDir error:NULL];
        [scratchDir release];
        scratchDir = nil;
    }
}

- (void)testMakeDirectories
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    BOOL isD;
    
    OBShouldNotError([fm createPathToFile:[scratchDir stringByAppendingPathComponent:@"doo/dah/day"] attributes:nil error:&error]);
    
    STAssertTrue([fm fileExistsAtPath:[scratchDir stringByAppendingPathComponent:@"doo/dah"] isDirectory:&isD] && isD, nil);
    STAssertFalse([fm fileExistsAtPath:[scratchDir stringByAppendingPathComponent:@"doo/dah/day"]], nil);
    
    STAssertEqualObjects([scratchDir stringByAppendingPathComponent:@"doo/dah"],
                         [fm existingPortionOfPath:[scratchDir stringByAppendingPathComponent:@"doo/dah"]], nil);
    STAssertEqualObjects([scratchDir stringByAppendingPathComponent:@"doo"],
                         [fm existingPortionOfPath:[scratchDir stringByAppendingPathComponent:@"doo"]], nil);
    STAssertEqualObjects([scratchDir stringByAppendingString:@"/doo/dah/"],
                         [fm existingPortionOfPath:[scratchDir stringByAppendingPathComponent:@"doo/dah/dilly/dally"]], nil);
    
    OBShouldNotError([@"bletcherous" writeToFile:[scratchDir stringByAppendingPathComponent:@"doo/dah/day"] atomically:NO encoding:NSUTF8StringEncoding error:&error]);
    STAssertTrue([fm fileExistsAtPath:[scratchDir stringByAppendingPathComponent:@"doo/dah/day"] isDirectory:&isD] && !isD, nil);
    
    STAssertEqualObjects([NSArray array],
                         [fm directoryContentsAtPath:[scratchDir stringByAppendingPathComponent:@"doo/dah"] havingExtension:@"blah" error:NULL], nil);
    STAssertEqualObjects(nil,
                         [fm directoryContentsAtPath:[scratchDir stringByAppendingPathComponent:@"doo/dork"] havingExtension:@"blah" error:NULL], nil);

    OBShouldNotError([@"bletcherous" writeToFile:[scratchDir stringByAppendingPathComponent:@"doo/dah/day.blah"] atomically:NO encoding:NSUTF8StringEncoding error:&error]);
    STAssertEqualObjects([NSArray arrayWithObject:@"day.blah"],
                         [fm directoryContentsAtPath:[scratchDir stringByAppendingPathComponent:@"doo/dah"] havingExtension:@"blah" error:NULL], nil);
    STAssertEqualObjects(nil,
                         [fm directoryContentsAtPath:[scratchDir stringByAppendingPathComponent:@"doo/dah/day"] havingExtension:@"blah" error:NULL], nil);
    
    error = nil;
    BOOL ok = [fm createPathToFile:[scratchDir stringByAppendingPathComponent:@"doo/dah/day/ding/dong"] attributes:nil error:&error];
    STAssertTrue(!ok, @"createPathToFile:... err=%@", error);
    STAssertEqualObjects([error domain], NSPOSIXErrorDomain, nil);
    NSLog(@"Failure message as expected (file in the way): %@", [error description]);
    
    error = nil;
    ok = [fm createPathToFile:[scratchDir stringByAppendingPathComponent:@"doo/dah/day"] attributes:nil error:&error];
    STAssertTrue(ok, @"createPathToFile:... err=%@", error);
    
    [fm removeItemAtPath:[scratchDir stringByAppendingPathComponent:@"doo/dah/day"] error:NULL];
    ok = [fm setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0111] forKey:NSFilePosixPermissions] ofItemAtPath:[scratchDir stringByAppendingPathComponent:@"doo/dah"] error:&error];
    STAssertTrue(ok, @"setAttributes:... ofItemAtPath:%@ err=%@", [scratchDir stringByAppendingPathComponent:@"doo/dah"], error);
    
    error = nil;
    ok = [fm createPathToFile:[scratchDir stringByAppendingPathComponent:@"doo/dah/day/ding/dong"] attributes:nil error:&error];
    STAssertTrue(!ok, @"createPathToFile:... err=%@", error);
    STAssertEqualObjects([error domain], NSPOSIXErrorDomain, nil);
    NSLog(@"Failure message as expected (no write permission): %@", [error description]);
}

- (void)testMakeDirectoriesWithMode
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *e = nil;
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0700]
                                                           forKey:NSFilePosixPermissions];
    
    e = nil;
    BOOL ok = [fm createPathToFile:[scratchDir stringByAppendingPathComponent:@"fee/fie/fo"] attributes:attributes error:&e];
    STAssertTrue(ok, @"createPathToFile:... err=%@", e);
        
    STAssertEqualObjects([NSNumber numberWithInt:0700], [[fm attributesOfItemAtPath:[scratchDir stringByAppendingPathComponent:@"fee"] error:NULL] objectForKey:NSFilePosixPermissions], @"file mode");
    STAssertEqualObjects([NSNumber numberWithInt:0700], [[fm attributesOfItemAtPath:[scratchDir stringByAppendingPathComponent:@"fee/fie"] error:NULL] objectForKey:NSFilePosixPermissions], @"file mode");
    STAssertFalse([fm fileExistsAtPath:[scratchDir stringByAppendingPathComponent:@"fee/fie/fo"]], nil);
    
    
    attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0750] forKey:NSFilePosixPermissions];
    ok = [fm createPathToFile:[scratchDir stringByAppendingPathComponent:@"fee/fie/fo/fum/fiddle!sticks/goo"] attributes:attributes error:&e];
    STAssertTrue(ok, @"createPathToFile:... err=%@", e);
    
    STAssertEqualObjects([NSNumber numberWithInt:0700], [[fm attributesOfItemAtPath:[scratchDir stringByAppendingPathComponent:@"fee"] error:NULL] objectForKey:NSFilePosixPermissions], @"file mode");
    STAssertEqualObjects([NSNumber numberWithInt:0700], [[fm attributesOfItemAtPath:[scratchDir stringByAppendingPathComponent:@"fee/fie"] error:NULL] objectForKey:NSFilePosixPermissions], @"file mode");
    STAssertEqualObjects([NSNumber numberWithInt:0750], [[fm attributesOfItemAtPath:[scratchDir stringByAppendingPathComponent:@"fee/fie/fo"] error:NULL] objectForKey:NSFilePosixPermissions], @"file mode");
    STAssertEqualObjects([NSNumber numberWithInt:0750], [[fm attributesOfItemAtPath:[scratchDir stringByAppendingPathComponent:@"fee/fie/fo/fum"] error:NULL] objectForKey:NSFilePosixPermissions], @"file mode");
    STAssertEqualObjects([NSNumber numberWithInt:0750], [[fm attributesOfItemAtPath:[scratchDir stringByAppendingPathComponent:@"fee/fie/fo/fum/fiddle!sticks"] error:NULL] objectForKey:NSFilePosixPermissions], @"file mode");
    STAssertFalse([fm fileExistsAtPath:[scratchDir stringByAppendingPathComponent:@"fee/fie/fo/fum/fiddle!sticks/goo"]], nil);
}

- (void)testExchangeObjects
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL ok;

    NSString *workingDir = [scratchDir stringByAppendingPathComponent:@"fsexchange"];
    ok = [fm createDirectoryAtPath:workingDir withIntermediateDirectories:NO attributes:nil error:NULL];
    STAssertTrue(ok, @"createDirectoryAtPath:...");
    
    NSError *error = nil;
    
    OBShouldNotError([@"tweedledee" writeToFile:[workingDir stringByAppendingPathComponent:@"bigend"] atomically:NO encoding:NSUTF8StringEncoding error:&error]);
    OBShouldNotError([@"tweedledum" writeToFile:[workingDir stringByAppendingPathComponent:@"littleend"] atomically:NO encoding:NSUTF8StringEncoding error:&error]);
    STAssertEqualObjects(([NSArray arrayWithObjects:@"bigend", @"littleend", nil]),
                         [fm contentsOfDirectoryAtPath:workingDir error:NULL], nil);
    
    
    STAssertEqualObjects([NSString stringWithContentsOfFile:[workingDir stringByAppendingPathComponent:@"bigend"]
                                                   encoding:NSASCIIStringEncoding error:NULL],
                         @"tweedledee", nil);
    ok = [fm replaceFileAtPath:[workingDir stringByAppendingPathComponent:@"bigend"] withFileAtPath:[workingDir stringByAppendingPathComponent:@"littleend"] error:NULL];
    STAssertTrue(ok, @"replaceFileAtPath:...", nil);
    STAssertEqualObjects(([NSArray arrayWithObjects:@"bigend", nil]),
                         [fm contentsOfDirectoryAtPath:workingDir error:NULL], nil);
    STAssertEqualObjects([NSString stringWithContentsOfFile:[workingDir stringByAppendingPathComponent:@"bigend"]
                                                   encoding:NSASCIIStringEncoding error:NULL],
                         @"tweedledum", nil);
    
    
    OBShouldNotError([@"tweedledork" writeToFile:[workingDir stringByAppendingPathComponent:@"middleend"] atomically:NO encoding:NSUTF8StringEncoding error:&error]);
    ok = [fm exchangeFileAtPath:[workingDir stringByAppendingPathComponent:@"bigend"] withFileAtPath:[workingDir stringByAppendingPathComponent:@"middleend"] error:NULL];
    STAssertTrue(ok, @"exchangeFileAtPath:...", nil);
    STAssertEqualObjects(([NSArray arrayWithObjects:@"bigend", @"middleend", nil]),
                         [fm contentsOfDirectoryAtPath:workingDir error:NULL], nil);
    STAssertEqualObjects([NSString stringWithContentsOfFile:[workingDir stringByAppendingPathComponent:@"bigend"]
                                                   encoding:NSASCIIStringEncoding error:NULL],
                         @"tweedledork", nil);
    STAssertEqualObjects([NSString stringWithContentsOfFile:[workingDir stringByAppendingPathComponent:@"middleend"]
                                                   encoding:NSASCIIStringEncoding error:NULL],
                         @"tweedledum", nil);    
}

- (void)testExchangeObjectsCrossVolume:(NSString *)volsize :(NSString *)fstype
{
    BOOL ok, exists;
    int rv;
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *volname = [@"TX" stringByAppendingString:fstype];
    NSString *workingDir = [scratchDir stringByAppendingPathComponent:[NSString stringWithFormat:@"fsexchange_%@", fstype]];
    ok = [fm createDirectoryAtPath:workingDir withIntermediateDirectories:NO attributes:nil error:NULL];
    STAssertTrue(ok, @"createDirectoryAtPath:...");

    NSString *otherworking = [@"/Volumes" stringByAppendingPathComponent:volname];
    exists = [fm directoryExistsAtPath:otherworking traverseLink:NO];
    STAssertFalse(exists, @"Mount point must be unoccupied for this to work");
    if (exists)
        return;
    
    NSString *sh = [NSString stringWithFormat:@"cd '%@' && hdiutil create -quiet -size %@ -fs %@ -volname '%@' -attach testvolume.dmg",
                    workingDir, volsize, fstype, volname];
    rv = system([sh UTF8String]);
    STAssertTrue(rv == 0, @"Creating disk image failed (shell command: %@)", sh);
    if (rv != 0)
        return;
    exists = [fm directoryExistsAtPath:otherworking traverseLink:NO];
    STAssertTrue(exists, @"Mounted volume didn't appear at the expected location");
    if (!exists)
        return;

    NSError *error = nil;
    
    OBShouldNotError([@"bacon" writeToFile:[workingDir stringByAppendingPathComponent:@"layer1.txt"] atomically:NO encoding:NSUTF8StringEncoding error:&error]);
    OBShouldNotError([@"lettuce" writeToFile:[otherworking stringByAppendingPathComponent:@"layer1.txt"] atomically:NO encoding:NSUTF8StringEncoding error:&error]);
    
    ok = [fm replaceFileAtPath:[otherworking stringByAppendingPathComponent:@"layer1.txt"] withFileAtPath:[workingDir stringByAppendingPathComponent:@"layer1.txt"] error:NULL];
    STAssertTrue(ok, @"exchangeFileAtPath:...", nil);
    STAssertEqualObjects(([NSArray arrayWithObjects:@"layer1.txt", nil]),
                         [fm directoryContentsAtPath:otherworking havingExtension:@"txt" error:NULL], nil);
    STAssertEqualObjects(([NSArray array]),
                         [fm directoryContentsAtPath:workingDir havingExtension:@"txt" error:NULL], nil);
    STAssertEqualObjects([NSString stringWithContentsOfFile:[otherworking stringByAppendingPathComponent:@"layer1.txt"]
                                                   encoding:NSASCIIStringEncoding error:NULL],
                         @"bacon", nil);
    
    OBShouldNotError([@"tomato" writeToFile:[workingDir stringByAppendingPathComponent:@"vegetable.txt"] atomically:NO encoding:NSUTF8StringEncoding error:&error]);
    ok = [fm replaceFileAtPath:[otherworking stringByAppendingPathComponent:@"layer1.txt"] withFileAtPath:[workingDir stringByAppendingPathComponent:@"layer1.txt"] error:NULL];
    STAssertTrue(ok, @"exchangeFileAtPath:...", nil);
    
    sh = [NSString stringWithFormat:@"hdiutil detach '/Volumes/%@' -force", volname];
    rv = system([sh UTF8String]);
    STAssertTrue(rv == 0, @"Detaching disk image failed (shell command: %@)", sh);
    if (rv != 0)
        return;
    exists = [fm directoryExistsAtPath:otherworking traverseLink:NO];
    STAssertFalse(exists, @"hdiutil detach apparently didn't clear out the mount point?");
    if (exists)
        return;
    
    sh = [NSString stringWithFormat:@"cd '%@' && hdiutil attach -readonly testvolume.dmg", workingDir];
    rv = system([sh UTF8String]);
    STAssertTrue(rv == 0, @"Remounting disk image readonly failed (shell command: %@)", sh);
    if (rv != 0)
        return;
    exists = [fm directoryExistsAtPath:otherworking traverseLink:NO];
    STAssertTrue(exists, @"Mounted volume didn't appear at the expected location");
    if (!exists)
        return;
    
    OBShouldNotError([@"mayonnaise" writeToFile:[workingDir stringByAppendingPathComponent:@"condiment.txt"] atomically:NO encoding:NSUTF8StringEncoding error:&error]);
    ok = [fm replaceFileAtPath:[otherworking stringByAppendingPathComponent:@"layer1.txt"] withFileAtPath:[workingDir stringByAppendingPathComponent:@"condiment.txt"] error:&error];
    STAssertFalse(ok, @"Shouldn't be able to replace on a readonly volume");
    STAssertNotNil(error, @"Failure should produce an NSError result");
    // NSLog(@"Resulting error: %@", [e toPropertyList]);
    
    sh = [NSString stringWithFormat:@"hdiutil detach '/Volumes/%@' -force", volname];
    rv = system([sh UTF8String]);
    STAssertTrue(rv == 0, @"Detaching disk image failed (shell command: %@)", sh);
}

- (void)testExchangeObjectsCrossVolumeHFSPlus
{
    if (![[self class] shouldRunSlowUnitTests]) {
        NSLog(@"Skipping slow test %@", NSStringFromSelector(_cmd));
        return;
    }
    return [self testExchangeObjectsCrossVolume:@"1m" :@"HFS+"];
}

- (void)testExchangeObjectsCrossVolumeHFSPlusJournaled
{
    if (![[self class] shouldRunSlowUnitTests]) {
        NSLog(@"Skipping slow test %@", NSStringFromSelector(_cmd));
        return;
    }
    // Journaled filesystems need to be pretty big.
    return [self testExchangeObjectsCrossVolume:@"32m" :@"HFS+J"];
}

- (void)testExchangeObjectsCrossVolumeMSDOS
{
    // The reason to use an MSDOS file system is that FSExchangeObjects won't work on it, so we can exercise the renaming-dance code path in -exchangeFileAtPath:.
    if (![[self class] shouldRunSlowUnitTests]) {
        NSLog(@"Skipping slow test %@", NSStringFromSelector(_cmd));
        return;
    }
    return [self testExchangeObjectsCrossVolume:@"256k" :@"MS-DOS"];
}

#if 0

// Directories can't have HFS type/creator info, so this test fails.
// Should replace it with something that directories can have (other than POSIX mode).

- (void)testMakeDirectoriesWithAttr
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *e = nil;
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:NSFileTypeForHFSTypeCode('t3sT')
                                                           forKey:NSFileHFSTypeCode];
    
    e = nil;
    BOOL ok = [fm createPathToFile:[scratchDir stringByAppendingPathComponent:@"ping/pong"] attributes:attributes error:&e];
    STAssertTrue(ok, @"createPathToFile:... err=%@", e);
    
#warning Deprecated NSFileManager API; use the NSError-returning methods instead
    NSDictionary *ratts = [fm fileAttributesAtPath:[scratchDir stringByAppendingPathComponent:@"ping"] traverseLink:NO];
    STAssertFalse([fm fileExistsAtPath:[scratchDir stringByAppendingPathComponent:@"ping/pong"]], nil);
    
    STAssertEqualObjects([ratts fileType], NSFileTypeDirectory, nil);
    STAssertEquals([ratts fileHFSTypeCode], ((OSType)'t3st'), nil);
}

#endif

@end
