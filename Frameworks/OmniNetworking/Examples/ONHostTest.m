// Copyright 2003-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniNetworking/OmniNetworking.h>
#include <unistd.h>
#include <pthread.h>

RCS_ID("$Id$");

struct workArea {
    int byName;
    NSConditionLock *resultLock;
    NSMutableArray *resultQueue;
    int workerCount;
} work;
    

void startWorkers(int numAddrs, int numWorkers, const char *format);
void *lookupWorker(void *arg);
void collectResults();

int main(int argc, char * const *argv)
{
    NSAutoreleasePool *pool;
    int addrCount, workerCount;
    const char *lookupFormat, *resolverType;
    int opt;

    [OBObject class];

    addrCount = 254;
    workerCount = 30;
    lookupFormat = NULL;
    resolverType = NULL;
    work.byName = NO;
    while((opt = getopt(argc, argv, "c:w:f:Nr:")) >= 0) {
        if (opt == 'c')
            addrCount = atoi(optarg);
        else if (opt == 'w')
            workerCount = atoi(optarg);
        else if (opt == 'f')
            lookupFormat = optarg;
        else if (opt == 'N')
            work.byName = YES;
        else if (opt == 'r')
            resolverType = optarg;
        else {
            fprintf(stderr, "%s: bad usage\n", argv[0]);
            exit(1);
        }
    }

    pool = [[NSAutoreleasePool alloc] init];

    if (resolverType) {
        [ONHost setResolverType:[NSString stringWithCString:resolverType]];
    }

    [ONServiceEntry hintPort:5222 forServiceNamed:@"jabber" protocolName:@"tcp"];

    NSLog(@"Hab: %@", [[ONHost hostForHostname:@"google.com"] portAddressesForService:[ONServiceEntry smtpService]]);

    startWorkers(addrCount, workerCount, lookupFormat);

    [pool release];
    pool = [[NSAutoreleasePool alloc] init];
    
    collectResults();

    NSLog(@"Expecting %d unique hosts, %d total", addrCount, addrCount * workerCount);
    
    [pool release];

    return 0;
}

void startWorkers(int numAddrs, int numWorkers, const char *fmt)
{
    NSMutableArray *args;
    int i;

    NSString *format = fmt? [NSString stringWithCString:fmt] : @"198.151.161.%d";

    args = [NSMutableArray array];
    for(i = 1; i <= numAddrs; i++) {
        NSString *n = [NSString stringWithFormat:format, i];
        
        if (!work.byName && !(i % 3))
            n = [NSString stringWithFormat:@"[%@]", n];

        [args addObject:n];
    }

    work.resultLock = [[NSConditionLock alloc] initWithCondition:NO];
    work.resultQueue = [[NSMutableArray alloc] init];
    work.workerCount = numWorkers;

    NSLog(@"Starting %d threads to resolve %d addresses.", numWorkers, [args count]);

    for (i = 0; i < numWorkers; i++) {
        pthread_t worker;
        if(pthread_create(&worker, NULL, lookupWorker, (void *)[args retain])) {
            perror("pthread_create");
            exit(1);
        }
        pthread_detach(worker);
    }
}

void *lookupWorker(void *arg)
{
    NSMutableArray *lookTheseUp;

    lookTheseUp = [[NSMutableArray alloc] initWithArray:(NSArray *)arg];
    [(id)arg release];

    while([lookTheseUp count] > 0) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        unsigned int anArgIndex;
        NSString *anArg;
        ONHostAddress *anAddress;
        ONHost *aHost;

        anArgIndex = (unsigned int)( random() % [lookTheseUp count] );
        anArg = [lookTheseUp objectAtIndex:anArgIndex];
        anAddress = nil;
        NS_DURING {
            if (work.byName) {
                anAddress = nil;
                aHost = [ONHost hostForHostname:anArg];
            } else {
                anAddress = [ONHostAddress hostAddressWithNumericString:anArg];
                aHost = [ONHost hostForAddress:anAddress];
            }
        } NS_HANDLER {
            aHost = nil;
            NSLog(@"Exception for %@/%@: %@", anArg, anAddress, localException);
        } NS_ENDHANDLER;
        
        [lookTheseUp removeObjectAtIndex:anArgIndex];

        if(aHost != nil) {
            [work.resultLock lock];
            [work.resultQueue addObject:aHost];
            [work.resultLock unlockWithCondition:YES];
        }

        [pool release];
    }

    [work.resultLock lock];
    work.workerCount --;
    [work.resultLock unlockWithCondition:YES];

    return NULL;
}

void collectResults()
{
    NSMutableSet *seen;
    int totalReturned, uniqueReturned;
    int workersRemaining;

    seen = [NSMutableSet set];
    totalReturned = 0;
    uniqueReturned = 0;
    
    do {
        NSArray *results;
        int resultIndex, resultCount;
        
        [work.resultLock lockWhenCondition:YES];
        results = [[NSArray alloc] initWithArray:work.resultQueue];
        [work.resultQueue removeAllObjects];
        workersRemaining = work.workerCount;
        [work.resultLock unlockWithCondition:NO];

        resultCount = [results count];
        for(resultIndex = 0; resultIndex < resultCount; resultIndex ++) {
            ONHost *result = [results objectAtIndex:resultIndex];
            BOOL seenThis;

            seenThis = [seen containsObject:result];
            NSLog(@"%c %@ (%@) = %@",
                  seenThis?'+':' ',
                  [result hostname], [result canonicalHostname], [[result addresses] description]);
            if (seenThis && [seen member:result] != result) {
                NSLog(@" **Warning: duplicate ONHost: %@ and %@",
                      OBShortObjectDescription(result),
                      OBShortObjectDescription([seen member:result]));
            }
            [seen addObject:result];
            if (!seenThis) {
                uniqueReturned ++;
            }
            totalReturned ++;
        }

        [results release];
    } while (workersRemaining > 0);

    NSLog(@"Returned %d hosts with %d unique (%d in set)",
          totalReturned, uniqueReturned, [seen count]);

    NSLog(@"Collected: %@", [seen description]);
}
