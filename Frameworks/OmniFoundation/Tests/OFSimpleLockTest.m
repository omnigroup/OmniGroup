// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

RCS_ID("$Id$")

#define FAIL(s) \
do { \
    fprintf(stderr, "%d: %s\n", __LINE__, s); \
    exit(1); \
} while (0)

#define TEST_LIMIT 100000000

static unsigned int count = 0;
static void *threadTest(void *arg);
static OFSimpleLockType lock;

int main(int argc, char *argv[])
{
    OFSimpleLockBoolean locked;
    pthread_t           thread1, thread2;
    
    OFSimpleLockInit(&lock);
    
    // Some really simple tests
    locked = OFSimpleLockTry(&lock);
    if (!locked)
        FAIL("Expected to be locked");
        
    locked = OFSimpleLockTry(&lock);
    if (locked)
        FAIL("Shouldn't get the lock twice");
        
    OFSimpleUnlock(&lock);
    locked = OFSimpleLockTry(&lock);
    if (!locked)
        FAIL("Unable to relock");
    OFSimpleUnlock(&lock);
    
    pthread_create(&thread1, NULL, threadTest, NULL);
    pthread_create(&thread2, NULL, threadTest, NULL);
    
    pthread_join(thread1, NULL);
    pthread_join(thread2, NULL);
    
    if (count != 2 * TEST_LIMIT)
        FAIL("Wrong count");
        
    return 0;
}


static void *threadTest(void *arg)
{
    unsigned int i;
    
    for (i = 0; i < TEST_LIMIT; i++) {
        OFSimpleLock(&lock);
        count++;
        OFSimpleUnlock(&lock);
    }
    
    return arg;
}

