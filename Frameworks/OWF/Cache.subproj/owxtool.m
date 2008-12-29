// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import "OWDiskCacheInternal.h"
#import <OmniIndex/OXDB.h>
#import <OWF/OWAddress.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Cache.subproj/owxtool.m 68913 2005-10-03 19:36:19Z kc $");

void listdb(OXDatabase *db);
void listarc(OXDatabase *db, unsigned int aid, BOOL andContent);
void listcontent(OXDatabase *db, unsigned int cid, BOOL andBytes);

int main (int argc, char **argv)
{
    NSAutoreleasePool *pool;
    OXDatabase *db;
    NSString *dbpath;
    id lockinfo;
    int optchar;

    pool = [[NSAutoreleasePool alloc] init];
    [OBPostLoader processClasses];

    if (argc < 2) {
        fprintf(stderr, "Usage: %s path/to/oxfile.ox [options...]\n", argv[0]);
        return 1;
    }

    dbpath = [NSString stringWithCString:argv[1]];
    [dbpath retain];

    lockinfo = [[NSFileManager defaultManager] lockFileAtPath:dbpath overridingExistingLock:NO];
    if (lockinfo) {
        NSLog(@"Error - database index is locked: %@", [lockinfo description]);
        return 1;
    }

    db = [[OXDatabase alloc] initFromFile:dbpath withCache:12 isNew:NO];
    if (!db) {
        NSLog(@"Error - can't open database at %@", dbpath);
        [[NSFileManager defaultManager] unlockFileAtPath:dbpath];
        return 1;
    }

    [pool release];

    while ((optchar = getopt(argc-1, argv+1, "la:A:c:h:")) != -1) {
        pool = [[NSAutoreleasePool alloc] init];
        switch (optchar) {
            case 'l':
                listdb(db);
                break;
            case 'a':
            case 'A':
                listarc(db, (unsigned int)strtoul(optarg, NULL, 10), ( optchar == 'A'? YES : NO ) );
                break;
            case 'c':
            case 'h':
                listcontent(db, (unsigned int)strtoul(optarg, NULL, 10), ( optchar == 'c'? YES : NO ));
                break;
            default:
                fprintf(stderr, "Unrecognized option '%c'\n", optchar);
                fputs("Options:\n"
                      "\t-l\tList all arcs and content\n"
                      "\t-a ID\tList arc with specified ID\n"
                      "\t-c ID\tList content with specified ID\n"
                      "\t-A ID\tList arc and associated content\n", stderr);
                exit(1);
                break;
        }
        [pool release];
    }


    pool = [[NSAutoreleasePool alloc] init];
    [db release];
    [[NSFileManager defaultManager] unlockFileAtPath:dbpath];
    [dbpath release];
    [pool release];

    return 0;
}

void listdb(OXDatabase *db)
{
    OXTable *arcs, *content;
    OXTupleEnumerator *rowEnumerator;
    OXTuple *row;
    NSCountedSet *refs;
    OXNull *oxNull = [OXNull null];

    arcs = [db tableNamed:@"Arc"];
    if (!arcs) NSLog(@"Can't find table named 'Arc'");
    content = [db tableNamed:@"Content"];
    if (!content) NSLog(@"Can't find table named 'Content'");
    if (!arcs || !content)
        return;
    
    printf("Table %s has columns: %s\nTable %s has columns: %s\n",
           [[arcs name] cString], [[[[arcs tupleType] names] description] cString],
           [[content name] cString], [[[[content tupleType] names] description] cString]);

    refs = [[NSCountedSet alloc] init];
    [refs autorelease];

    printf("Table %s:\n%8s  %8s  %8s  %8s  %8s\n", [[arcs name] cString], "ID", "Src", "Subj", "Obj", "Metadata");
    rowEnumerator = [db queryTable:[arcs name] whereColumn:nil isEqualToValue:nil];
    while( (row = [rowEnumerator nextTuple]) != nil) {
        unsigned int aid;
        NSNumber *src, *subj, *obj;
        id meta;

        aid = [(NSNumber *)[row valueOfColumn:@"aid"] unsignedIntValue];
        src = (NSNumber *)[row valueOfColumn:@"source"];
        subj = (NSNumber *)[row valueOfColumn:@"subject"];
        obj = (NSNumber *)[row valueOfColumn:@"object"];
        meta = [row valueOfColumn:@"metadata"];

        [refs addObject:src];
        [refs addObject:subj];
        [refs addObject:obj];

        printf("%8u  %8u  %8u  %8u  ", aid, [src unsignedIntValue], [subj unsignedIntValue], [obj unsignedIntValue]);
        char buffer[12];
        if (meta != nil && meta != oxNull)
            sprintf(buffer, "(%u b)", [meta length]);
        else
            sprintf(buffer, "%s", "NULL");
        printf("%8s\n", buffer);
    }
    
    printf("Table %s:\n%8s  %4s  %4s  %8s  %4s  %4s  %6s\n", [[content name] cString], "ID", "Refs", "Type", "Vhash", "Meta", "Data", "Long");
    rowEnumerator = [db queryTable:[content name] whereColumn:nil isEqualToValue:nil];
    while( (row = [rowEnumerator nextTuple]) != nil) {
        unsigned int type, vhash;
        NSNumber *cid;
        id sdata, ldata;

        cid = (NSNumber *)[row valueOfColumn:@"cid"];
        type = [(NSNumber *)[row valueOfColumn:@"type"] unsignedIntValue];
        vhash = [(NSNumber *)[row valueOfColumn:@"valuehash"] unsignedIntValue];
        sdata = [row valueOfColumn:@"value"];
        ldata = [row valueOfColumn:@"longvalue"];

        printf("%8u  %4u  %4u  %08x  %4s  ", [cid unsignedIntValue], [refs countForObject:cid], type, vhash, " -- ");
        if (sdata != nil && sdata != oxNull)
            printf("%4u", [sdata length]);
        else
            printf("%4s", "NULL");
        printf("  ");
        if (ldata != nil && ldata != oxNull)
            printf("%6u", [ldata length]);
        else
            printf("%6s", "NULL");
        printf("\n");
    }
}

void listarc(OXDatabase *db, unsigned int aid, BOOL andContent)
{
    OXTupleEnumerator *enumr;
    OXTuple *row;
    NSKeyedUnarchiver *arch;
    NSDate *creationDate, *expirationDate;
    NSDictionary *contextDict;
    NSData *metaData;
    unsigned int so, su, ob;

    enumr = [db queryTable:@"Arc" whereColumn:@"aid" isEqualToValue:[NSNumber numberWithUnsignedInt:aid]];
    row = [enumr nextTuple];
    if (!row) {
        printf("No arc with ID %u\n", aid);
        return;
    }

    printf("Cache arc %u:\n", [(NSNumber *)[row valueOfColumn:@"aid"] unsignedIntValue]);
    so = [(NSNumber *)[row valueOfColumn:@"source"] unsignedIntValue];
    su = [(NSNumber *)[row valueOfColumn:@"subject"] unsignedIntValue];
    ob = [(NSNumber *)[row valueOfColumn:@"object"] unsignedIntValue];
    printf("Subject: %u ", su);
    if (so != su)
        printf("Source: %u ", so);
    printf("Object: %u\n", ob);

    metaData = (NSData *)[row valueOfColumn:@"metadata"];
    creationDate = nil;
    expirationDate = nil;
    contextDict = nil;
    if ([metaData length] > 3 && !memcmp([metaData bytes], "SaM", 3)) {
        // First version of compactified metadata format
        int offset;
        unsigned char flags;

        flags = ((unsigned char *)[metaData bytes])[3];
        offset = 4;
        if (flags & 010) {
            creationDate = [NSDate dateWithTimeIntervalSince1970:*(UInt32 *)([metaData bytes] + offset)];
            offset += 4;
        }
        if (flags & 020) {
            expirationDate = [NSDate dateWithTimeIntervalSince1970:*(UInt32 *)([metaData bytes] + offset)];
            offset += 4;
        }
        if (flags & 040)
            arch = [[NSKeyedUnarchiver alloc] initForReadingWithData:[metaData subdataWithRange:(NSRange){offset, [metaData length]-offset}]];
        else
            arch = nil;
    } else {
        // Old format, just one NSArchived blob
        arch = [[NSKeyedUnarchiver alloc] initForReadingWithData:metaData];
    }

    if (creationDate == nil)
        creationDate = [arch decodeObjectForKey:@"created"];
    contextDict = [arch decodeObjectForKey:@"context"];

    printf("Created: %s\n", [[creationDate description] cString]);
    printf("Expires: %s\n", [[expirationDate description] cString]);
    if (contextDict)
        printf("Context: %s\n", [[contextDict description] cString]);

/*    {
        FILE *fp;
        fflush(stdout);
        fp = popen("hexdump -C", "w");
        fwrite([metaData bytes], [metaData length], 1, fp);
        pclose(fp);
    }
    */

    [arch release];

    if (andContent) {
        listcontent(db, su, YES);
        if (so != su)
            listcontent(db, so, NO);
        listcontent(db, ob, NO);
    }
}

void listcontent(OXDatabase *db, unsigned int cid, BOOL andBytes)
{
    OXTupleEnumerator *enumr;
    OXTuple *row;
    unsigned int type, vhash;
    OWAddress *addressEntry;
    NSData *dataEntry;
    NSDictionary *headers;
    FILE *fp;

    enumr = [db queryTable:@"Content" whereColumn:@"cid" isEqualToValue:[NSNumber numberWithUnsignedInt:cid]];
    row = [enumr nextTuple];
    if (!row) {
        printf("No content entry with ID %u\n", cid);
        return;
    }

    printf("Cache content item %u:\n", [(NSNumber *)[row valueOfColumn:@"cid"] unsignedIntValue]);
    headers = (NSDictionary *)[row valueOfColumn:@"metadata"];
    printf("%s\n", [[headers description] cString]);
    type = [(NSNumber *)[row valueOfColumn:@"type"] unsignedIntValue];
    vhash = [(NSNumber *)[row valueOfColumn:@"valuehash"] unsignedIntValue];
    id storedConcreteValue = [row valueOfColumn:@"value"];
    if (storedConcreteValue == [OXNull null] || storedConcreteValue == nil)
        storedConcreteValue = [row valueOfColumn:@"longvalue"];
    printf("Type: %u ", type);
    switch((enum OWDiskCacheConcreteContentType)type) {
        case OWDiskCacheAddressConcreteType:
            printf(" (Address / URL)\nHash: %08x\n", vhash);
            addressEntry = [NSKeyedUnarchiver unarchiveObjectWithData:storedConcreteValue];
            printf("Value: %s\n", [[addressEntry description] cString]);
            break;
        case OWDiskCacheBytesConcreteType:
            printf(" (Data)\nHash: %08x\n", vhash);
            if (andBytes) {
                dataEntry = storedConcreteValue;
                fflush(stdout);
                fp = popen("hexdump -C", "w");
                fwrite([dataEntry bytes], [dataEntry length], 1, fp);
                pclose(fp);
            }
            break;
        case OWDiskCacheExceptionConcreteType:
            printf(" (Error Result)\nHash: %08x\n", vhash);
            // ...;
            break;
        default:
            printf(" (Unknown type - version mismatch?)\n");
            break;
    } 
}

