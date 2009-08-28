// Copyright 2001-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFClobberDetectionZone.h>

#import <OmniFoundation/OFSimpleLock.h>
#import <OmniFoundation/OFBTree.h>

#import <pthread.h>
#import <stdlib.h>
#import <unistd.h>
#import <mach/mach_init.h>
#import <mach/vm_map.h>

RCS_ID("$Id$")


//#define USE_MUTEX

#define SMALL_ALLOCATION_SLOTS (32)

#define ROUND_ALLOCATION(x)   ((x + (sizeof(unsigned int) - 1)) & ~(sizeof(unsigned int) - 1))
#define MIN_ALLOCATION        ROUND_ALLOCATION(sizeof(unsigned int))
#define ZERO_BLOCK_SIZE       (SMALL_ALLOCATION_SLOTS * vm_page_size)

#define BLOCK_AGEING_LENGTH   (64*1024)

#ifdef USE_MUTEX
#define ZLOCK(zone) pthread_mutex_lock(&zone->lock)
#define ZUNLOCK(zone) pthread_mutex_unlock(&zone->lock)
#else
#define ZLOCK(zone) OFSimpleLock(&zone->lock)
#define ZUNLOCK(zone) OFSimpleUnlock(&zone->lock)
#endif


static kern_return_t _OFClobberDetectionZoneEnumerator(task_t task, void *, unsigned type_mask, vm_address_t zone_address, memory_reader_t reader, vm_range_recorder_t recorder);
static size_t	_OFClobberDetectionZoneGoodSize(malloc_zone_t *zone, size_t size);
static boolean_t 	_OFClobberDetectionZoneCheck(malloc_zone_t *zone);
static void 	_OFClobberDetectionZonePrint(malloc_zone_t *zone, boolean_t verbose);
static void	_OFClobberDetectionZoneLog(malloc_zone_t *zone, void *address);
static void	_OFClobberDetectionZoneForceLock(malloc_zone_t *zone);
static void	_OFClobberDetectionZoneForceUnlock(malloc_zone_t *zone);

static void *_OFClobberDetectionZoneRealloc(struct _malloc_zone_t *zone, void *ptr, size_t size);
static void *_OFClobberDetectionZoneMalloc(struct _malloc_zone_t *zone, size_t size);
static void _OFClobberDetectionZoneFree(struct _malloc_zone_t *zone, void *ptr);
static void _OFClobberDetectionZoneDestroy(struct _malloc_zone_t *zone);
static void *_OFClobberDetectionZoneCalloc(struct _malloc_zone_t *zone, size_t num_items, size_t size);
static void *_OFClobberDetectionZoneValloc(struct _malloc_zone_t *zone, size_t size);
static size_t _OFClobberDetectionZoneSize(struct _malloc_zone_t *zone, const void *ptr);

malloc_introspection_t _OFClobberDetectionZoneIntrospect = {
    _OFClobberDetectionZoneEnumerator,
    _OFClobberDetectionZoneGoodSize,
    _OFClobberDetectionZoneCheck,
    _OFClobberDetectionZonePrint,
    _OFClobberDetectionZoneLog,
    _OFClobberDetectionZoneForceLock,
    _OFClobberDetectionZoneForceUnlock
};

typedef struct _OFClobberDetectionBlock {
    vm_size_t  size;
    void      *page;
    void      *next;  // for when this is in a linked list
} OFClobberDetectionBlock;


typedef struct _OFClobberDetectionZone {
    malloc_zone_t   basicZone;
#ifdef USE_MUTEX
    pthread_mutex_t  lock;
#else
    OFSimpleLockType lock;
#endif

    // All the blocks that are currently live live in this tree.
    // The btree actually holds pointers to the blocks, meaning that we have
    // to pass it pointers to pointers (and it returns them).
    OFBTree allocatedTree;

    // A free list of empty block headers
    OFClobberDetectionBlock *freeHeaders;

    // All the blocks in each of these queues owns N pages of memory where 
    // N is the index in the queue plus one (so all the entries in slot
    // zero are one page entries).
    OFClobberDetectionBlock *freeQueues[SMALL_ALLOCATION_SLOTS];
    
    // All the blocks in this queue are deallocated and marked invalid.  The slot
    // at ageingIndex is where the next freed block will get placed (and if there
    // is a block there, it will get resurrected and put in the right free list
    // (or if it is too big for any of the free lists, it's memory will get deallocate
    // end the empty header will be put on the freeHeaders list).
    OFClobberDetectionBlock *ageingList[BLOCK_AGEING_LENGTH];
    unsigned int             ageingIndex;
} OFClobberDetectionZone;

static BOOL _OFClobberDetectionZoneLogEnabled = NO;
static BOOL _OFClobberDetectionZoneShowBTreeOps = NO;
static BOOL _OFClobberDetectionZoneKeepDeallocatedBlocks = NO;
static malloc_zone_t *_OFClobberDetectionZoneCreate(void);
static malloc_zone_t *_OFClobberDetectionZoneDefault = NULL;
static void *_OFClobberDetectionZeroBlock = NULL;
static task_t _OFClobberDetectionTask = TASK_NULL;
static void _locked_OFClobberDetectionZonePrint(OFClobberDetectionZone *z, int debugLevel);


static void _OFClobberAbort(OFClobberDetectionZone *z) __attribute__ ((noreturn));
static void _OFClobberAbort(OFClobberDetectionZone *z)
{
    if (z)
        _locked_OFClobberDetectionZonePrint(z, 99);
    malloc_printf("OFClobberDetectionZone error ... waiting for debugger to attach to pid %d\n", getpid());
    while (1) {
        sleep(2);
    }
}

static inline void LOG(OFClobberDetectionZone *z, const char *str, void *ptr)
{
    if (!_OFClobberDetectionZoneLogEnabled)
        return;
    if (ptr)
        malloc_printf("Zone=0x%x Ptr=0x%x -- %s\n", z, ptr, str);
    else
        malloc_printf("Zone=0x%x -- %s\n", z, str);
}

malloc_zone_t *OFClobberDetectionZoneCreate(void)
{
    malloc_zone_t *zone;

    zone = _OFClobberDetectionZoneCreate();
    malloc_zone_register(zone);
    return zone;
}

#define stack_logging_type_free	0
#define stack_logging_type_generic	1
#define stack_logging_type_alloc	2
#define stack_logging_type_dealloc	4
#define	stack_logging_flag_zone		8
#define	stack_logging_flag_calloc	16
#define stack_logging_flag_object 	32
#define stack_logging_flag_cleared	64
#define stack_logging_flag_handle	128
#define stack_logging_flag_set_handle_size	256

#define MALLOC_LOG_TYPE_ALLOCATE	stack_logging_type_alloc
#define MALLOC_LOG_TYPE_DEALLOCATE	stack_logging_type_dealloc
#define MALLOC_LOG_TYPE_HAS_ZONE	stack_logging_flag_zone
#define MALLOC_LOG_TYPE_CLEARED		stack_logging_flag_cleared

typedef void (malloc_logger_t)(unsigned type, unsigned arg1, unsigned arg2, unsigned arg3, unsigned result, unsigned num_hot_frames_to_skip);
extern malloc_logger_t *malloc_logger;

#if 0

static void _OFMallocLogger(unsigned type, unsigned arg1, unsigned arg2, unsigned arg3, unsigned result, unsigned num_hot_frames_to_skip)
{
    switch (type) {
    case MALLOC_LOG_TYPE_ALLOCATE | MALLOC_LOG_TYPE_HAS_ZONE:
        malloc_printf("[malloc zone=0x%x size=%d ptr=0x%x]\n", arg1, arg2, result);
        break;
    case MALLOC_LOG_TYPE_ALLOCATE | MALLOC_LOG_TYPE_HAS_ZONE | MALLOC_LOG_TYPE_CLEARED:
        malloc_printf("[calloc zone=0x%x size=%d ptr=0x%x]\n", arg1, arg2, result);
        break;
    case MALLOC_LOG_TYPE_ALLOCATE | MALLOC_LOG_TYPE_DEALLOCATE | MALLOC_LOG_TYPE_HAS_ZONE:
        malloc_printf("[realloc zone=0x%x oldPtr=0x%x size=%d ptr=0x%x]\n", arg1, arg2, arg3, result);
        break;
    case MALLOC_LOG_TYPE_DEALLOCATE | MALLOC_LOG_TYPE_HAS_ZONE:
        malloc_printf("[free zone=0x%x ptr=0x%x]\n", arg1, arg2);
        break;
    default:
        malloc_printf("[???? type=%d arg1=0x%x arg2=0x%x arg3=0x%x result=0x%x\n", type, arg1, arg2, arg3, result);
        break;
    }
}

#endif

//#define USE_CLOBBER_ZONE_AS_DEFAULT_ZONE
#ifdef USE_CLOBBER_ZONE_AS_DEFAULT_ZONE
#warning **************************************
#warning **** USING OFClobberDetectionZone ****
#warning **************************************
void OFUseClobberDetectionZoneAsDefaultZone()  __attribute__ ((constructor));

#endif

static malloc_zone_t *originalDefaultZone = NULL;

void OFUseClobberDetectionZoneAsDefaultZone()
{
    extern unsigned malloc_num_zones;
    extern malloc_zone_t **malloc_zones;
    unsigned int clobberZoneIndex;

    malloc_printf("**************************************\n");
    malloc_printf("**** USING OFClobberDetectionZone ****\n");
    malloc_printf("**************************************\n");
    
    if (_OFClobberDetectionZoneDefault)
        return;
        
    _OFClobberDetectionZoneDefault = OFClobberDetectionZoneCreate();

    // The default zone should be at index zero.
    originalDefaultZone = malloc_default_zone();
    if (malloc_zones[0] != originalDefaultZone) {
        malloc_printf("OFUseClobberDetectionZoneAsDefaultZone -- Was expecting the default zone to be at index zero!\n");
        return;
    }
    
    // Find where the our zone got registered
    for (clobberZoneIndex = 0; clobberZoneIndex < malloc_num_zones; clobberZoneIndex++) {
        if (malloc_zones[clobberZoneIndex] == _OFClobberDetectionZoneDefault)
            break;
    }
    
    if (clobberZoneIndex == malloc_num_zones) {
        malloc_printf("OFUseClobberDetectionZoneAsDefaultZone -- Unable to find zone index for clobber zone!\n");
        return;
    }
    
    // Swap the zones to make our zone the default zone
    malloc_zones[0] = _OFClobberDetectionZoneDefault;
    malloc_zones[clobberZoneIndex] = originalDefaultZone;
}


static void OFClobberDetectionZoneError(OFClobberDetectionZone *zone, const char *function, const char *msg, const void *ptr)
{
    if (ptr) {
        malloc_printf("*** OFClobberDetectionZone[%d], %s: error for block %p: %s\n", getpid(), function, ptr, msg);
    } else {
        malloc_printf("*** OFClobberDetectionZone[%d], %s: error: %s\n", getpid(), function, msg);
    }
    _OFClobberAbort(zone);
}

#define ERROR(zone,msg,ptr) OFClobberDetectionZoneError(zone,__PRETTY_FUNCTION__,msg,ptr)

static inline void *allocate_pages(OFClobberDetectionZone *zone, size_t size)
{
    kern_return_t	err;
    vm_address_t	addr;
    size_t		allocation_size = round_page(size);
    
    malloc_printf("size=%d, allocation_size=%d\n", size, allocation_size);
    if (!allocation_size) allocation_size = vm_page_size;
    err = vm_allocate(_OFClobberDetectionTask, &addr, allocation_size, 1);
    if (err) {
        ERROR(zone, "Can't allocate pages", NULL);
        return NULL;
    }
    return (void *)addr;
}

static inline void deallocate_pages(OFClobberDetectionZone *zone, void *addr, size_t size)
{
    kern_return_t	err;
    err = vm_deallocate(_OFClobberDetectionTask, (vm_address_t)addr, size);
    if (err) {
        ERROR(zone, "Can't deallocate_pages pages", addr);
    }
}

static inline void copy_pages(OFClobberDetectionZone *zone, const void *source, void *dest, size_t size)
{
    kern_return_t err;
    err = vm_copy(_OFClobberDetectionTask, (vm_address_t)source, size, (vm_address_t)dest);
    if (err) {
        ERROR(zone, "Can't copy_pages page", (void *)source);
    }
}

static inline void protect_pages(OFClobberDetectionZone *zone, void *addr, size_t size, vm_prot_t prot)
{
    kern_return_t err;
    err = vm_protect(_OFClobberDetectionTask, (vm_address_t)addr, size, FALSE, prot);
    if (err) {
        ERROR(zone, "Can't disable_pages pages", (void *)addr);
    }
}

static inline void disable_pages(OFClobberDetectionZone *zone, void *addr, size_t size)
{
    protect_pages(zone, addr, size, VM_PROT_NONE);
}


#define BTREE_NODE_SIZE (vm_page_size)

static void *_allocateTreeNode(struct _OFBTree *tree)
{
    return allocate_pages((OFClobberDetectionZone *)tree->userInfo, BTREE_NODE_SIZE);
}

static void _deallocateTreeNode(struct _OFBTree *tree, void *node)
{
    deallocate_pages((OFClobberDetectionZone *)tree->userInfo, node, BTREE_NODE_SIZE);
}

static int _compareBlockAddresses(struct _OFBTree *tree, const void *elementA, const void *elementB)
{
    // The btree actually holds pointers to the blocks, meaning that we have
    // to pass it pointers to pointers (and it returns them).
    OFClobberDetectionBlock *blockA = *(OFClobberDetectionBlock **)elementA;
    OFClobberDetectionBlock *blockB = *(OFClobberDetectionBlock **)elementB;
    
    // Probably shouldn't do subtraction here ...
    if (blockA->page > blockB->page)
        return 1;
    else if (blockA->page < blockB->page)
        return -1;
    return 0;
}


static malloc_zone_t *_OFClobberDetectionZoneCreate(void)
{
    OFClobberDetectionZone *zone;
    
    if (_OFClobberDetectionTask == TASK_NULL) {
        _OFClobberDetectionTask = mach_task_self();
    }

    if (!_OFClobberDetectionZeroBlock) {
        if (_OFClobberDetectionZoneLogEnabled)
            malloc_printf("*** Creating zero block of size %d\n", ZERO_BLOCK_SIZE);
        _OFClobberDetectionZeroBlock = allocate_pages(NULL, ZERO_BLOCK_SIZE);
        protect_pages(NULL, _OFClobberDetectionZeroBlock, ZERO_BLOCK_SIZE, VM_PROT_READ);
    }
    
    zone = (OFClobberDetectionZone *)allocate_pages(NULL, sizeof(*zone));
    if (!zone)
        return (malloc_zone_t *)zone;
    
    // Assign to the zone this way so that we'll get a warning/error if the
    // layout of the zone struct changes
    zone->basicZone = (malloc_zone_t) {
        NULL, // reserved1
        NULL, // reserved2
        _OFClobberDetectionZoneSize,
        _OFClobberDetectionZoneMalloc,
        _OFClobberDetectionZoneCalloc,
        _OFClobberDetectionZoneValloc,
        _OFClobberDetectionZoneFree,
        _OFClobberDetectionZoneRealloc,
        _OFClobberDetectionZoneDestroy,
        "Clobber Detection Zone",
        NULL, // batch_malloc
        NULL, // batch_free
        &_OFClobberDetectionZoneIntrospect,
        0, // version
    };
    
#ifdef USE_MUTEX
    pthread_mutex_init(&zone->lock, NULL);
#else
    OFSimpleLockInit(&zone->lock);
#endif
    
    OFBTreeInit(&zone->allocatedTree, vm_page_size, sizeof(OFClobberDetectionBlock *), _allocateTreeNode, _deallocateTreeNode, _compareBlockAddresses);
    zone->allocatedTree.userInfo = zone;
    
    LOG(zone, "Created", NULL);
    
    return &zone->basicZone;
}



static inline OFClobberDetectionBlock *_locked_OFClobberDetectionBlockForPointer(OFClobberDetectionZone *z, const void *ptr)
{
    OFClobberDetectionBlock **blockp, key, *keyp;
    
    if (_OFClobberDetectionZoneLogEnabled)
        malloc_printf("Zone=0x%x -- Looking for block for address=0x%x\n", z, ptr);
    
    key.page = (void *)ptr;
    
    // The btree actually holds pointers to the blocks, meaning that we have
    // to pass it pointers to pointers (and it returns them).
    keyp = &key;
    blockp = (OFClobberDetectionBlock **)OFBTreeFind(&z->allocatedTree, &keyp);
    if (_OFClobberDetectionZoneLogEnabled) {
        if (blockp)
            malloc_printf("Zone=0x%x -- Block found at 0x%x\n", z, *blockp);
        else
            malloc_printf("Zone=0x%x -- No block found\n", z);
    }
    
    return blockp ? *blockp : NULL;
}

static kern_return_t _OFClobberDetectionZoneEnumerator(task_t task, void *x, unsigned type_mask, vm_address_t zone_address, memory_reader_t reader, vm_range_recorder_t recorder)
{
    ERROR((OFClobberDetectionZone *)zone_address, "Function not implemented", NULL);
    _OFClobberAbort(NULL);
    return KERN_FAILURE;
}

static size_t	_OFClobberDetectionZoneGoodSize(malloc_zone_t *zone, size_t size)
{
    //ERROR((OFClobberDetectionZone *)zone, "Function not implemented", NULL);
    //_OFClobberAbort(NULL);
    return size;
}



static boolean_t _OFClobberDetectionZoneCheck(malloc_zone_t *zone)
{
    return 0;
}

static inline void _printBlock(OFClobberDetectionBlock *block)
{
    malloc_printf("    [0x%x] 0x%x -- %d\n", block, block->page, block->size);
}

static inline void _printNode(OFBTree *tree, void *element, void *arg)
{
    OFClobberDetectionBlock **blockp;
    
    blockp = element;
    _printBlock(*blockp);
}

static void _locked_OFClobberDetectionZonePrint(OFClobberDetectionZone *z, int debugLevel)
{
    unsigned int slot, count;
    OFClobberDetectionBlock *block;
    
    malloc_printf("\n\nZone=0x%x\n", z);
    malloc_printf("  Allocated Nodes:\n", z);
    
    OFBTreeEnumerate(&z->allocatedTree, _printNode, NULL);
    
    for (slot = 0; slot < SMALL_ALLOCATION_SLOTS; slot++) {
        block = z->freeQueues[slot];
        if (block) {
            if (debugLevel == 1) {
                count = 0;
                while (block) {
                    count++;
                    block = block->next;
                }
                malloc_printf("  Small Allocation Free List (%d pages) -- %d entries\n", slot + 1, count);
            } else if (debugLevel > 1) {
                malloc_printf("  Small Allocation Free List (%d pages)\n", slot + 1);
                while (block) {
                    _printBlock(block);
                    block = block->next;
                }
            }
        }
    }

    malloc_printf("  Ageing queue: (head = %d)\n", z->ageingIndex);
    for (slot = z->ageingIndex; slot < BLOCK_AGEING_LENGTH; slot++) {
        block = z->ageingList[slot];
        if (!block)
            break;
        _printBlock(block);
    }
    for (slot = 0; slot < z->ageingIndex; slot++) {
        block = z->ageingList[slot];
        if (!block)
            break;
        _printBlock(block);
    }
        
    malloc_printf("\n\n");
}

static void _OFClobberDetectionZonePrint(malloc_zone_t *zone, boolean_t verbose)
{
    OFClobberDetectionZone *z = (OFClobberDetectionZone *)zone;
    
    ZLOCK(z);
    _locked_OFClobberDetectionZonePrint(z, verbose);
    ZUNLOCK(z);
}

static void _OFClobberDetectionZoneLog(malloc_zone_t *zone, void *address)
{
    ERROR((OFClobberDetectionZone *)zone, "Function not implemented", NULL);
    _OFClobberAbort(NULL);
}

static void _OFClobberDetectionZoneForceLock(malloc_zone_t *zone)
{
    ZLOCK(((OFClobberDetectionZone *)zone));
}

static void _OFClobberDetectionZoneForceUnlock(malloc_zone_t *zone)
{
    ZUNLOCK(((OFClobberDetectionZone *)zone));
}

static inline OFClobberDetectionBlock *
_locked_OFClobberDetectionZoneGetHeader(OFClobberDetectionZone *z)
{
    OFClobberDetectionBlock *header;
    
    if (!z->freeHeaders) {
        unsigned int headerCount;
        OFClobberDetectionBlock *head;
        
        // Need to populate the list with some more headers
        head = allocate_pages(z, vm_page_size * 16);
        headerCount = (vm_page_size * 16) / sizeof(*header);
        header = head;
        
        // Link up all the headers
        while (headerCount--) {
            header->next = header + 1;
            header = header + 1;
        }
        
        // The last one really doesn't have anything after it
        header--;
        header->next = NULL;
        
        // Replenish the list
        z->freeHeaders = head;
    }
    
    header = z->freeHeaders;
    z->freeHeaders = header->next;
    
    return header;
}


#define MIN_PAGES_TO_ALLOCATE   (1024)
#define MIN_BLOCKS_TO_ALLOCATE  (4)

static inline OFClobberDetectionBlock *
_locked_OFClobberDetectionZoneGetSmallBlock(OFClobberDetectionZone *z, unsigned int pageCount)
{
    OFClobberDetectionBlock *block;

    if (pageCount > SMALL_ALLOCATION_SLOTS)
        return NULL;
        
    if (!z->freeQueues[pageCount - 1]) {
        unsigned int pagesToAllocate;
        void *pages;
        
        // Need to populate the free queue with some more entries
        if ((pagesToAllocate = pageCount * MIN_BLOCKS_TO_ALLOCATE) < MIN_PAGES_TO_ALLOCATE)
            pagesToAllocate = MIN_PAGES_TO_ALLOCATE;
        
        // Make sure that we allocate a multiple of the amount we're going to use
        if (pagesToAllocate % pageCount) {
            pagesToAllocate = pageCount * (pagesToAllocate/pageCount + 1);
        }
        
        pages = allocate_pages(z, pagesToAllocate * vm_page_size);
        while (pagesToAllocate) {
            block = _locked_OFClobberDetectionZoneGetHeader(z);
            block->page = pages;
            block->next = z->freeQueues[pageCount - 1];
            z->freeQueues[pageCount - 1] = block;
            
            pages += vm_page_size * pageCount;
            pagesToAllocate -= pageCount;
        }
    }
    
    block = z->freeQueues[pageCount - 1];
    z->freeQueues[pageCount - 1] = block->next;
    
    return block;
}

// Since we always return page aligned blocks, we can use this for valloc as well as normal allocation
static inline void *_locked_OFClobberDetectionZoneMalloc(OFClobberDetectionZone *z, size_t size)
{

    OFClobberDetectionBlock *block;
    size_t pageSize;
    unsigned int pageCount;
    
    // Give something back even if they ask for zero bytes
    if (size < MIN_ALLOCATION)
        size = MIN_ALLOCATION;
    
    pageSize = round_page(size);
    pageCount = pageSize / vm_page_size;
    
    // Grab an entry out of one of our small block free lists, if possible
    block = _locked_OFClobberDetectionZoneGetSmallBlock(z, pageCount);
    if (!block) {
        // Too big for our free lists.
        block = _locked_OFClobberDetectionZoneGetHeader(z);
        block->size = size;
        block->page = allocate_pages(z, pageSize);
    }

    // Record the size of the block
    block->size = size;
    
    // The btree actually holds pointers to the blocks, meaning that we have
    // to pass it pointers to pointers (and it returns them).
    if (_OFClobberDetectionZoneShowBTreeOps) {
        malloc_printf("insert(0x%x [0x%x %d])\n", block, block->page, block->size);
    }
    OFBTreeInsert(&z->allocatedTree, &block);

    if (_OFClobberDetectionZoneLogEnabled)
        malloc_printf("Zone=0x%x -- Allocated pointer=0x%x with size=%d\n", z, block->page, size);
    
    return block->page;
}

static void *_OFClobberDetectionZoneMalloc(struct _malloc_zone_t *zone, size_t size)
{
    OFClobberDetectionZone *z = (OFClobberDetectionZone *)zone;
    void *ptr;

    ZLOCK(z);
    if (_OFClobberDetectionZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Malloc(%d)\n", zone, size);
    ptr = _locked_OFClobberDetectionZoneMalloc(z, size);
    ZUNLOCK(z);
    
    return ptr;
}

// Always return page aligned, zero filled blocks so this is really the same as malloc for us.
static void *_OFClobberDetectionZoneValloc(struct _malloc_zone_t *zone, size_t size)
{
    OFClobberDetectionZone *z = (OFClobberDetectionZone *)zone;
    void *ptr;

    ZLOCK(z);
    if (_OFClobberDetectionZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Valloc(%d)\n", zone, size);
    ptr = _locked_OFClobberDetectionZoneMalloc(z, size);
    ZUNLOCK(z);
    
    return ptr;
}


static inline void _locked_OFClobberDetectionBlockMarkDeallocated(OFClobberDetectionZone *z, OFClobberDetectionBlock *block)
{
    vm_size_t size, sizeToZero, sizeToCopy;
    void *page, *pageToZero;
    OFClobberDetectionBlock *ageBlock;
    
    size = round_page(block->size);
    page = block->page;

    // The btree actually holds pointers to the blocks, meaning that we have
    // to pass it pointers to pointers (and it returns them).
    if (_OFClobberDetectionZoneShowBTreeOps) {
        malloc_printf("delete(0x%x [0x%x %d])\n", block, block->page, block->size);
    }
    if (!OFBTreeDelete(&z->allocatedTree, &block)) {
        ERROR(z, "Unable to remove block from btree", block);
        abort();
    }
    
    if (!_OFClobberDetectionZoneKeepDeallocatedBlocks) {
        unsigned int pageCount;

        // Zero the page (w/o a system call) and put it on the head of the free list
        pageCount = size / vm_page_size;
        if (pageCount > SMALL_ALLOCATION_SLOTS) {
            // Big allocation.  Just toss the memory.
            deallocate_pages(z, page, size);
            
            // Put the empty header on the free header list
            block->next = z->freeHeaders;
            z->freeHeaders = block;
        } else {
            // Zero the page
            memset(page, 0, size);
            
            // Put the block on the free list for this page count
            block->next = z->freeQueues[pageCount - 1];
            z->freeQueues[pageCount - 1] = block;
        }
        
        return;
    }
    
    // Empty a slot on the ageing list if there is something in the head slot
    ageBlock = z->ageingList[z->ageingIndex];
    if (ageBlock) {
        unsigned int pageSize, pageCount;
        
        if (!z->ageingIndex) {
            malloc_printf("Looped on ageing list\n");
        }
        
        pageSize = round_page(ageBlock->size);
        pageCount = pageSize / vm_page_size;
        if (pageCount > SMALL_ALLOCATION_SLOTS) {
            // Big allocation.  Just toss the memory now that it's been aged.
            deallocate_pages(z, ageBlock->page, pageSize);
            
            // Put the empty header on the free header list
            ageBlock->next = z->freeHeaders;
            z->freeHeaders = ageBlock;
        } else {
            // Make the pages writeable again.  They were already zeroed when first freed.
            protect_pages(z, ageBlock->page, pageSize, VM_PROT_READ | VM_PROT_WRITE);
            
            // Put the block on the free list for this page count
            ageBlock->next = z->freeQueues[pageCount - 1];
            z->freeQueues[pageCount - 1] = ageBlock;
        }
    }

    // Put this block on the ageing list
    z->ageingList[z->ageingIndex] = block;
    z->ageingIndex++;
    if (z->ageingIndex == BLOCK_AGEING_LENGTH)
        z->ageingIndex = 0;
    
    // Fill the block with COW zero pages so they no longer take up any physical memory.  ZERO_BLOCK_SIZE is big enough that we can do this in one kernel call for all of our 'short' blocks.
    sizeToZero = size;
    pageToZero = page;
    while (sizeToZero) {
        sizeToCopy = MIN(sizeToZero, ZERO_BLOCK_SIZE);
        copy_pages(z, _OFClobberDetectionZeroBlock, page, sizeToCopy);
        sizeToZero -= sizeToCopy;
        pageToZero += sizeToCopy;
    }
        
    // Mark the pages unreadable and unwritable to catch any access after having been freed
    disable_pages(z, page, size);
}


static void _OFClobberDetectionZoneFree(struct _malloc_zone_t *zone, void *ptr)
{
    OFClobberDetectionZone *z = (OFClobberDetectionZone *)zone;
    OFClobberDetectionBlock *block;
        
    ZLOCK(z);

    if (_OFClobberDetectionZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Free ptr=0x%x\n", zone, ptr);

    if (!ptr) {
        ZUNLOCK(z);
        return;
    }
    block = _locked_OFClobberDetectionBlockForPointer(z, ptr);
    if (!block) {
#warning TODO: Try to avoid this problem
        if ((unsigned int)ptr == round_page((unsigned int)ptr)) {
            ERROR(z, "Cannot find block for pointer.  Attempt to free a pointer that isn't part of the zone (or has already been freed)", ptr);
        } else {
            malloc_printf("Cannot find block for pointer 0x%x to free it, but since it isn't page aligned, its probably from the old default malloc zone -- we'll just leak it\n");
        }
    } else {
        _locked_OFClobberDetectionBlockMarkDeallocated(z, block);
    }
    
    ZUNLOCK(z);
    return;
}

static void *_OFClobberDetectionZoneRealloc(struct _malloc_zone_t *zone, void *ptr, size_t size)
{
    OFClobberDetectionZone *z = (OFClobberDetectionZone *)zone;
    OFClobberDetectionBlock *block;
    void *newPointer = NULL;
    size_t copySize;
        
    ZLOCK(z);
    
    if (_OFClobberDetectionZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Realloc pointer=0x%x newSize=%d\n", zone, ptr, size);


    block = _locked_OFClobberDetectionBlockForPointer(z, ptr);
    if (ptr && !block) {
        // If this pointer is owned by the old default malloc zone, free it from the old zone and do the new allocation in our zone.
        if (malloc_zone_from_ptr(ptr) == originalDefaultZone) {
            ZUNLOCK(z);
            if (size) {
                size_t oldSize = malloc_size(ptr);
                newPointer = _OFClobberDetectionZoneMalloc(zone, size);
                memcpy(newPointer, ptr, oldSize);
            } else {
                newPointer = NULL;
            }
            malloc_zone_free(originalDefaultZone, ptr);
            return newPointer;
        }
        
        malloc_printf("ptr = 0x%x\n", ptr);
        malloc_printf("originalDefaultZone = 0x%x\n", originalDefaultZone);
        malloc_printf("malloc_zone_from_ptr(ptr) = 0x%x\n", malloc_zone_from_ptr(ptr));
        
        ERROR(z, "Attempted to realloc a pointer not owned by this zone", block);
        goto done;
    }

    newPointer = _locked_OFClobberDetectionZoneMalloc(z, size);

    // Copy the old contents (if any -- ptr might be NULL in which case this is basically a malloc)
    if (block) {
        copySize = MIN(size, block->size);
        copy_pages(z, ptr, newPointer, copySize);
        
        _locked_OFClobberDetectionBlockMarkDeallocated(z, block);
    }


done:
    ZUNLOCK(z);
    return newPointer;
}

static void _OFClobberDetectionZoneDestroy(struct _malloc_zone_t *zone)
{
    ERROR((OFClobberDetectionZone *)zone, "Function not implemented", NULL);
    _OFClobberAbort(NULL);
}

static void *_OFClobberDetectionZoneCalloc(struct _malloc_zone_t *zone, size_t num_items, size_t size)
{
    OFClobberDetectionZone *z = (OFClobberDetectionZone *)zone;
    void *ptr;
    
    ZLOCK(z);
    
    if (_OFClobberDetectionZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Calloc count=%d, size=%d (total size = %d)\n",
                      z, num_items, size, num_items * size);
    ptr = _locked_OFClobberDetectionZoneMalloc(z, num_items * size);
    
    ZUNLOCK(z);
    
    return ptr;
}

static size_t _OFClobberDetectionZoneSize(struct _malloc_zone_t *zone, const void *ptr)
{
    OFClobberDetectionZone *z = (OFClobberDetectionZone *)zone;
    OFClobberDetectionBlock *block;
    vm_size_t size = 0;
    
    if (!ptr)
        return 0;
        
    if ((vm_address_t)ptr != round_page((vm_address_t)ptr))
        // not page aligned -- it can't be us
        return 0;
        
    ZLOCK(z);

    if (_OFClobberDetectionZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Looking for size for pointer=0x%x\n", z, ptr);

    block = _locked_OFClobberDetectionBlockForPointer(z, ptr);
    if (block)
        size = block->size;
    else
        size = 0;
        
    ZUNLOCK(z);

    if (_OFClobberDetectionZoneLogEnabled)
        malloc_printf("Zone=0x%x -- pointer=0x%x has size=%d\n", z, ptr, size);
    return size;
}

