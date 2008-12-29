// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFNoFreeDebugZone.h>

#import <OmniFoundation/OFSimpleLock.h>

#import <unistd.h>
#import <pthread.h>

RCS_ID("$Id$")


#define USE_MUTEX

static kern_return_t _OFNoFreeDebugZoneEnumerator(task_t task, void *, unsigned type_mask, vm_address_t zone_address, memory_reader_t reader, vm_range_recorder_t recorder);
static size_t	_OFNoFreeDebugZoneGoodSize(malloc_zone_t *zone, size_t size);
static boolean_t 	_OFNoFreeDebugZoneCheck(malloc_zone_t *zone);
static void 	_OFNoFreeDebugZonePrint(malloc_zone_t *zone, boolean_t verbose);
static void	_OFNoFreeDebugZoneLog(malloc_zone_t *zone, void *address);
static void	_OFNoFreeDebugZoneForceLock(malloc_zone_t *zone);
static void	_OFNoFreeDebugZoneForceUnlock(malloc_zone_t *zone);

static void *_OFNoFreeDebugZoneRealloc(struct _malloc_zone_t *zone, void *ptr, size_t size);
static void *_OFNoFreeDebugZoneMalloc(struct _malloc_zone_t *zone, size_t size);
static void _OFNoFreeDebugZoneFree(struct _malloc_zone_t *zone, void *ptr);
static void _OFNoFreeDebugZoneDestroy(struct _malloc_zone_t *zone);
static void *_OFNoFreeDebugZoneCalloc(struct _malloc_zone_t *zone, size_t num_items, size_t size);
static size_t _OFNoFreeDebugZoneSize(struct _malloc_zone_t *zone, const void *ptr);

malloc_introspection_t _OFNoFreeDebugZoneIntrospect = {
    _OFNoFreeDebugZoneEnumerator,
    _OFNoFreeDebugZoneGoodSize,
    _OFNoFreeDebugZoneCheck,
    _OFNoFreeDebugZonePrint,
    _OFNoFreeDebugZoneLog,
    _OFNoFreeDebugZoneForceLock,
    _OFNoFreeDebugZoneForceUnlock
};

#define MAGIC(ptr) ((unsigned int)ptr ^ 0xcafebabe)

typedef struct _OFNoFreeDebugBlockHeader {
    unsigned int magic;
    unsigned int size: 31;
    unsigned int deallocated:1;
} OFNoFreeDebugBlockHeader;

typedef struct _OFNoFreeDebugBlock {
    OFNoFreeDebugBlockHeader header;
    unsigned char data[0];
} OFNoFreeDebugBlock;

typedef struct _OFNoFreeDebugDeallocatedBlock {
    OFNoFreeDebugBlockHeader header;
    unsigned int checksum;
    unsigned char data[0];
} OFNoFreeDebugDeallocatedBlock;

typedef struct _OFNoFreeDebugRegion {
    vm_size_t size;
    vm_size_t spaceUsed;
    OFNoFreeDebugBlock blocks[0];
} OFNoFreeDebugRegion;

typedef struct _OFNoFreeDebugZone {
    malloc_zone_t   basicZone;
#ifdef USE_MUTEX
    pthread_mutex_t  lock;
#else
    OFSimpleLockType lock;
#endif

    OFNoFreeDebugRegion **regions;
    unsigned int          regionsCount;
    unsigned int          regionsSize;
} OFNoFreeDebugZone;

static malloc_zone_t *_OFNoFreeDebugZoneCreate();

#define ROUND_ALLOCATION(x)   ((x + (sizeof(unsigned int) - 1)) & ~(sizeof(unsigned int) - 1))
#define MIN_ALLOCATION        ROUND_ALLOCATION(sizeof(OFNoFreeDebugDeallocatedBlock))

#ifdef USE_MUTEX
#define ZLOCK(zone) pthread_mutex_lock(&zone->lock)
#define ZUNLOCK(zone) pthread_mutex_unlock(&zone->lock)
#else
#define ZLOCK(zone) OFSimpleLock(&zone->lock)
#define ZUNLOCK(zone) OFSimpleUnlock(&zone->lock)
#endif

static BOOL _OFNoFreeDebugZoneLogEnabled = NO;

static inline void LOG(OFNoFreeDebugZone *z, const char *str, void *ptr)
{
    if (!_OFNoFreeDebugZoneLogEnabled)
        return;
    if (ptr)
        malloc_printf("Zone=0x%x Ptr=0x%x -- %s\n", z, ptr, str);
    else
        malloc_printf("Zone=0x%x -- %s\n", z, str);
}

malloc_zone_t *OFNoFreeDebugZoneCreate()
{
    malloc_zone_t *zone;

    zone = _OFNoFreeDebugZoneCreate();
    malloc_zone_register(zone);
    return zone;
}

static malloc_zone_t *_OFNoFreeDebugZoneDefault = NULL;

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

void OFUseNoFreeDebugZoneAsDefaultZone()
{
    malloc_zone_t *defaultZone;
    extern unsigned malloc_num_zones;
    extern malloc_zone_t **malloc_zones;

#if 1
//    malloc_logger = _OFMallocLogger;
    return;
#endif

    if (_OFNoFreeDebugZoneDefault)
        return;
        
    if (malloc_num_zones != 1) {
        malloc_printf("OFUseNoFreeDebugZoneAsDefaultZone -- Too late, there are %d zones registered!\n", malloc_num_zones);
        return;
    }
    if (malloc_zones[0] != malloc_default_zone()) {
        malloc_printf("OFUseNoFreeDebugZoneAsDefaultZone -- Was expecting zone zero to be the default zone!\n");
        return;
    }
    
    // This will register the zone in slot 1
    _OFNoFreeDebugZoneDefault = OFNoFreeDebugZoneCreate();
    
    if (malloc_num_zones != 2) {
        malloc_printf("OFUseNoFreeDebugZoneAsDefaultZone -- Was expecting two zones to be registered!\n");
        return;
    }
    if (malloc_zones[1] != _OFNoFreeDebugZoneDefault) {
        malloc_printf("OFUseNoFreeDebugZoneAsDefaultZone -- Was expecting zone one to be the new zone!\n");
        return;
    }
    
    // Swap the zones to make our zone the default zone
    defaultZone = malloc_zones[0];
    malloc_zones[0] = _OFNoFreeDebugZoneDefault;
    malloc_zones[1] = defaultZone;
}


static void OFNoFreeDebugZoneError(OFNoFreeDebugZone *zone, const char *function, const char *msg, const void *ptr)
{
    if (ptr) {
        malloc_printf("*** OFNoFreeDebugZone[%d], %s: error for block %p: %s\n", getpid(), function, ptr, msg);
    } else {
        malloc_printf("*** OFNoFreeDebugZone[%d], %s: error: %s\n", getpid(), function, msg);
    }
    abort();
}

#define ERROR(zone,msg,ptr) OFNoFreeDebugZoneError(zone,__PRETTY_FUNCTION__,msg,ptr)

static vm_address_t allocate_pages(OFNoFreeDebugZone *zone, size_t size)
{
    kern_return_t	err;
    vm_address_t	addr;
    size_t		allocation_size = round_page(size);
    if (!allocation_size) allocation_size = vm_page_size;
    err = vm_allocate(mach_task_self(), &addr, allocation_size, 1);
    if (err) {
        ERROR(zone, "Can't allocate region", NULL);
        return NULL;
    }
    return addr;
}

static void deallocate_pages(OFNoFreeDebugZone *zone, vm_address_t addr, size_t size)
{
    kern_return_t	err;
    err = vm_deallocate(mach_task_self(), addr, size);
    if (err) {
        ERROR(zone, "Can't deallocate_pages region", (void *)addr);
    }
}


static malloc_zone_t *_OFNoFreeDebugZoneCreate()
{
    OFNoFreeDebugZone *zone;
    
    zone = (OFNoFreeDebugZone *)allocate_pages(NULL, sizeof(*zone));
    if (!zone)
        return (malloc_zone_t *)zone;
    
    zone->basicZone.realloc = _OFNoFreeDebugZoneRealloc;
    zone->basicZone.malloc = _OFNoFreeDebugZoneMalloc;
    zone->basicZone.calloc = _OFNoFreeDebugZoneCalloc;
    zone->basicZone.free = _OFNoFreeDebugZoneFree;
    zone->basicZone.size = _OFNoFreeDebugZoneSize;
    zone->basicZone.destroy = _OFNoFreeDebugZoneDestroy;
    zone->basicZone.introspect = &_OFNoFreeDebugZoneIntrospect;
    
#ifdef USE_MUTEX
    pthread_mutex_init(&zone->lock, NULL);
#else
    OFSimpleLockInit(&zone->lock);
#endif
    
    zone->regionsSize = vm_page_size / sizeof(*zone->regions);
    zone->regionsCount = 0;
    zone->regions = (OFNoFreeDebugRegion **)allocate_pages(NULL, zone->regionsSize * sizeof(*zone->regions));
    
    LOG(zone, "Created", NULL);
    
    return &zone->basicZone;
}


static inline OFNoFreeDebugRegion *_locked_OFNoFreeDebugRegionForBlock(OFNoFreeDebugZone *zone,
                                                                       OFNoFreeDebugBlock *block)
{
    unsigned int regionIndex;
    
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- Searching for block=0x%x\n", zone, block);
    
    regionIndex = zone->regionsCount;
    while (regionIndex--) {
        OFNoFreeDebugRegion *region;
        
        region = zone->regions[regionIndex];
//        if (_OFNoFreeDebugZoneLogEnabled)
//            malloc_printf("Zone=0x%x --   Looking in region=0x%x (size=%d)\n", zone, region, region->size);

        if (&region->blocks[0] > block)
            continue;
        if ((void *)region + region->size < (void *)block)
            continue;

        if (_OFNoFreeDebugZoneLogEnabled)
            malloc_printf("Zone=0x%x --   Found\n", zone, region, region->size);
        return region;
    }
    
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x --   Not found\n", zone);
    return NULL;
}

static kern_return_t _OFNoFreeDebugZoneEnumerator(task_t task, void *x, unsigned type_mask, vm_address_t zone_address, memory_reader_t reader, vm_range_recorder_t recorder)
{
    ERROR((OFNoFreeDebugZone *)zone_address, "Function not implemented", NULL);
    abort();
}

static size_t	_OFNoFreeDebugZoneGoodSize(malloc_zone_t *zone, size_t size)
{
    ERROR((OFNoFreeDebugZone *)zone, "Function not implemented", NULL);
    abort();
}



static void _locked_OFNoFreeDebugBlockMarkDeallocated(OFNoFreeDebugBlock *block)
{
    OFNoFreeDebugDeallocatedBlock *deadBlock = (OFNoFreeDebugDeallocatedBlock *)block;
    unsigned int *word;
    unsigned int wordCount;
    unsigned int sum;
    
    // Compute a checksum over all the non header/checksum bytes and mess up the bytes
    // in the block to help cause crashes if we try to dereference them.
    deadBlock->header.deallocated = 1;
    word = (unsigned int *)&deadBlock->data[0];
    wordCount = (deadBlock->header.size - sizeof(*deadBlock)) / sizeof(*word);
    
    if ((deadBlock->header.size - sizeof(*deadBlock)) % sizeof(*word))
        abort();

    sum = deadBlock->header.magic ^ deadBlock->header.size;
    while (wordCount--) {
        *word = ~(*word);
        sum ^= *word;
        word++;
    }
    
    // Write the checksum
    deadBlock->checksum = sum;
}

static inline void _OFNoFreeDebugDeallocatedBlockCheck(OFNoFreeDebugZone *z,
                                                       OFNoFreeDebugDeallocatedBlock *deadBlock)
{
    unsigned int *word;
    unsigned int wordCount;
    unsigned int sum;

    // All the normal block stuff has been checked, we just need to check the checksum
    // with the same algorithm as above.
    
    word = (unsigned int *)&deadBlock->data[0];
    wordCount = (deadBlock->header.size - sizeof(*deadBlock)) / sizeof(*word);

    if ((deadBlock->header.size - sizeof(*deadBlock)) % sizeof(*word))
        abort();

    sum = deadBlock->header.magic ^ deadBlock->header.size;
    while (wordCount--) {
        sum ^= *word;
        word++;
    }
    
    if (deadBlock->checksum != sum)
        ERROR(z, "Deallocated block has wrong checksum.", deadBlock);
}
                                                       
#warning Modify the algorithms here to NOT require locking for the check function.
// Right now we have to lock since the pointer to the list of regions could change.

static inline void _OFNoFreeDebugRegionCheck(OFNoFreeDebugZone *z, OFNoFreeDebugRegion *region)
{
    OFNoFreeDebugBlock *block, *lastBlock;

    if (region->size < region->spaceUsed)
        ERROR(z, "Region has larger space used than space available.", NULL);
        
    block = &region->blocks[0];
    lastBlock = (void *)region + region->spaceUsed;
    while (block < lastBlock) {
        if (MAGIC(block) != block->header.magic)
            ERROR(z, "Block has incorrect magic.", block);
        if (!block->header.size)
            ERROR(z, "Block has zero size.", block);
        if ((void *)block + block->header.size > (void *)lastBlock)
            ERROR(z, "Block extends past last block in region.", block);
        if (block->header.deallocated)
            _OFNoFreeDebugDeallocatedBlockCheck(z, (OFNoFreeDebugDeallocatedBlock *)block);
        block = (void *)block + block->header.size;
    }
}

static boolean_t _OFNoFreeDebugZoneCheck(malloc_zone_t *zone)
{
    OFNoFreeDebugZone *z = (OFNoFreeDebugZone *)zone;
    unsigned int regionIndex;
    
    ZLOCK(z);
    for (regionIndex = 0; regionIndex < z->regionsCount; regionIndex++) {
        _OFNoFreeDebugRegionCheck(z, z->regions[regionIndex]);
    }
    ZUNLOCK(z);
    
    return 0;
}

static void _locked_OFNoFreeDebugRegionPrint(OFNoFreeDebugRegion *region, boolean_t verbose)
{
    OFNoFreeDebugBlock *block, *last;
    
    malloc_printf("Region=0x%x Size=%d Space Used=%d\n", region, region->size, region->spaceUsed);
    block = &region->blocks[0];
    last = (void *)region + region->spaceUsed;
    while (block < last) {
        malloc_printf("  Block=0x%x Deallocated=%d Size=%d\n", block, block->header.deallocated, block->header.size);
        block = (void *)block + block->header.size;
    }
}

static void _locked_OFNoFreeDebugZonePrint(OFNoFreeDebugZone *zone, boolean_t verbose)
{
    unsigned int regionIndex;
    
    malloc_printf("\n\nZone=0x%x Regions=0x%x Regions Count=%d Regions Size=%d\n",
                  zone, zone->regions, zone->regionsCount, zone->regionsSize);
    
    for (regionIndex = 0; regionIndex < zone->regionsCount; regionIndex++)
        _locked_OFNoFreeDebugRegionPrint(zone->regions[regionIndex], verbose);
        
    malloc_printf("\n\n");
}

static void _OFNoFreeDebugZonePrint(malloc_zone_t *zone, boolean_t verbose)
{
    OFNoFreeDebugZone *z = (OFNoFreeDebugZone *)zone;
    
    ZLOCK(z);
    _locked_OFNoFreeDebugZonePrint(z, verbose);
    ZUNLOCK(z);
}

static void _OFNoFreeDebugZoneLog(malloc_zone_t *zone, void *address)
{
    ERROR((OFNoFreeDebugZone *)zone, "Function not implemented", NULL);
    abort();
}

static void _OFNoFreeDebugZoneForceLock(malloc_zone_t *zone)
{
    ZLOCK(((OFNoFreeDebugZone *)zone));
}

static void _OFNoFreeDebugZoneForceUnlock(malloc_zone_t *zone)
{
    ZUNLOCK(((OFNoFreeDebugZone *)zone));
}

static OFNoFreeDebugRegion *_locked_OFNoFreeDebugZoneCreateNewRegion(OFNoFreeDebugZone *z, size_t regionSize)
{
    OFNoFreeDebugRegion *region;
    
    region = (OFNoFreeDebugRegion *)allocate_pages(z, regionSize);
    region->size = regionSize;
    region->spaceUsed = sizeof(OFNoFreeDebugRegion);
    
    // Make sure we have room for the region
    if (z->regionsCount == z->regionsSize) {
        vm_size_t newSize;
        OFNoFreeDebugRegion **oldRegions;
        
        oldRegions = z->regions;
        newSize = z->regionsSize * 2;
        z->regions = (OFNoFreeDebugRegion **)allocate_pages(z, newSize * sizeof(*z->regions));
        // TJW -- could do a vm_copy here
        memcpy(z->regions, oldRegions, z->regionsCount * sizeof(*z->regions));
        deallocate_pages(z, (vm_address_t)oldRegions, z->regionsSize * sizeof(*z->regions));
        z->regionsSize = newSize;
    }
    
    // Store the new region
    z->regions[z->regionsCount] = region;
    z->regionsCount++;
    
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- Created new region=0x%x with size=%d\n", z, region, region->size);
        
    return region;
}

#warning TJW: In Public Beta there is no valloc hook (this is in Darwin now though).  If we get a page aligned size, we will just assume that valloc was called and return a page aligned result (with a wasteful approach).
static inline OFNoFreeDebugBlock *_locked_OFNoFreeDebugZoneMallocBlock(OFNoFreeDebugZone *z, size_t size)
{

    OFNoFreeDebugRegion *region = NULL;
    OFNoFreeDebugBlock *block;
    
    if (size && (size & (vm_page_size - 1)) == 0) {
        size_t regionSize;
        OFNoFreeDebugBlock *fillerBlock, *realBlock;

        // Page aligned size -- return a page aligned result
        if (_OFNoFreeDebugZoneLogEnabled)
            malloc_printf("Zone=0x%x -- Size=0x%x is page aligned -- return a page aligned result\n", z, size);
            
        // We'll do this by allocating an extra page to contain the header.  We'll also
        // put a filler block before the real block and mark it as deallocated.
        
        regionSize = size + vm_page_size;
        region = _locked_OFNoFreeDebugZoneCreateNewRegion(z, regionSize);
        region->size = regionSize;
        region->spaceUsed = regionSize;
        
        fillerBlock = &region->blocks[0];
        fillerBlock->header.magic = MAGIC(fillerBlock);
        fillerBlock->header.size = vm_page_size - sizeof(OFNoFreeDebugRegion) - sizeof(OFNoFreeDebugBlock);
        if (!fillerBlock->header.size)
            abort();
        _locked_OFNoFreeDebugBlockMarkDeallocated(fillerBlock);
        if (_OFNoFreeDebugZoneLogEnabled)
            malloc_printf("Zone=0x%x -- fillerBlock=0x%x\n", z, fillerBlock);

        realBlock = (void *)region + vm_page_size - sizeof(OFNoFreeDebugBlock);
        realBlock->header.magic = MAGIC(realBlock);
        realBlock->header.size = size + sizeof(OFNoFreeDebugBlock);
        if (!realBlock->header.size)
            abort();
            
        if (_OFNoFreeDebugZoneLogEnabled)
            malloc_printf("Zone=0x%x -- realBlock=0x%x\n", z, realBlock);
        
//        _locked_OFNoFreeDebugRegionPrint(region, 1);
        if (_OFNoFreeDebugZoneLogEnabled)
            malloc_printf("Zone=0x%x -- Allocated block=0x%x with size=%d out of region=0x%x\n", z, realBlock, size, region);
        return realBlock;
    }
    
    // Adjust the size to include the header and be rounded correctly
    size = ROUND_ALLOCATION(size + sizeof(OFNoFreeDebugBlockHeader));
    if (size < MIN_ALLOCATION)
        size = MIN_ALLOCATION;
        
    // See if the most recent region has room, always leaving room at the end for a deallocated
    // end block.
    if (z->regionsCount) {
        region = z->regions[z->regionsCount - 1];
        if (region->size - region->spaceUsed < size + sizeof(OFNoFreeDebugDeallocatedBlock)) {
            OFNoFreeDebugBlock *lastBlock;
            
            if (_OFNoFreeDebugZoneLogEnabled)
                malloc_printf("Zone=0x%x -- Last region only has %d bytes -- not enough\n", z, region->size - region->spaceUsed);

            if (region->size - region->spaceUsed) {
                // Mark the end of this region as having been a deallocated object so that
                // we can detect writes to it with our normal code for detecting writes to freed objects
    
                lastBlock = (void *)region + region->spaceUsed;
                lastBlock->header.magic = MAGIC(lastBlock);
                lastBlock->header.size = region->size - region->spaceUsed;
                if (!lastBlock->header.size)
                    abort();
                region->spaceUsed = region->size;
                _locked_OFNoFreeDebugBlockMarkDeallocated(lastBlock);
                //_locked_OFNoFreeDebugRegionPrint(region, 1);
            }
            
            region = NULL;
        } else {
            if (_OFNoFreeDebugZoneLogEnabled)
                malloc_printf("Zone=0x%x -- Last region has %d bytes -- enough\n", z, region->size - region->spaceUsed);
        }
    }
    
    // See if we need a new region
    if (!region) {
        size_t regionSize;
        
        regionSize = size + sizeof(OFNoFreeDebugRegion) + sizeof(OFNoFreeDebugDeallocatedBlock);
        regionSize = round_page(regionSize);
        region = _locked_OFNoFreeDebugZoneCreateNewRegion(z, regionSize);
    }
    
    // We have a region with enough space
    block = (void *)region + region->spaceUsed;

    // Now, verify that the block is all zeros (no one should have written to this space ever)
    {
        unsigned int index, *word;
        
        index = size / sizeof(unsigned int);
        word = (unsigned int *)block;
        while (index--) {
            if (*word) {
                _locked_OFNoFreeDebugRegionPrint(region, 1);
                ERROR((OFNoFreeDebugZone *)z, "Block has already been written to!", block);
            }
            word++;
        }
    }
    
    // Configure the block
    region->spaceUsed += size;
    block->header.magic = MAGIC(block);
    block->header.size = size;
    if (!block->header.size)
        abort();
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- Allocated block=0x%x with size=%d out of region=0x%x\n", z, block, size, region);
    
    return block;
}

static void *_OFNoFreeDebugZoneMalloc(struct _malloc_zone_t *zone, size_t size)
{
    OFNoFreeDebugZone *z = (OFNoFreeDebugZone *)zone;
    OFNoFreeDebugBlock *block;

    ZLOCK(z);
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Malloc(%d)\n", zone, size);
    block = _locked_OFNoFreeDebugZoneMallocBlock(z, size);
    ZUNLOCK(z);
    
    return &block->data[0];
}

static inline BOOL _locked_OFNoFreeDebugBlockIsValid(OFNoFreeDebugZone *z,
                                                     OFNoFreeDebugRegion *region,
                                                     OFNoFreeDebugBlock *block)
{
    OFNoFreeDebugBlock *iterate, *last;
    
    // Iterate through the block in this region to make sure that this is a valid block
    iterate = &region->blocks[0];
    last = (OFNoFreeDebugBlock *)((void *)region + region->spaceUsed);
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- Validating block=0x%x in region=0x%x, searching from block=0x%x to block=0x%x\n",
                      z, block, region, iterate, last);
        
    while (iterate < last) {
//        if (_OFNoFreeDebugZoneLogEnabled)
//            malloc_printf("Zone=0x%x --   Block=0x%x\n", z, iterate);

        if (!iterate->header.size)
            ERROR(z, "Block has zero size", iterate);
        if (iterate->header.magic != MAGIC(iterate))
            ERROR(z, "Block has incorrect magic", iterate);
            
        if (iterate == block) {
            if (_OFNoFreeDebugZoneLogEnabled)
                malloc_printf("Zone=0x%x --   Found\n", z);
            return YES;
        }
        
        iterate = (void *)iterate + iterate->header.size;
    }
    
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- block=0x%x is not valid in region=0x%x\n", z, block, region);
    return NO;
}


static void _OFNoFreeDebugZoneFree(struct _malloc_zone_t *zone, void *ptr)
{
    OFNoFreeDebugZone *z = (OFNoFreeDebugZone *)zone;
    OFNoFreeDebugRegion *region;
    OFNoFreeDebugBlock *block;
    
    block = (void *)ptr - sizeof(OFNoFreeDebugBlock);
    
    ZLOCK(z);
    
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Free block=0x%x\n", zone, block);

    // Find the region for this pointer
    region = _locked_OFNoFreeDebugRegionForBlock(z, block);
    if (!region) {
        ERROR(z, "Cannot find region for pointer.  Attempt to free a pointer that isn't part of the zone", ptr);
        goto done;
    }
    
    if (_locked_OFNoFreeDebugBlockIsValid(z, region, block)) {
        if (block->header.deallocated) {
            ERROR(z, "Attempted to free a block that is already freed", block);
            goto done;
        }
        _locked_OFNoFreeDebugBlockMarkDeallocated(block);
    } else {
        ERROR(z, "Attempted to free a block that isn't valid in its region", block);
        goto done;
    }
    
done:
    ZUNLOCK(z);
    return;
}

static void *_OFNoFreeDebugZoneRealloc(struct _malloc_zone_t *zone, void *ptr, size_t size)
{
    OFNoFreeDebugZone *z = (OFNoFreeDebugZone *)zone;
    OFNoFreeDebugRegion *region = NULL;
    OFNoFreeDebugBlock *block, *newBlock;
    size_t copySize;
    
    block = (void *)ptr - sizeof(OFNoFreeDebugBlock);
    newBlock = NULL;
    
    ZLOCK(z);
    
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Realloc block=0x%x newSize=%d\n", zone, block, size);

    // Find the region for this pointer
    region = _locked_OFNoFreeDebugRegionForBlock(z, block);
    if (!region) {
        ERROR(z, "Cannot find region for block.  Attempt to realloc a block that isn't part of the zone", block);
        goto done;
    }

    if (_locked_OFNoFreeDebugBlockIsValid(z, region, block)) {
        if (block->header.deallocated) {
            ERROR(z, "Attempted to realloc a block that is already freed", block);
            goto done;
        }
    } else {
        ERROR(z, "Attempted to realloc a block that isn't valid in its region", block);
        goto done;
    }

    newBlock = _locked_OFNoFreeDebugZoneMallocBlock(z, size);

    // Copy the old contents
    copySize = MIN(size, block->header.size - sizeof(OFNoFreeDebugBlock));

    memcpy(&newBlock->data[0], &block->data[0], copySize);

    _locked_OFNoFreeDebugBlockMarkDeallocated(block);

done:
    ZUNLOCK(z);
    return &newBlock->data[0];
}

static void _OFNoFreeDebugZoneDestroy(struct _malloc_zone_t *zone)
{
    ERROR((OFNoFreeDebugZone *)zone, "Function not implemented", NULL);
    abort();
}

static void *_OFNoFreeDebugZoneCalloc(struct _malloc_zone_t *zone, size_t num_items, size_t size)
{
    OFNoFreeDebugZone *z = (OFNoFreeDebugZone *)zone;
    OFNoFreeDebugBlock *block;
    
    ZLOCK(z);
    
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Calloc count=%d, size=%d (total size = %d)\n",
                      z, num_items, size, num_items * size);
    block = _locked_OFNoFreeDebugZoneMallocBlock(z, num_items * size);
    
    ZUNLOCK(z);
    
    return &block->data[0];
}

static size_t _OFNoFreeDebugZoneSize(struct _malloc_zone_t *zone, const void *ptr)
{
    OFNoFreeDebugZone *z = (OFNoFreeDebugZone *)zone;
    OFNoFreeDebugRegion *region;
    OFNoFreeDebugBlock *block;
    vm_size_t size;
    
    if (!ptr)
        return 0;
    block = (void *)ptr - sizeof(OFNoFreeDebugBlock);
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- *** Looking for size for block=0x%x\n", z, block);

    ZLOCK(z);
    
    region = _locked_OFNoFreeDebugRegionForBlock(z, block);
    if (region && _locked_OFNoFreeDebugBlockIsValid(z, region, block)) {
        if (block->header.size < sizeof(block->header))
            ERROR(z, "Corrupted block header.  Size is smaller than header size.", block);
        size = block->header.size - sizeof(block->header);
    } else {
        if (_OFNoFreeDebugZoneLogEnabled)
            malloc_printf("Zone=0x%x -- Size requested on invalid block=0x%x -- returning zero\n", zone, block);
        size = 0;
    }
    
    ZUNLOCK(z);
    
    if (_OFNoFreeDebugZoneLogEnabled)
        malloc_printf("Zone=0x%x -- block=0x%x has size=%d\n", z, block, size);
    return size;
}

